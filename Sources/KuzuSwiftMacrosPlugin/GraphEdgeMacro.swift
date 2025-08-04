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
            throw DiagnosticError(
                message: "@GraphEdge can only be applied to structs",
                diagnosticID: MessageID(domain: "KuzuSwiftMacros", id: "invalid-type"),
                severity: .error
            )
        }
        
        guard case .argumentList(let arguments) = node.arguments,
              arguments.count >= 2,
              let fromArg = arguments.first,
              let toArg = arguments.dropFirst().first else {
            throw DiagnosticError(
                message: "@GraphEdge requires 'from' and 'to' type parameters",
                diagnosticID: MessageID(domain: "KuzuSwiftMacros", id: "missing-parameters"),
                severity: .error
            )
        }
        
        let fromType = fromArg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".self", with: "")
        let toType = toArg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".self", with: "")
        
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
                case "Timestamp":
                    continue
                default:
                    break
                }
            }
            
            columns.append((propertyName, kuzuType, constraints))
            
            var columnDef = "\(propertyName) \(kuzuType)"
            if constraints.contains("PRIMARY KEY") {
                columnDef += " PRIMARY KEY"
            }
            ddlColumns.append(columnDef)
        }
        
        let ddl = "CREATE REL TABLE \(structName) (FROM \(fromType) TO \(toType), \(ddlColumns.joined(separator: ", ")))"
        
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
        let extensionDecl = try ExtensionDeclSyntax(
            extendedType: type,
            inheritanceClause: InheritanceClauseSyntax {
                InheritedTypeSyntax(
                    type: TypeSyntax("_KuzuGraphModel")
                )
            }
        ) {}
        
        return [extensionDecl]
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