import Foundation

/// Marks a property as the destination node in an edge relationship
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
public macro Target<Root, Value>(_ keyPath: KeyPath<Root, Value>) = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "TargetMacro"
)
