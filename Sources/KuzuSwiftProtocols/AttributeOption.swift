import Foundation

/// Attribute options for customizing property behavior
public enum AttributeOption: Sendable {
    /// Enable full-text search indexing with BM25 ranking
    /// Creates a Full-Text Search index on the property
    case spotlight

    /// Custom storage name for the property in the database
    case originalName(String)
}
