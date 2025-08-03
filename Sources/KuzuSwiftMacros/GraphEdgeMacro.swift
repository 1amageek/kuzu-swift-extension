import Foundation

@attached(member, names: named(_kuzuDDL), named(_kuzuColumns))
@attached(extension)
public macro GraphEdge(from: Any.Type, to: Any.Type) = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "GraphEdgeMacro"
)