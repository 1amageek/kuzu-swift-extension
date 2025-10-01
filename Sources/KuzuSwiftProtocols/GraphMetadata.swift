import Foundation

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

    /// Empty metadata (no vector or Full-Text Search properties)
    public static let none = GraphMetadata(
        vectorProperties: [],
        fullTextSearchProperties: []
    )

    public init(
        vectorProperties: [VectorPropertyMetadata] = [],
        fullTextSearchProperties: [FullTextSearchPropertyMetadata] = []
    ) {
        self.vectorProperties = vectorProperties
        self.fullTextSearchProperties = fullTextSearchProperties
    }
}
