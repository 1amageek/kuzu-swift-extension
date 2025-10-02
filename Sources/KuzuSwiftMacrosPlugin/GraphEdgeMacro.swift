import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct GraphEdgeMacro: MemberMacro, ExtensionMacro {

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

        // Extract from/to types from macro arguments
        guard case .argumentList(let arguments) = node.arguments,
              arguments.count == 2 else {
            let diagnostic = Diagnostic(
                node: node,
                message: GraphEdgeDiagnostic.missingFromToArguments
            )
            context.diagnose(diagnostic)
            return []
        }

        // Parse from: and to: arguments
        var fromType: String?
        var toType: String?

        for argument in arguments {
            guard let label = argument.label?.text else { continue }
            let expr = argument.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)

            if label == "from" {
                // Keep the full type path from "User.self" -> "User"
                // This preserves nested types like "MyStruct.User"
                if expr.hasSuffix(".self") {
                    fromType = String(expr.dropLast(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    fromType = expr
                }
            } else if label == "to" {
                if expr.hasSuffix(".self") {
                    toType = String(expr.dropLast(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    toType = expr
                }
            }
        }

        guard let from = fromType, let to = toType else {
            let diagnostic = Diagnostic(
                node: node,
                message: GraphEdgeDiagnostic.missingFromToArguments
            )
            context.diagnose(diagnostic)
            return []
        }

        let structName = structDecl.name.text
        let members = structDecl.memberBlock.members

        // Extract explicit CodingKeys if present (same as GraphNodeMacro)
        let explicitCodingKeys = extractCodingKeys(from: members)

        var columns: [(propertyName: String, columnName: String, type: String, constraints: [String])] = []
        var ddlColumns: [String] = []
        var idProperties: [(propertyName: String, columnName: String, location: SyntaxProtocol)] = []

        for member in members {
            guard let variableDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = variableDecl.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeAnnotation = binding.typeAnnotation?.type else {
                continue
            }

            let propertyName = pattern.identifier.text

            // Skip computed properties
            if binding.accessorBlock != nil {
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

            var constraints: [String] = []

            for attribute in variableDecl.attributes {
                guard let attr = attribute.as(AttributeSyntax.self) else { continue }
                let attrName = attr.attributeName.description.trimmingCharacters(in: .whitespacesAndNewlines)

                switch attrName {
                case "ID":
                    constraints.append("PRIMARY KEY")
                    idProperties.append((propertyName: propertyName, columnName: columnName, location: variableDecl))
                case "Default":
                    if case .argumentList(let args) = attr.arguments,
                       let firstArg = args.first {
                        let defaultValue = firstArg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
                        if defaultValue.hasPrefix("\"") && defaultValue.hasSuffix("\"") {
                            let sqlValue = defaultValue.replacingOccurrences(of: "\"", with: "'")
                            constraints.append("DEFAULT \(sqlValue)")
                        } else {
                            constraints.append("DEFAULT \(defaultValue)")
                        }
                    }
                case "Transient":
                    // Skip transient properties
                    continue
                default:
                    break
                }
            }

            let kuzuType = MacroUtilities.mapSwiftTypeToKuzuType(swiftType)
            columns.append((propertyName: propertyName, columnName: columnName, type: kuzuType, constraints: constraints))

            let escapedName = KuzuReservedWords.escapeIfNeeded(columnName)
            var columnDef = "\(escapedName) \(kuzuType)"
            for constraint in constraints {
                columnDef += " \(constraint)"
            }
            ddlColumns.append(columnDef)
        }

        // Validate ID properties - edges can have zero or one ID property
        if idProperties.count > 1 {
            let notes = idProperties.map { (propName, colName, location) in
                Note(
                    node: Syntax(location),
                    message: MacroExpansionNoteMessage("Property '\(propName)' (column: '\(colName)') is marked with @ID")
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

        // Generate DDL
        let ddl: String
        if ddlColumns.isEmpty {
            ddl = "CREATE REL TABLE \(structName) (FROM \(from) TO \(to))"
        } else {
            ddl = "CREATE REL TABLE \(structName) (FROM \(from) TO \(to), \(ddlColumns.joined(separator: ", ")))"
        }

        let columnsArray = columns.map { column in
            let constraintsArray = column.constraints.map { "\"\($0)\"" }.joined(separator: ", ")
            return "(propertyName: \"\(column.propertyName)\", columnName: \"\(column.columnName)\", type: \"\(column.type)\", constraints: [\(constraintsArray)])"
        }.joined(separator: ", ")

        return [
            """
            public static let _kuzuDDL: String = "\(raw: ddl)"
            """,
            """
            public static let _kuzuColumns: [(propertyName: String, columnName: String, type: String, constraints: [String])] = [\(raw: columnsArray)]
            """,
            """
            public static let _metadata = GraphMetadata()
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
            return []
        }

        // Extract from/to types from macro arguments
        guard case .argumentList(let arguments) = node.arguments,
              arguments.count == 2 else {
            return []
        }

        var fromType: String?
        var toType: String?

        for argument in arguments {
            guard let label = argument.label?.text else { continue }
            let expr = argument.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)

            if label == "from" {
                // Keep the full type path from "User.self" -> "User"
                // This preserves nested types like "MyStruct.User"
                if expr.hasSuffix(".self") {
                    fromType = String(expr.dropLast(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    fromType = expr
                }
            } else if label == "to" {
                if expr.hasSuffix(".self") {
                    toType = String(expr.dropLast(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    toType = expr
                }
            }
        }

        guard let from = fromType, let to = toType else {
            return []
        }

        let extensionDecl = ExtensionDeclSyntax(
            extendedType: type,
            inheritanceClause: InheritanceClauseSyntax {
                InheritedTypeSyntax(type: TypeSyntax("GraphEdgeModel"))
            }
        ) {
            """
            public static let _fromType: Any.Type = \(raw: from).self
            """
            """
            public static let _toType: Any.Type = \(raw: to).self
            """
        }

        return [extensionDecl]
    }
}
