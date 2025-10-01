import Foundation

/// Metadata for a Full-Text Search property
///
/// This structure contains information about properties that should have
/// Full-Text Search indexes created on them for text search capabilities.
///
/// Full-Text Search (FTS) enables efficient searching of text content using
/// natural language queries with features like stemming and stopword removal.
///
/// Example:
/// ```swift
/// @GraphNode
/// struct Article: Codable {
///     @ID var id: Int
///     @Attribute(.spotlight) var content: String  // Creates Full-Text Search index
/// }
/// ```
public struct FullTextSearchPropertyMetadata: Sendable {
    /// The name of the property in the Swift model
    public let propertyName: String

    /// The stemmer to use for text processing
    /// Common values: "porter", "english", "russian"
    public let stemmer: String

    public init(propertyName: String, stemmer: String = "porter") {
        self.propertyName = propertyName
        self.stemmer = stemmer
    }

    /// Generate the index name for this Full-Text Search property
    /// Format: {tableName}_{propertyName}_fts_idx
    public func indexName(for tableName: String) -> String {
        "\(tableName.lowercased())_\(propertyName.lowercased())_fts_idx"
    }
}
