import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct GraphEdgeMacro: MemberMacro, ExtensionMacro {
    
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            let diagnostic = Diagnostic(
                node: declaration,
                message: GraphEdgeDiagnostic.mustBeAppliedToStruct
            )
            context.diagnose(diagnostic)
            return []
        }
        
        guard case .argumentList(let arguments) = node.arguments,
              arguments.count >= 2,
              let fromArg = arguments.first,
              let toArg = arguments.dropFirst().first else {
            let diagnostic = Diagnostic(
                node: node,
                message: GraphEdgeDiagnostic.missingParameters
            )
            context.diagnose(diagnostic)
            return []
        }
        
        let fromType = fromArg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".self", with: "")
        let toType = toArg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".self", with: "")
        
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
            
            columns.append((propertyName, kuzuType, constraints))
            
            // Escape property name if it's a reserved word
            let escapedName = KuzuReservedWords.escapeIfNeeded(propertyName)
            var columnDef = "\(escapedName) \(kuzuType)"
            for constraint in constraints {
                columnDef += " \(constraint)"
            }
            ddlColumns.append(columnDef)
        }
        
        // Validate ID properties - edges can have zero or one ID property
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
        
        let ddl: String
        if ddlColumns.isEmpty {
            ddl = "CREATE REL TABLE \(structName) (FROM \(fromType) TO \(toType))"
        } else {
            ddl = "CREATE REL TABLE \(structName) (FROM \(fromType) TO \(toType), \(ddlColumns.joined(separator: ", ")))"
        }
        
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
        
        // Check if the macro has the required parameters
        guard case .argumentList(let arguments) = node.arguments,
              arguments.count >= 2 else {
            // Don't generate extension if parameters are missing
            return []
        }
        
        let extensionDecl = ExtensionDeclSyntax(
            extendedType: type,
            inheritanceClause: InheritanceClauseSyntax {
                InheritedTypeSyntax(
                    type: TypeSyntax("GraphEdgeModel")
                )
            }
        ) {}
        
        return [extensionDecl]
    }
    
}