import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct GraphNodeMacro: MemberMacro, ExtensionMacro {

    /// Extract CodingKeys from the struct if explicitly defined
    private static func extractCodingKeys(from members: MemberBlockItemListSyntax) -> Set<String>? {
        for member in members {
            guard let enumDecl = member.decl.as(EnumDeclSyntax.self),
                  enumDecl.name.text == "CodingKeys" else {
                continue
            }

            var keys = Set<String>()
            for caseMember in enumDecl.memberBlock.members {
                guard let caseDecl = caseMember.decl.as(EnumCaseDeclSyntax.self) else {
                    continue
                }

                for element in caseDecl.elements {
                    keys.insert(element.name.text)
                }
            }
            return keys
        }
        return nil
    }

    /// Check if a property is a computed property (has accessor block)
    private static func isComputedProperty(_ binding: PatternBindingSyntax) -> Bool {
        return binding.accessorBlock != nil
    }

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

        // Extract explicit CodingKeys if present
        let explicitCodingKeys = extractCodingKeys(from: members)

        var columns: [(name: String, type: String, constraints: [String])] = []
        var ddlColumns: [String] = []
        var idProperties: [(name: String, location: SyntaxProtocol)] = []
        var vectorProperties: [(name: String, dimensions: String, metric: String)] = []

        for member in members {
            guard let variableDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = variableDecl.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeAnnotation = binding.typeAnnotation?.type else {
                continue
            }

            let propertyName = pattern.identifier.text

            // Skip computed properties (mimicking Codable behavior)
            if isComputedProperty(binding) {
                continue
            }

            // If explicit CodingKeys exist, only process properties listed there
            if let codingKeys = explicitCodingKeys {
                guard codingKeys.contains(propertyName) else {
                    continue
                }
            }
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
                        var dimensions: String = ""
                        var metric: String = "l2" // default metric

                        for arg in args {
                            if arg.label?.text == "dimensions",
                               let expr = arg.expression.as(IntegerLiteralExprSyntax.self) {
                                dimensions = expr.literal.text
                            } else if arg.label?.text == "metric" {
                                // Extract metric value (e.g., ".l2" -> "l2")
                                let metricExpr = arg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
                                if metricExpr.contains(".l2") {
                                    metric = "l2"
                                } else if metricExpr.contains(".cosine") {
                                    metric = "cosine"
                                } else if metricExpr.contains(".innerProduct") {
                                    metric = "ip"
                                }
                            }
                        }

                        if !dimensions.isEmpty {
                            // Store vector property metadata for index creation
                            vectorProperties.append((name: propertyName, dimensions: dimensions, metric: metric))

                            // Detect Swift type to determine correct Kuzu vector type
                            let vectorType: String
                            if swiftType.contains("Float") {
                                vectorType = "FLOAT[\(dimensions)]"
                            } else if swiftType.contains("Double") {
                                vectorType = "DOUBLE[\(dimensions)]"
                            } else {
                                // Default to FLOAT for backward compatibility
                                vectorType = "FLOAT[\(dimensions)]"
                            }
                            columns.append((propertyName, vectorType, constraints))
                            // Build DDL column with only supported inline constraints
                            // Escape property name if it's a reserved word
                            let escapedName = KuzuReservedWords.escapeIfNeeded(propertyName)
                            var columnDef = "\(escapedName) \(vectorType)"
                            for constraint in constraints {
                                if constraint.hasPrefix("PRIMARY KEY") || constraint.hasPrefix("DEFAULT") {
                                    columnDef += " \(constraint)"
                                }
                                // UNIQUE and FULLTEXT are ignored as Kuzu doesn't support them inline
                            }
                            ddlColumns.append(columnDef)
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

        // Generate vector properties metadata
        let vectorPropertiesArray = vectorProperties.map { property in
            return "VectorPropertyMetadata(propertyName: \"\(property.name)\", dimensions: \(property.dimensions), metric: .\(property.metric))"
        }.joined(separator: ", ")

        var declarations: [DeclSyntax] = [
            """
            public static let _kuzuDDL: String = "\(raw: ddl)"
            """,
            """
            public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [\(raw: columnsArray)]
            """
        ]

        // Add _vectorProperties only if there are vector properties
        if !vectorProperties.isEmpty {
            declarations.append(
                """
                public static let _vectorProperties: [VectorPropertyMetadata] = [\(raw: vectorPropertiesArray)]
                """
            )
        }

        return declarations
    }
    
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Check if the declaration is a struct
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            // Don't generate extension for non-struct types
            return []
        }

        let members = structDecl.memberBlock.members

        // Collect vector properties
        var vectorProperties: [(name: String, dimensions: String, metric: String)] = []

        for member in members {
            guard let variableDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = variableDecl.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }

            let propertyName = pattern.identifier.text

            for attribute in variableDecl.attributes {
                guard let attr = attribute.as(AttributeSyntax.self) else { continue }
                let attrName = attr.attributeName.description.trimmingCharacters(in: .whitespacesAndNewlines)

                if attrName == "Vector" {
                    if case .argumentList(let args) = attr.arguments {
                        var dimensions: String = ""
                        var metric: String = "l2"

                        for arg in args {
                            if arg.label?.text == "dimensions",
                               let expr = arg.expression.as(IntegerLiteralExprSyntax.self) {
                                dimensions = expr.literal.text
                            }
                        }

                        if !dimensions.isEmpty {
                            vectorProperties.append((name: propertyName, dimensions: dimensions, metric: metric))
                        }
                    }
                }
            }
        }

        // Generate base extension with GraphNodeModel conformance
        let baseExtension = ExtensionDeclSyntax(
            extendedType: type,
            inheritanceClause: InheritanceClauseSyntax {
                InheritedTypeSyntax(
                    type: TypeSyntax("GraphNodeModel")
                )
            }
        ) {}

        // If has vector properties, add HasVectorProperties conformance
        if !vectorProperties.isEmpty {
            let vectorExtension = ExtensionDeclSyntax(
                extendedType: type,
                inheritanceClause: InheritanceClauseSyntax {
                    InheritedTypeSyntax(
                        type: TypeSyntax("HasVectorProperties")
                    )
                }
            ) {}

            return [baseExtension, vectorExtension]
        }

        return [baseExtension]
    }
    
}