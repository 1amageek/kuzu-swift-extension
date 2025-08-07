import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct KuzuSwiftMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        GraphNodeMacro.self,
        GraphEdgeMacro.self,
        IDMacro.self,
        IndexMacro.self,
        VectorMacro.self,
        FullTextSearchMacro.self,
        TimestampMacro.self,
        UniqueMacro.self,
        DefaultMacro.self,
    ]
}