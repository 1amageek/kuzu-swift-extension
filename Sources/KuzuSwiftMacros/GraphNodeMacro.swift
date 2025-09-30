import Foundation
import KuzuSwiftProtocols

@attached(member, names: named(_kuzuDDL), named(_kuzuColumns), named(_vectorProperties))
@attached(extension, conformances: GraphNodeModel, HasVectorProperties)
public macro GraphNode() = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "GraphNodeMacro"
)