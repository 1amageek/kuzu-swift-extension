import Foundation

// MARK: - Graph Algorithms Extension

public extension GraphContext {
    var algo: GraphAlgorithms {
        GraphAlgorithms(context: self)
    }
}

public struct GraphAlgorithms {
    private let context: GraphContext
    
    init(context: GraphContext) {
        self.context = context
    }
    
    // MARK: - PageRank
    
    public func pageRank<T: GraphNodeProtocol>(
        _ type: T.Type,
        damping: Double = 0.85,
        iterations: Int = 20
    ) async throws -> [PageRankResult] {
        let cypher = """
            CALL algo.pagerank($1, damping := $2, iter := $3)
            RETURN node, rank
            """
        
        let bindings: [String: any Encodable] = [
            "1": T._kuzuTableName,
            "2": damping,
            "3": iterations
        ]
        
        return try await context.raw(cypher, bindings: bindings)
    }
    
    // MARK: - Shortest Path
    
    public func shortestPath<T: GraphNodeProtocol>(
        from source: T,
        to target: T,
        via edgeType: (any GraphEdgeProtocol.Type)? = nil
    ) async throws -> PathResult? {
        let edgePattern = edgeType.map { ":\($0._kuzuTableName)*" } ?? "*"
        
        let cypher = """
            MATCH p = shortestPath((source:\(T._kuzuTableName))-[\(edgePattern)]-(target:\(T._kuzuTableName)))
            WHERE source.id = $1 AND target.id = $2
            RETURN p
            """
        
        // Extract ID values - this is simplified
        let sourceID = extractID(from: source)
        let targetID = extractID(from: target)
        
        let bindings: [String: any Encodable] = [
            "1": sourceID,
            "2": targetID
        ]
        
        return try await context.raw(cypher, bindings: bindings)
    }
    
    // MARK: - All Shortest Paths
    
    public func allShortestPaths<T: GraphNodeProtocol>(
        from source: T,
        to target: T,
        via edgeType: (any GraphEdgeProtocol.Type)? = nil
    ) async throws -> [PathResult] {
        let edgePattern = edgeType.map { ":\($0._kuzuTableName)*" } ?? "*"
        
        let cypher = """
            MATCH p = allShortestPaths((source:\(T._kuzuTableName))-[\(edgePattern)]-(target:\(T._kuzuTableName)))
            WHERE source.id = $1 AND target.id = $2
            RETURN p
            """
        
        let sourceID = extractID(from: source)
        let targetID = extractID(from: target)
        
        let bindings: [String: any Encodable] = [
            "1": sourceID,
            "2": targetID
        ]
        
        return try await context.raw(cypher, bindings: bindings)
    }
    
    // MARK: - Strongly Connected Components
    
    public func stronglyConnectedComponents() async throws -> [SCCResult] {
        let cypher = "CALL algo.scc() RETURN group_id, node_id"
        return try await context.raw(cypher)
    }
    
    // MARK: - Weakly Connected Components
    
    public func weaklyConnectedComponents() async throws -> [WCCResult] {
        let cypher = "CALL algo.wcc() RETURN group_id, node_id"
        return try await context.raw(cypher)
    }
    
    // MARK: - Community Detection (Louvain)
    
    public func louvain() async throws -> [CommunityResult] {
        let cypher = "CALL algo.louvain() RETURN node_id, community_id"
        return try await context.raw(cypher)
    }
    
    // MARK: - Betweenness Centrality
    
    public func betweennessCentrality<T: GraphNodeProtocol>(
        _ type: T.Type,
        normalized: Bool = true
    ) async throws -> [CentralityResult] {
        let cypher = """
            CALL algo.betweenness_centrality($1, normalized := $2)
            RETURN node, centrality
            """
        
        let bindings: [String: any Encodable] = [
            "1": T._kuzuTableName,
            "2": normalized
        ]
        
        return try await context.raw(cypher, bindings: bindings)
    }
    
    // MARK: - Private Helpers
    
    private func extractID<T: _KuzuGraphModel>(from model: T) -> any Encodable {
        // Use Mirror to extract ID property
        let mirror = Mirror(reflecting: model)
        
        for child in mirror.children {
            if let label = child.label,
               (label == "id" || label.hasSuffix("ID")),
               let id = child.value as? any Encodable {
                return id
            }
        }
        
        // Return empty string as fallback
        return ""
    }
}

// MARK: - Result Types

public struct PageRankResult: Decodable {
    public let node: String
    public let rank: Double
}

public struct PathResult: Decodable {
    public let nodes: [String]
    public let edges: [String]
    public let length: Int
}

public struct SCCResult: Decodable {
    public let groupId: Int
    public let nodeId: String
    
    private enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case nodeId = "node_id"
    }
}

public struct WCCResult: Decodable {
    public let groupId: Int
    public let nodeId: String
    
    private enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case nodeId = "node_id"
    }
}

public struct CommunityResult: Decodable {
    public let nodeId: String
    public let communityId: Int
    
    private enum CodingKeys: String, CodingKey {
        case nodeId = "node_id"
        case communityId = "community_id"
    }
}

public struct CentralityResult: Decodable {
    public let node: String
    public let centrality: Double
}