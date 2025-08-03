import Foundation

/// Represents available Kuzu database extensions
public enum KuzuExtension: String, CaseIterable, Hashable, Sendable {
    case httpfs
    case json
    case parquet
    case postgres_scanner
    case rdf
    case s3
    case vector
    case fts
    
    /// The SQL command to install this extension
    public var installCommand: String {
        "INSTALL \(rawValue)"
    }
    
    /// The SQL command to load this extension
    public var loadCommand: String {
        "LOAD EXTENSION \(rawValue)"
    }
}