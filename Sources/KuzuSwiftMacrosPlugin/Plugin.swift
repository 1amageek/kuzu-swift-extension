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
        FTSMacro.self,
        TimestampMacro.self
    ]
}