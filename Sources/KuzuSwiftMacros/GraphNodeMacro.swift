import Foundation
import KuzuSwiftProtocols

@attached(member, names: named(_kuzuDDL), named(_kuzuColumns))
@attached(extension, conformances: GraphNodeModel)
public macro GraphNode() = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "GraphNodeMacro"
)