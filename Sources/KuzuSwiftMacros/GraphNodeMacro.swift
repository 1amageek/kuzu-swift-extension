import Foundation

@attached(member, names: named(_kuzuDDL), named(_kuzuColumns))
@attached(extension)
public macro GraphNode() = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "GraphNodeMacro"
)