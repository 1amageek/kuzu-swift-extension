import Foundation

@attached(extension, names: named(_kuzuDDL), named(_kuzuColumns), named(_kuzuTableName), named(From), named(To))
public macro GraphEdge<From, To>(
    from: From.Type,
    to: To.Type
) = #externalMacro(module: "KuzuSwiftExtensionMacrosPlugin", type: "GraphEdgeMacro")