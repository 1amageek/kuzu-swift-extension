import Foundation
import KuzuSwiftProtocols

@attached(member, names: named(_kuzuDDL), named(_kuzuColumns))
@attached(extension, conformances: GraphEdgeModel)
public macro GraphEdge(from: Any.Type, to: Any.Type) = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "GraphEdgeMacro"
)
