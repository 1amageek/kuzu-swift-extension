import Foundation

/// Delete rule for relationships (SwiftData compatible)
public enum DeleteRule: String, Sendable, Codable {
    /// Delete related objects when this object is deleted
    case cascade

    /// Nullify references to this object when deleted (default)
    case nullify

    /// Deny deletion if related objects exist
    case deny

    /// No automatic action taken
    case noAction
}

/// Protocol for types that have relationship metadata
public protocol HasRelationshipMetadata {
    /// Relationship metadata for this type
    static var _relationshipMetadata: RelationshipMetadata { get }
}

/// Metadata for edge relationships
public struct RelationshipMetadata: Sendable, Equatable {
    /// Delete rule to apply when the source node is deleted
    public let deleteRule: DeleteRule

    /// Optional inverse key path (for bidirectional relationships)
    public let inverse: String?

    public init(deleteRule: DeleteRule = .nullify, inverse: String? = nil) {
        self.deleteRule = deleteRule
        self.inverse = inverse
    }
}
