import Foundation

@attached(peer)
public macro ID() = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "IDMacro"
)

@attached(peer)
public macro Index() = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "IndexMacro"
)

@attached(peer)
public macro Vector(dimensions: Int) = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "VectorMacro"
)

@attached(peer)
public macro FTS() = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "FTSMacro"
)

@attached(peer)
public macro Timestamp() = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "TimestampMacro"
)