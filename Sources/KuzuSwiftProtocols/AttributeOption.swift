import Foundation

/// Attribute options for customizing property behavior
public enum AttributeOption: Sendable {
    /// Mark as unique (single-property uniqueness)
    case unique

    /// Enable full-text search (replaces @FullTextSearch)
    case spotlight

    /// Timestamp tracking (replaces @Timestamp)
    case timestamp

    /// Custom storage name (originalName parameter)
    case originalName(String)
}
