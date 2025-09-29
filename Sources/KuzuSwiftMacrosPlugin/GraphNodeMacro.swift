import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct GraphNodeMacro: MemberMacro, ExtensionMacro {
    
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            let diagnostic = Diagnostic(
                node: declaration,
                message: GraphNodeDiagnostic.mustBeAppliedToStruct
            )
            context.diagnose(diagnostic)
            return []
        }
        
        let structName = structDecl.name.text
        let members = structDecl.memberBlock.members
        
        var columns: [(name: String, type: String, constraints: [String])] = []
        var ddlColumns: [String] = []
        var idProperties: [(name: String, location: SyntaxProtocol)] = []
        
        for member in members {
            guard let variableDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = variableDecl.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeAnnotation = binding.typeAnnotation?.type else {
                continue
            }
            
            let propertyName = pattern.identifier.text
            let swiftType = typeAnnotation.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let kuzuType = MacroUtilities.mapSwiftTypeToKuzuType(swiftType)
            
            var constraints: [String] = []
            
            for attribute in variableDecl.attributes {
                guard let attr = attribute.as(AttributeSyntax.self) else { continue }
                let attrName = attr.attributeName.description.trimmingCharacters(in: .whitespacesAndNewlines)
                
                switch attrName {
                case "ID":
                    constraints.append("PRIMARY KEY")
                    idProperties.append((name: propertyName, location: variableDecl))
                case "Index":
                    constraints.append("INDEX")
                case "Vector":
                    if case .argumentList(let args) = attr.arguments {
                        for arg in args {
                            if let expr = arg.expression.as(IntegerLiteralExprSyntax.self) {
                                let dimensions = expr.literal.text
                                // Use FLOAT[] type for vectors (as per Kuzu documentation)
                                columns.append((propertyName, "FLOAT[\(dimensions)]", constraints))
                                // Build DDL column with only supported inline constraints
                                // Escape property name if it's a reserved word
                                let escapedName = KuzuReservedWords.escapeIfNeeded(propertyName)
                                var columnDef = "\(escapedName) FLOAT[\(dimensions)]"
                                for constraint in constraints {
                                    if constraint.hasPrefix("PRIMARY KEY") || constraint.hasPrefix("DEFAULT") {
                                        columnDef += " \(constraint)"
                                    }
                                    // UNIQUE and FULLTEXT are ignored as Kuzu doesn't support them inline
                                }
                                ddlColumns.append(columnDef)
                                continue
                            }
                        }
                    }
                    continue
                case "FullTextSearch":
                    constraints.append("FULLTEXT")
                case "Unique":
                    constraints.append("UNIQUE")
                case "Default":
                    if case .argumentList(let args) = attr.arguments,
                       let firstArg = args.first {
                        let defaultValue = firstArg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
                        // Handle string literals by ensuring they're properly quoted for SQL
                        if defaultValue.hasPrefix("\"") && defaultValue.hasSuffix("\"") {
                            // Convert Swift string literal to SQL string literal
                            let sqlValue = defaultValue.replacingOccurrences(of: "\"", with: "'")
                            constraints.append("DEFAULT \(sqlValue)")
                        } else {
                            // Non-string values (numbers, etc.)
                            constraints.append("DEFAULT \(defaultValue)")
                        }
                    }
                case "Timestamp":
                    // @Timestamp is metadata only, process property normally
                    break
                default:
                    break
                }
            }
            
            if !variableDecl.attributes.contains(where: { 
                if let attr = $0.as(AttributeSyntax.self) {
                    return attr.attributeName.description.trimmingCharacters(in: .whitespacesAndNewlines) == "Vector"
                }
                return false
            }) {
                columns.append((propertyName, kuzuType, constraints))
                
                // Build DDL column with only supported inline constraints
                // Escape property name if it's a reserved word
                let escapedName = KuzuReservedWords.escapeIfNeeded(propertyName)
                var columnDef = "\(escapedName) \(kuzuType)"
                for constraint in constraints {
                    if constraint.hasPrefix("PRIMARY KEY") || constraint.hasPrefix("DEFAULT") {
                        columnDef += " \(constraint)"
                    }
                    // UNIQUE and FULLTEXT are ignored as Kuzu doesn't support them inline
                }
                ddlColumns.append(columnDef)
            }
        }
        
        // Validate ID properties
        if idProperties.isEmpty {
            let diagnostic = Diagnostic(
                node: structDecl.name,
                message: GraphNodeDiagnostic.missingIDProperty
            )
            context.diagnose(diagnostic)
            return []
        }
        
        if idProperties.count > 1 {
            // Create notes for all ID properties
            let notes = idProperties.map { (propertyName, location) in
                Note(
                    node: Syntax(location),
                    message: MacroExpansionNoteMessage("Property '\(propertyName)' is marked with @ID")
                )
            }
            
            let diagnostic = Diagnostic(
                node: structDecl.name,
                message: GraphNodeDiagnostic.duplicatePrimaryKey,
                notes: notes
            )
            context.diagnose(diagnostic)
            return []
        }
        
        let ddl = "CREATE NODE TABLE \(structName) (\(ddlColumns.joined(separator: ", ")))"
        
        let columnsArray = columns.map { column in
            let constraintsArray = column.constraints.map { "\"\($0)\"" }.joined(separator: ", ")
            return "(name: \"\(column.name)\", type: \"\(column.type)\", constraints: [\(constraintsArray)])"
        }.joined(separator: ", ")
        
        return [
            """
            public static let _kuzuDDL: String = "\(raw: ddl)"
            """,
            """
            public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [\(raw: columnsArray)]
            """
        ]
    }
    
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Check if the declaration is a struct
        guard declaration.is(StructDeclSyntax.self) else {
            // Don't generate extension for non-struct types
            return []
        }
        
        let extensionDecl = ExtensionDeclSyntax(
            extendedType: type,
            inheritanceClause: InheritanceClauseSyntax {
                InheritedTypeSyntax(
                    type: TypeSyntax("GraphNodeModel")
                )
            }
        ) {}
        
        return [extensionDecl]
    }
    
}