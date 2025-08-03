import Foundation

// MARK: - Vector Search Extension

public extension GraphContext {
    var vector: VectorSearch {
        VectorSearch(context: self)
    }
}

public struct VectorSearch {
    private let context: GraphContext
    
    init(context: GraphContext) {
        self.context = context
    }
    
    // MARK: - Similarity Search
    
    public func similaritySearch<T: _KuzuGraphModel>(
        in type: T.Type,
        vector: [Float],
        property: String,
        topK: Int = 10,
        metric: VectorMetric = .l2
    ) async throws -> [VectorSearchResult<T>] {
        let vectorString = vector.map { String($0) }.joined(separator: ",")
        
        let cypher: String
        switch metric {
        case .l2:
            cypher = """
                MATCH (n:\(T._kuzuTableName))
                WITH n, array_distance(n.\(property), [\(vectorString)]) AS distance
                ORDER BY distance ASC
                LIMIT $1
                RETURN n, distance
                """
        case .cosine:
            cypher = """
                MATCH (n:\(T._kuzuTableName))
                WITH n, array_cosine_similarity(n.\(property), [\(vectorString)]) AS similarity
                ORDER BY similarity DESC
                LIMIT $1
                RETURN n, similarity AS distance
                """
        case .innerProduct:
            cypher = """
                MATCH (n:\(T._kuzuTableName))
                WITH n, array_inner_product(n.\(property), [\(vectorString)]) AS score
                ORDER BY score DESC
                LIMIT $1
                RETURN n, -score AS distance
                """
        }
        
        let bindings: [String: any Encodable] = ["1": topK]
        
        // This would need proper implementation to decode results
        return try await context.raw(cypher, bindings: bindings)
    }
    
    // MARK: - Range Search
    
    public func rangeSearch<T: _KuzuGraphModel>(
        in type: T.Type,
        vector: [Float],
        property: String,
        radius: Float,
        metric: VectorMetric = .l2
    ) async throws -> [VectorSearchResult<T>] {
        let vectorString = vector.map { String($0) }.joined(separator: ",")
        
        let cypher: String
        switch metric {
        case .l2:
            cypher = """
                MATCH (n:\(T._kuzuTableName))
                WITH n, array_distance(n.\(property), [\(vectorString)]) AS distance
                WHERE distance <= $1
                ORDER BY distance ASC
                RETURN n, distance
                """
        case .cosine:
            cypher = """
                MATCH (n:\(T._kuzuTableName))
                WITH n, array_cosine_similarity(n.\(property), [\(vectorString)]) AS similarity
                WHERE similarity >= $1
                ORDER BY similarity DESC
                RETURN n, similarity AS distance
                """
        case .innerProduct:
            cypher = """
                MATCH (n:\(T._kuzuTableName))
                WITH n, array_inner_product(n.\(property), [\(vectorString)]) AS score
                WHERE score >= $1
                ORDER BY score DESC
                RETURN n, -score AS distance
                """
        }
        
        let bindings: [String: any Encodable] = ["1": radius]
        
        return try await context.raw(cypher, bindings: bindings)
    }
    
    // MARK: - Hybrid Search (Vector + Filter)
    
    public func hybridSearch<T: _KuzuGraphModel>(
        in type: T.Type,
        vector: [Float],
        property: String,
        filter: @escaping (T) -> Bool,
        topK: Int = 10,
        metric: VectorMetric = .l2
    ) async throws -> [VectorSearchResult<T>] {
        // This is a simplified implementation
        // In production, we'd compile the filter to a WHERE clause
        let results = try await similaritySearch(
            in: type,
            vector: vector,
            property: property,
            topK: topK * 2, // Fetch more to account for filtering
            metric: metric
        )
        
        // Apply client-side filter (not ideal, but works for now)
        return results.filter { result in
            filter(result.node)
        }.prefix(topK).map { $0 }
    }
}

// MARK: - Vector Metrics

public enum VectorMetric {
    case l2              // Euclidean distance
    case cosine          // Cosine similarity
    case innerProduct    // Inner product (dot product)
}

// MARK: - Result Types

public struct VectorSearchResult<T: _KuzuGraphModel>: Decodable {
    public let node: T
    public let distance: Float
    
    public init(node: T, distance: Float) {
        self.node = node
        self.distance = distance
    }
    
    // Simplified decoding - in production, this would decode from Kuzu's result format
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.node = try container.decode(T.self, forKey: .node)
        self.distance = try container.decode(Float.self, forKey: .distance)
    }
    
    private enum CodingKeys: String, CodingKey {
        case node
        case distance
    }
}

// MARK: - Vector Index Management

public extension VectorSearch {
    func createIndex<T: _KuzuGraphModel>(
        on type: T.Type,
        property: String,
        dimensions: Int,
        metric: VectorMetric = .l2
    ) async throws {
        let indexName = "\(T._kuzuTableName)_\(property)_vector_idx"
        
        let metricString: String
        switch metric {
        case .l2:
            metricString = "L2"
        case .cosine:
            metricString = "COSINE"
        case .innerProduct:
            metricString = "IP"
        }
        
        let cypher = """
            CREATE VECTOR INDEX \(indexName)
            ON \(T._kuzuTableName) (\(property))
            USING HNSW (metric := '\(metricString)', dim := \(dimensions))
            """
        
        _ = try await context.rawQuery(cypher)
    }
    
    func dropIndex<T: _KuzuGraphModel>(
        on type: T.Type,
        property: String
    ) async throws {
        let indexName = "\(T._kuzuTableName)_\(property)_vector_idx"
        let cypher = "DROP INDEX \(indexName)"
        _ = try await context.rawQuery(cypher)
    }
}