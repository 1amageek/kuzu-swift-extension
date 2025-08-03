import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct KuzuSwiftExtensionMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        GraphNodeMacro.self,
        GraphEdgeMacro.self
    ]
}