import Foundation
import Kuzu

// MARK: - GraphContext Vector Search API

public extension GraphContext {

    /// Execute a vector search query and return results with distances
    ///
    /// Type-safe API for HNSW vector index queries. Automatically handles:
    /// - Index name resolution from metadata
    /// - Vector dimension validation
    /// - Type casting (CAST AS FLOAT[n])
    /// - Parameter binding
    /// - Result decoding
    ///
    /// Usage:
    /// ```swift
    /// let results = try context.vectorSearch(PhotoAsset.self) {
    ///     VectorSearch(\.labColor, query: queryVector, k: 10)
    ///         .where(\.enabled, .equal, true)
    /// }
    ///
    /// for (photo, distance) in results {
    ///     print("\(photo.id): distance = \(distance)")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - modelType: The GraphNodeModel type to search
    ///   - builder: Query builder closure
    /// - Returns: Array of (model, distance) tuples
    /// - Throws: KuzuError if query execution or result mapping fails
    func vectorSearch<Model: GraphNodeModel & Decodable>(
        _ modelType: Model.Type,
        @QueryBuilder builder: () -> VectorSearch<Model>
    ) throws -> [(model: Model, distance: Double)] {
        try _performVectorSearch(modelType, builder: builder)
    }

    /// Internal implementation of vector search
    private func _performVectorSearch<Model: GraphNodeModel & Decodable>(
        _ modelType: Model.Type,
        @QueryBuilder builder: () -> VectorSearch<Model>
    ) throws -> [(model: Model, distance: Double)] {
        let vectorSearch = builder()

        // Generate Cypher query
        let cypher = try vectorSearch.toCypher()

        // Execute query with parameter binding
        let result: QueryResult
        if cypher.parameters.isEmpty {
            result = try withConnection { connection in
                try connection.query(cypher.query)
            }
        } else {
            result = try withConnection { connection in
                let statement = try connection.prepare(cypher.query)
                let kuzuParams = try encoder.encodeParameters(cypher.parameters)
                return try connection.execute(statement, kuzuParams)
            }
        }

        // Map results
        return try vectorSearch.mapResult(result, decoder: decoder)
    }

    /// Execute a vector search query and return only models (discarding distances)
    ///
    /// Convenience API when you only need the models, not the similarity scores.
    ///
    /// Usage:
    /// ```swift
    /// let photos = try context.vectorSearchModels(PhotoAsset.self) {
    ///     VectorSearch(\.labColor, query: queryVector, k: 10)
    ///         .where(\.enabled, .equal, true)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - modelType: The GraphNodeModel type to search
    ///   - builder: Query builder closure
    /// - Returns: Array of models ordered by distance
    /// - Throws: KuzuError if query execution or result mapping fails
    func vectorSearchModels<Model: GraphNodeModel & Decodable>(
        _ modelType: Model.Type,
        @QueryBuilder builder: () -> VectorSearch<Model>
    ) throws -> [Model] {
        let results = try _performVectorSearch(modelType, builder: builder)
        return results.map { $0.model }
    }

}
