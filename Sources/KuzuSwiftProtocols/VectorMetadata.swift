import Foundation

/// Metadata for a vector property
public struct VectorPropertyMetadata: Sendable {
    /// The name of the property in the Swift model
    public let propertyName: String

    /// The vector dimensions
    public let dimensions: Int

    /// The distance metric for the vector index
    public let metric: VectorMetric

    public init(propertyName: String, dimensions: Int, metric: VectorMetric) {
        self.propertyName = propertyName
        self.dimensions = dimensions
        self.metric = metric
    }

    /// Generate the index name for this vector property
    /// Format: {tableName}_{propertyName}_idx
    public func indexName(for tableName: String) -> String {
        "\(tableName.lowercased())_\(propertyName.lowercased())_idx"
    }
}

/// Distance metric for vector similarity search
public enum VectorMetric: String, Sendable, Codable {
    /// L2 (Euclidean) distance
    case l2 = "l2"

    /// Cosine similarity
    case cosine = "cosine"

    /// Inner product
    case innerProduct = "ip"
}

/// Protocol for models with vector properties
public protocol HasVectorProperties {
    /// Metadata for all vector properties in this model
    static var _vectorProperties: [VectorPropertyMetadata] { get }
}