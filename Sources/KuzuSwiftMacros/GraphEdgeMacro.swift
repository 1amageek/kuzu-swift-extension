import Foundation
import KuzuSwiftProtocols

@attached(member, names: named(_kuzuDDL), named(_kuzuColumns), named(_metadata))
@attached(extension, conformances: GraphEdgeModel, names: named(_fromType), named(_toType))
public macro GraphEdge<From: GraphNodeModel, To: GraphNodeModel>(from: From.Type, to: To.Type) = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "GraphEdgeMacro"
)
