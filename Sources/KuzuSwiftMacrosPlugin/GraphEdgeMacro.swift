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

        let structName = structDecl.name.text
        let members = structDecl.memberBlock.members

        var columns: [(name: String, type: String, constraints: [String])] = []
        var ddlColumns: [String] = []
        var idProperties: [(name: String, location: SyntaxProtocol)] = []

        // Track @Since and @Target properties for edge metadata
        var sinceProperty: (name: String, nodeType: String, keyPath: String, swiftType: String)?
        var targetProperty: (name: String, nodeType: String, keyPath: String, swiftType: String)?

        for member in members {
            guard let variableDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = variableDecl.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeAnnotation = binding.typeAnnotation?.type else {
                continue
            }

            let propertyName = pattern.identifier.text
            let swiftType = typeAnnotation.description.trimmingCharacters(in: .whitespacesAndNewlines)

            var constraints: [String] = []

            for attribute in variableDecl.attributes {
                guard let attr = attribute.as(AttributeSyntax.self) else { continue }
                let attrName = attr.attributeName.description.trimmingCharacters(in: .whitespacesAndNewlines)

                switch attrName {
                case "Since":
                    if case .argumentList(let args) = attr.arguments,
                       let firstArg = args.first {
                        let keyPathExpr = firstArg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let parsed = parseKeyPath(keyPathExpr) {
                            sinceProperty = (propertyName, parsed.nodeType, parsed.property, swiftType)
                        }
                    }
                case "Target":
                    if case .argumentList(let args) = attr.arguments,
                       let firstArg = args.first {
                        let keyPathExpr = firstArg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let parsed = parseKeyPath(keyPathExpr) {
                            targetProperty = (propertyName, parsed.nodeType, parsed.property, swiftType)
                        }
                    }
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
                        if defaultValue.hasPrefix("\"") && defaultValue.hasSuffix("\"") {
                            let sqlValue = defaultValue.replacingOccurrences(of: "\"", with: "'")
                            constraints.append("DEFAULT \(sqlValue)")
                        } else {
                            constraints.append("DEFAULT \(defaultValue)")
                        }
                    }
                case "Timestamp":
                    break
                default:
                    break
                }
            }

            let kuzuType = MacroUtilities.mapSwiftTypeToKuzuType(swiftType)
            columns.append((propertyName, kuzuType, constraints))

            let escapedName = KuzuReservedWords.escapeIfNeeded(propertyName)
            var columnDef = "\(escapedName) \(kuzuType)"
            for constraint in constraints {
                columnDef += " \(constraint)"
            }
            ddlColumns.append(columnDef)
        }

        // Validate @Since/@Target
        guard let since = sinceProperty else {
            let diagnostic = Diagnostic(
                node: structDecl.name,
                message: GraphEdgeDiagnostic.missingSinceProperty
            )
            context.diagnose(diagnostic)
            return []
        }

        guard let target = targetProperty else {
            let diagnostic = Diagnostic(
                node: structDecl.name,
                message: GraphEdgeDiagnostic.missingTargetProperty
            )
            context.diagnose(diagnostic)
            return []
        }

        // Validate ID properties - edges can have zero or one ID property
        if idProperties.count > 1 {
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

        // Generate DDL using extracted node types
        let ddl: String
        if ddlColumns.isEmpty {
            ddl = "CREATE REL TABLE \(structName) (FROM \(since.nodeType) TO \(target.nodeType))"
        } else {
            ddl = "CREATE REL TABLE \(structName) (FROM \(since.nodeType) TO \(target.nodeType), \(ddlColumns.joined(separator: ", ")))"
        }

        let columnsArray = columns.map { column in
            let constraintsArray = column.constraints.map { "\"\($0)\"" }.joined(separator: ", ")
            return "(name: \"\(column.name)\", type: \"\(column.type)\", constraints: [\(constraintsArray)])"
        }.joined(separator: ", ")

        // Generate EdgeMetadata
        let edgeMetadataDecl = """
            EdgeMetadata(
                sinceProperty: "\(since.name)",
                sinceNodeType: "\(since.nodeType)",
                sinceNodeKeyPath: "\(since.keyPath)",
                targetProperty: "\(target.name)",
                targetNodeType: "\(target.nodeType)",
                targetNodeKeyPath: "\(target.keyPath)"
            )
            """

        return [
            """
            public static let _kuzuDDL: String = "\(raw: ddl)"
            """,
            """
            public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [\(raw: columnsArray)]
            """,
            """
            public static let _metadata = GraphMetadata(edgeMetadata: \(raw: edgeMetadataDecl))
            """
        ]
    }

    /// Parse KeyPath expression like "\User.id" to extract node type and property
    private static func parseKeyPath(_ keyPath: String) -> (nodeType: String, property: String)? {
        // Remove leading backslash if present
        let cleaned = keyPath.hasPrefix("\\") ? String(keyPath.dropFirst()) : keyPath

        // Split by dot
        let components = cleaned.split(separator: ".")
        guard components.count == 2 else {
            return nil
        }

        return (String(components[0]), String(components[1]))
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
                    type: TypeSyntax("GraphEdgeModel")
                )
            }
        ) {}

        return [extensionDecl]
    }
    
}