import Foundation

@attached(extension, names: named(_kuzuDDL), named(_kuzuColumns), named(_kuzuTableName))
public macro GraphNode() = #externalMacro(module: "KuzuSwiftExtensionMacrosPlugin", type: "GraphNodeMacro")