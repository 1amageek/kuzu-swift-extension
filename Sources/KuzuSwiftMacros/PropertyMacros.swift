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
public macro FullTextSearch() = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "FullTextSearchMacro"
)

@attached(peer)
public macro Timestamp() = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "TimestampMacro"
)

@attached(peer)
public macro Unique() = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "UniqueMacro"
)

@attached(peer)
public macro Default(_ value: Any) = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "DefaultMacro"
)

