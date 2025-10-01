import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct GraphNodeMacro: MemberMacro, ExtensionMacro {

    /// Extract CodingKeys from the struct if explicitly defined
    /// Returns a dictionary mapping Swift property names to database column names
    private static func extractCodingKeys(from members: MemberBlockItemListSyntax) -> [String: String]? {
        for member in members {
            guard let enumDecl = member.decl.as(EnumDeclSyntax.self),
                  enumDecl.name.text == "CodingKeys" else {
                continue
            }

            var mappings: [String: String] = [:]
            for caseMember in enumDecl.memberBlock.members {
                guard let caseDecl = caseMember.decl.as(EnumCaseDeclSyntax.self) else {
                    continue
                }

                for element in caseDecl.elements {
                    let propertyName = element.name.text

                    // Check if there's a raw value (e.g., case userName = "user_name")
                    if let rawValue = element.rawValue?.value.as(StringLiteralExprSyntax.self) {
                        // Extract the string value from segments
                        let columnName = rawValue.segments.description.trimmingCharacters(in: .init(charactersIn: "\""))
                        mappings[propertyName] = columnName
                    } else {
                        // No raw value, use property name as column name
                        mappings[propertyName] = propertyName
                    }
                }
            }
            return mappings
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
        var fullTextSearchProperties: [(name: String, stemmer: String)] = []

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

            // Skip @Transient properties
            let hasTransient = variableDecl.attributes.contains(where: {
                if let attr = $0.as(AttributeSyntax.self) {
                    return attr.attributeName.description.trimmingCharacters(in: .whitespacesAndNewlines) == "Transient"
                }
                return false
            })
            if hasTransient {
                continue
            }

            // If explicit CodingKeys exist, only process properties listed there
            if let codingKeys = explicitCodingKeys {
                guard codingKeys.keys.contains(propertyName) else {
                    continue
                }
            }

            // Determine the column name (use CodingKeys mapping if available)
            let columnName: String
            if let codingKeys = explicitCodingKeys, let mappedName = codingKeys[propertyName] {
                columnName = mappedName
            } else {
                columnName = propertyName
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
                case "Attribute":
                    // Handle @Attribute options
                    if case .argumentList(let args) = attr.arguments {
                        for arg in args {
                            let argExpr = arg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
                            if argExpr.contains(".spotlight") {
                                constraints.append("FULLTEXT")
                                // Track Full-Text Search property for index creation
                                fullTextSearchProperties.append((name: columnName, stemmer: "porter"))
                            }
                        }
                    }
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
                            vectorProperties.append((name: columnName, dimensions: dimensions, metric: metric))

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
                            columns.append((columnName, vectorType, constraints))
                            // Build DDL column with only supported inline constraints
                            // Escape column name if it's a reserved word
                            let escapedName = KuzuReservedWords.escapeIfNeeded(columnName)
                            var columnDef = "\(escapedName) \(vectorType)"
                            for constraint in constraints {
                                if constraint.hasPrefix("PRIMARY KEY") || constraint.hasPrefix("DEFAULT") {
                                    columnDef += " \(constraint)"
                                }
                                // FULLTEXT is metadata only - index created separately by GraphContainer
                            }
                            ddlColumns.append(columnDef)
                        }
                    }
                    continue
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
                columns.append((columnName, kuzuType, constraints))

                // Build DDL column with only supported inline constraints
                // Escape column name if it's a reserved word
                let escapedName = KuzuReservedWords.escapeIfNeeded(columnName)
                var columnDef = "\(escapedName) \(kuzuType)"
                for constraint in constraints {
                    if constraint.hasPrefix("PRIMARY KEY") || constraint.hasPrefix("DEFAULT") {
                        columnDef += " \(constraint)"
                    }
                    // FULLTEXT is metadata only - index created separately by GraphContainer
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

        // Generate Full-Text Search properties metadata
        let fullTextSearchPropertiesArray = fullTextSearchProperties.map { property in
            return "FullTextSearchPropertyMetadata(propertyName: \"\(property.name)\", stemmer: \"\(property.stemmer)\")"
        }.joined(separator: ", ")

        var declarations: [DeclSyntax] = [
            """
            public static let _kuzuDDL: String = "\(raw: ddl)"
            """,
            """
            public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [\(raw: columnsArray)]
            """
        ]

        // Generate _metadata property
        declarations.append(
            """
            public static let _metadata = GraphMetadata(
                vectorProperties: [\(raw: vectorPropertiesArray)],
                fullTextSearchProperties: [\(raw: fullTextSearchPropertiesArray)]
            )
            """
        )

        return declarations
    }
    
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Generate extension with GraphNodeModel conformance only
        // All metadata is now in _metadata property
        let baseExtension = ExtensionDeclSyntax(
            extendedType: type,
            inheritanceClause: InheritanceClauseSyntax {
                InheritedTypeSyntax(
                    type: TypeSyntax("GraphNodeModel")
                )
            }
        ) {}

        return [baseExtension]
    }

}