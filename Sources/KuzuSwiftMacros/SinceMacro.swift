import Foundation

/// Marks a property as the source node in an edge relationship
///
/// Example:
/// ```swift
/// @GraphEdge
/// struct Authored: Codable {
///     @Since(\User.id) var author: User
///     @Target(\Post.id) var post: Post
/// }
/// ```
@attached(peer)
public macro Since<Root, Value>(_ keyPath: KeyPath<Root, Value>) = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "SinceMacro"
)
