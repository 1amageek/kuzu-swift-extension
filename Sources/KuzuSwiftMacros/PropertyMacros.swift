import Foundation

@attached(peer)
public macro ID() = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "IDMacro"
)

@attached(peer)
public macro Vector(dimensions: Int) = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "VectorMacro"
)

@attached(peer)
public macro Default(_ value: Any) = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "DefaultMacro"
)
