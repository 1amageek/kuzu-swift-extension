import Foundation
import KuzuSwiftProtocols

/// Configures relationship properties with delete rules and inverse relationships
///
/// Use this macro on edge properties to specify delete behavior and bidirectional relationships.
/// This is compatible with SwiftData's @Relationship macro.
///
/// Example:
/// ```swift
/// @GraphEdge(from: User.self, to: Post.self)
/// struct Authored: Codable {
///     @ID var id: UUID
///     @Relationship(deleteRule: .cascade, inverse: \Post.author)
///     var metadata: EdgeMetadata?
/// }
/// ```
@attached(peer)
public macro Relationship(deleteRule: DeleteRule = .nullify, inverse: String? = nil) = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "RelationshipMacro"
)
