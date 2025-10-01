import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct KuzuSwiftMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        GraphNodeMacro.self,
        GraphEdgeMacro.self,
        IDMacro.self,
        VectorMacro.self,
        DefaultMacro.self,
        TransientMacro.self,
        AttributeMacro.self,
    ]
}