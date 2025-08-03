import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct GraphNodeMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw GraphNodeMacroError.onlyApplicableToStruct
        }
        
        let tableName = structDecl.name.text
        let members = structDecl.memberBlock.members
        
        // Analyze properties to generate DDL and columns
        let analyzer = PropertyAnalyzer()
        let properties = analyzer.analyze(members: members)
        
        // Generate DDL
        let ddlGenerator = DDLGenerator()
        let ddl = ddlGenerator.generateNodeTableDDL(tableName: tableName, properties: properties)
        let columns = ddlGenerator.generateColumnMeta(properties: properties)
        
        // Build the extension
        let extensionDecl = try ExtensionDeclSyntax(
            """
            extension \(type): GraphNodeProtocol, _KuzuGraphModel {
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

enum GraphNodeMacroError: Error, CustomStringConvertible {
    case onlyApplicableToStruct
    
    var description: String {
        switch self {
        case .onlyApplicableToStruct:
            return "@GraphNode can only be applied to structs"
        }
    }
}