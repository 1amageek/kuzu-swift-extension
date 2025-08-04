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
            throw DiagnosticError(
                message: "@GraphNode can only be applied to structs",
                diagnosticID: MessageID(domain: "KuzuSwiftMacros", id: "invalid-type"),
                severity: .error
            )
        }
        
        let structName = structDecl.name.text
        let members = structDecl.memberBlock.members
        
        var columns: [(name: String, type: String, constraints: [String])] = []
        var ddlColumns: [String] = []
        
        for member in members {
            guard let variableDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = variableDecl.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeAnnotation = binding.typeAnnotation?.type else {
                continue
            }
            
            let propertyName = pattern.identifier.text
            let swiftType = typeAnnotation.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let kuzuType = mapSwiftTypeToKuzuType(swiftType)
            
            var constraints: [String] = []
            
            for attribute in variableDecl.attributes {
                guard let attr = attribute.as(AttributeSyntax.self) else { continue }
                let attrName = attr.attributeName.description.trimmingCharacters(in: .whitespacesAndNewlines)
                
                switch attrName {
                case "ID":
                    constraints.append("PRIMARY KEY")
                case "Index":
                    constraints.append("INDEX")
                case "Vector":
                    if case .argumentList(let args) = attr.arguments {
                        for arg in args {
                            if let expr = arg.expression.as(IntegerLiteralExprSyntax.self) {
                                let dimensions = expr.literal.text
                                columns.append((propertyName, "DOUBLE[\(dimensions)]", constraints))
                                ddlColumns.append("\(propertyName) DOUBLE[\(dimensions)]")
                                continue
                            }
                        }
                    }
                    continue
                case "FTS":
                    constraints.append("FTS")
                case "Timestamp":
                    continue
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
                
                var columnDef = "\(propertyName) \(kuzuType)"
                if constraints.contains("PRIMARY KEY") {
                    columnDef += " PRIMARY KEY"
                }
                ddlColumns.append(columnDef)
            }
        }
        
        let ddl = "CREATE NODE TABLE \(structName) (\(ddlColumns.joined(separator: ", ")))"
        
        let columnsArray = columns.map { column in
            let constraintsArray = column.constraints.map { "\"\($0)\"" }.joined(separator: ", ")
            return "(name: \"\(column.name)\", type: \"\(column.type)\", constraints: [\(constraintsArray)])"
        }.joined(separator: ", ")
        
        return [
            """
            static let _kuzuDDL: String = "\(raw: ddl)"
            """,
            """
            static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [\(raw: columnsArray)]
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
        let decl: DeclSyntax = """
            extension \(type.trimmed): _KuzuGraphModel {}
            """
        return [decl.cast(ExtensionDeclSyntax.self)]
    }
    
    private static func mapSwiftTypeToKuzuType(_ swiftType: String) -> String {
        let typeMapping: [String: String] = [
            "String": "STRING",
            "String?": "STRING",
            "Int": "INT64",
            "Int?": "INT64",
            "Int32": "INT32",
            "Int32?": "INT32",
            "Int64": "INT64",
            "Int64?": "INT64",
            "Double": "DOUBLE",
            "Double?": "DOUBLE",
            "Float": "FLOAT",
            "Float?": "FLOAT",
            "Bool": "BOOLEAN",
            "Bool?": "BOOLEAN",
            "Date": "TIMESTAMP",
            "Date?": "TIMESTAMP",
            "UUID": "STRING",
            "UUID?": "STRING"
        ]
        
        return typeMapping[swiftType] ?? "STRING"
    }
}

struct DiagnosticError: Error {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity
}