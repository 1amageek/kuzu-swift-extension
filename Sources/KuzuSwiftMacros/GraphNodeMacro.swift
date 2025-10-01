import Foundation
import KuzuSwiftProtocols

@attached(member, names: named(_kuzuDDL), named(_kuzuColumns), named(_metadata))
@attached(extension, conformances: GraphNodeModel)
public macro GraphNode() = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "GraphNodeMacro"
)