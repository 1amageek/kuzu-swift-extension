import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct GraphEdgeMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw GraphEdgeMacroError.onlyApplicableToStruct
        }
        
        // Extract from and to types from the attribute
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              arguments.count == 2,
              let fromExpr = arguments.first(where: { $0.label?.text == "from" }),
              let toExpr = arguments.first(where: { $0.label?.text == "to" }),
              let fromType = fromExpr.expression.as(MemberAccessExprSyntax.self)?.base,
              let toType = toExpr.expression.as(MemberAccessExprSyntax.self)?.base else {
            throw GraphEdgeMacroError.invalidArguments
        }
        
        let tableName = structDecl.name.text
        let members = structDecl.memberBlock.members
        
        // Analyze properties
        let analyzer = PropertyAnalyzer()
        let properties = analyzer.analyze(members: members)
        
        // Generate DDL
        let ddlGenerator = DDLGenerator()
        let ddl = ddlGenerator.generateEdgeTableDDL(
            tableName: tableName,
            fromType: fromType.description,
            toType: toType.description,
            properties: properties
        )
        let columns = ddlGenerator.generateColumnMeta(properties: properties)
        
        // Build the extension
        let extensionDecl = try ExtensionDeclSyntax(
            """
            extension \(type): GraphEdgeProtocol, _KuzuGraphModel {
                public typealias From = \(fromType)
                public typealias To = \(toType)
                
                @_spi(Graph)
                public static let _kuzuDDL: [String] = \(literal: ddl)
                
                @_spi(Graph)
                public static let _kuzuColumns: [ColumnMeta] = \(raw: columns)
                
                public static let _kuzuTableName: String = \(literal: tableName)
            }
            """
        )
        
        return [extensionDecl]
    }
}

enum GraphEdgeMacroError: Error, CustomStringConvertible {
    case onlyApplicableToStruct
    case invalidArguments
    
    var description: String {
        switch self {
        case .onlyApplicableToStruct:
            return "@GraphEdge can only be applied to structs"
        case .invalidArguments:
            return "@GraphEdge requires from: and to: type arguments"
        }
    }
}