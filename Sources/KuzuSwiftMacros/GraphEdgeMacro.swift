import Foundation
import KuzuSwiftProtocols

@attached(member, names: named(_kuzuDDL), named(_kuzuColumns), named(_metadata))
@attached(extension, conformances: GraphEdgeModel)
public macro GraphEdge() = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "GraphEdgeMacro"
)
