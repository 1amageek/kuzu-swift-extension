import Foundation

/// Metadata for edge relationships
///
/// Contains information about @Since and @Target properties that define
/// the source and destination nodes for an edge.
///
/// Example:
/// ```swift
/// @GraphEdge
/// struct Authored: Codable {
///     @Since(\User.id) var author: User
///     @Target(\Post.id) var post: Post
/// }
///
/// // Generated metadata:
/// // EdgeMetadata(
/// //     sinceProperty: "author",
/// //     sinceNodeType: "User",
/// //     sinceNodeKeyPath: "id",
/// //     targetProperty: "post",
/// //     targetNodeType: "Post",
/// //     targetNodeKeyPath: "id"
/// // )
/// ```
public struct EdgeMetadata: Sendable {
    /// Property name marked with @Since
    public let sinceProperty: String

    /// Node type for the @Since property (e.g., "User")
    public let sinceNodeType: String

    /// KeyPath on the since node used for matching (e.g., "id")
    public let sinceNodeKeyPath: String

    /// Property name marked with @Target
    public let targetProperty: String

    /// Node type for the @Target property (e.g., "Post")
    public let targetNodeType: String

    /// KeyPath on the target node used for matching (e.g., "id")
    public let targetNodeKeyPath: String

    public init(
        sinceProperty: String,
        sinceNodeType: String,
        sinceNodeKeyPath: String,
        targetProperty: String,
        targetNodeType: String,
        targetNodeKeyPath: String
    ) {
        self.sinceProperty = sinceProperty
        self.sinceNodeType = sinceNodeType
        self.sinceNodeKeyPath = sinceNodeKeyPath
        self.targetProperty = targetProperty
        self.targetNodeType = targetNodeType
        self.targetNodeKeyPath = targetNodeKeyPath
    }
}

/// Container for all optional metadata associated with a graph model
///
/// This structure aggregates various types of metadata (vector properties, Full-Text Search properties)
/// into a single, cohesive container. It provides a clean separation between required
/// model metadata (_kuzuDDL, _kuzuColumns) and optional indexing features.
///
/// Note: Kuzu only supports the following index types:
/// - PRIMARY KEY: Automatically created Hash index (via @ID)
/// - Vector Index: HNSW index for similarity search (via @Vector)
/// - Full-Text Search Index: Full-text search index (via @Attribute(.spotlight))
///
/// Kuzu does NOT support:
/// - Regular secondary indexes on arbitrary properties
/// - UNIQUE constraints on non-primary-key columns
///
/// Example:
/// ```swift
/// @GraphNode
/// struct Article: Codable {
///     @ID var id: Int
///     @Vector(dimensions: 512) var embedding: [Float]
///     @Attribute(.spotlight) var content: String
/// }
///
/// // Access metadata
/// Article._metadata.vectorProperties              // [VectorPropertyMetadata(...)]
/// Article._metadata.fullTextSearchProperties      // [FullTextSearchPropertyMetadata(...)]
/// ```
public struct GraphMetadata: Sendable {
    /// Vector property metadata for HNSW indexes
    public let vectorProperties: [VectorPropertyMetadata]

    /// Full-Text Search property metadata for Full-Text Search indexes
    public let fullTextSearchProperties: [FullTextSearchPropertyMetadata]

    /// Edge relationship metadata (@Since/@Target properties)
    public let edgeMetadata: EdgeMetadata?

    /// Empty metadata (no vector, Full-Text Search, or edge properties)
    public static let none = GraphMetadata(
        vectorProperties: [],
        fullTextSearchProperties: [],
        edgeMetadata: nil
    )

    public init(
        vectorProperties: [VectorPropertyMetadata] = [],
        fullTextSearchProperties: [FullTextSearchPropertyMetadata] = [],
        edgeMetadata: EdgeMetadata? = nil
    ) {
        self.vectorProperties = vectorProperties
        self.fullTextSearchProperties = fullTextSearchProperties
        self.edgeMetadata = edgeMetadata
    }
}
