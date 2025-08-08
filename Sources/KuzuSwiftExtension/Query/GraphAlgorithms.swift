import Foundation

/// Graph algorithm wrappers for Kuzu
public struct GraphAlgorithms {
    
    // MARK: - PageRank Algorithm
    
    /// PageRank algorithm for computing node importance
    public struct PageRank {
        /// Calls the PageRank algorithm
        public static func compute(
            graph: String? = nil,
            damping: Double = 0.85,
            iterations: Int = 20,
            tolerance: Double = 1e-6,
            yields: [String] = ["nodeId", "score"]
        ) -> Call {
            var params: [String: any Sendable] = [
                "damping": damping,
                "iterations": iterations,
                "tolerance": tolerance
            ]
            
            if let graph = graph {
                params["graph"] = graph
            }
            
            return Call.procedure(
                "gds.pageRank",
                parameters: params,
                yields: yields
            )
        }
        
        /// Simplified PageRank with default parameters
        public static func simple(yields: [String] = ["nodeId", "score"]) -> Call {
            compute(yields: yields)
        }
    }
    
    // MARK: - Community Detection Algorithms
    
    /// Louvain community detection algorithm
    public struct Louvain {
        /// Calls the Louvain algorithm
        public static func detect(
            graph: String? = nil,
            seedProperty: String? = nil,
            tolerance: Double = 0.0001,
            maxIterations: Int = 10,
            yields: [String] = ["nodeId", "communityId"]
        ) -> Call {
            var params: [String: any Sendable] = [
                "tolerance": tolerance,
                "maxIterations": maxIterations
            ]
            
            if let graph = graph {
                params["graph"] = graph
            }
            
            if let seed = seedProperty {
                params["seedProperty"] = seed
            }
            
            return Call.procedure(
                "gds.louvain",
                parameters: params,
                yields: yields
            )
        }
        
        /// Simplified Louvain with default parameters
        public static func simple(yields: [String] = ["nodeId", "communityId"]) -> Call {
            detect(yields: yields)
        }
    }
    
    /// Label Propagation Algorithm for community detection
    public struct LabelPropagation {
        /// Calls the Label Propagation algorithm
        public static func detect(
            graph: String? = nil,
            maxIterations: Int = 10,
            seedProperty: String? = nil,
            yields: [String] = ["nodeId", "communityId"]
        ) -> Call {
            var params: [String: any Sendable] = [
                "maxIterations": maxIterations
            ]
            
            if let graph = graph {
                params["graph"] = graph
            }
            
            if let seed = seedProperty {
                params["seedProperty"] = seed
            }
            
            return Call.procedure(
                "gds.labelPropagation",
                parameters: params,
                yields: yields
            )
        }
    }
    
    // MARK: - Connected Components
    
    /// Weakly Connected Components algorithm
    public struct ConnectedComponents {
        /// Finds weakly connected components
        public static func weakly(
            graph: String? = nil,
            seedProperty: String? = nil,
            yields: [String] = ["nodeId", "componentId"]
        ) -> Call {
            var params: [String: any Sendable] = [:]
            
            if let graph = graph {
                params["graph"] = graph
            }
            
            if let seed = seedProperty {
                params["seedProperty"] = seed
            }
            
            return Call.procedure(
                "gds.wcc",
                parameters: params,
                yields: yields
            )
        }
        
        /// Finds strongly connected components
        public static func strongly(
            graph: String? = nil,
            yields: [String] = ["nodeId", "componentId"]
        ) -> Call {
            var params: [String: any Sendable] = [:]
            
            if let graph = graph {
                params["graph"] = graph
            }
            
            return Call.procedure(
                "gds.scc",
                parameters: params,
                yields: yields
            )
        }
    }
    
    // MARK: - Shortest Path Algorithms
    
    /// Shortest path algorithms
    public struct ShortestPath {
        /// Dijkstra's shortest path algorithm
        public static func dijkstra(
            source: String,
            target: String,
            weightProperty: String? = nil,
            yields: [String] = ["path", "cost"]
        ) -> Call {
            var params: [String: any Sendable] = [
                "source": source,
                "target": target
            ]
            
            if let weight = weightProperty {
                params["weightProperty"] = weight
            }
            
            return Call.procedure(
                "gds.shortestPath.dijkstra",
                parameters: params,
                yields: yields
            )
        }
        
        /// A* shortest path algorithm
        public static func aStar(
            source: String,
            target: String,
            weightProperty: String? = nil,
            latitudeProperty: String = "latitude",
            longitudeProperty: String = "longitude",
            yields: [String] = ["path", "cost"]
        ) -> Call {
            var params: [String: any Sendable] = [
                "source": source,
                "target": target,
                "latitudeProperty": latitudeProperty,
                "longitudeProperty": longitudeProperty
            ]
            
            if let weight = weightProperty {
                params["weightProperty"] = weight
            }
            
            return Call.procedure(
                "gds.shortestPath.astar",
                parameters: params,
                yields: yields
            )
        }
        
        /// All shortest paths between nodes
        public static func all(
            source: String? = nil,
            weightProperty: String? = nil,
            yields: [String] = ["source", "target", "distance"]
        ) -> Call {
            var params: [String: any Sendable] = [:]
            
            if let source = source {
                params["source"] = source
            }
            
            if let weight = weightProperty {
                params["weightProperty"] = weight
            }
            
            return Call.procedure(
                "gds.allShortestPaths",
                parameters: params,
                yields: yields
            )
        }
    }
    
    // MARK: - Centrality Algorithms
    
    /// Centrality algorithms for node importance
    public struct Centrality {
        /// Betweenness centrality
        public static func betweenness(
            graph: String? = nil,
            samplingSize: Int? = nil,
            samplingSeed: Int? = nil,
            yields: [String] = ["nodeId", "score"]
        ) -> Call {
            var params: [String: any Sendable] = [:]
            
            if let graph = graph {
                params["graph"] = graph
            }
            
            if let size = samplingSize {
                params["samplingSize"] = size
            }
            
            if let seed = samplingSeed {
                params["samplingSeed"] = seed
            }
            
            return Call.procedure(
                "gds.betweenness",
                parameters: params,
                yields: yields
            )
        }
        
        /// Closeness centrality
        public static func closeness(
            graph: String? = nil,
            useWassermanFaust: Bool = false,
            yields: [String] = ["nodeId", "score"]
        ) -> Call {
            var params: [String: any Sendable] = [
                "useWassermanFaust": useWassermanFaust
            ]
            
            if let graph = graph {
                params["graph"] = graph
            }
            
            return Call.procedure(
                "gds.closeness",
                parameters: params,
                yields: yields
            )
        }
        
        /// Degree centrality
        public static func degree(
            graph: String? = nil,
            orientation: String = "NATURAL",
            yields: [String] = ["nodeId", "score"]
        ) -> Call {
            var params: [String: any Sendable] = [
                "orientation": orientation
            ]
            
            if let graph = graph {
                params["graph"] = graph
            }
            
            return Call.procedure(
                "gds.degree",
                parameters: params,
                yields: yields
            )
        }
        
        /// Eigenvector centrality
        public static func eigenvector(
            graph: String? = nil,
            maxIterations: Int = 20,
            tolerance: Double = 1e-6,
            yields: [String] = ["nodeId", "score"]
        ) -> Call {
            var params: [String: any Sendable] = [
                "maxIterations": maxIterations,
                "tolerance": tolerance
            ]
            
            if let graph = graph {
                params["graph"] = graph
            }
            
            return Call.procedure(
                "gds.eigenvector",
                parameters: params,
                yields: yields
            )
        }
    }
    
    // MARK: - Similarity Algorithms
    
    /// Similarity algorithms for comparing nodes
    public struct Similarity {
        /// Jaccard similarity
        public static func jaccard(
            graph: String? = nil,
            topK: Int = 10,
            threshold: Double = 0.0,
            yields: [String] = ["node1", "node2", "similarity"]
        ) -> Call {
            var params: [String: any Sendable] = [
                "topK": topK,
                "threshold": threshold
            ]
            
            if let graph = graph {
                params["graph"] = graph
            }
            
            return Call.procedure(
                "gds.nodeSimilarity.jaccard",
                parameters: params,
                yields: yields
            )
        }
        
        /// Cosine similarity
        public static func cosine(
            graph: String? = nil,
            vectorProperty: String,
            topK: Int = 10,
            threshold: Double = 0.0,
            yields: [String] = ["node1", "node2", "similarity"]
        ) -> Call {
            var params: [String: any Sendable] = [
                "vectorProperty": vectorProperty,
                "topK": topK,
                "threshold": threshold
            ]
            
            if let graph = graph {
                params["graph"] = graph
            }
            
            return Call.procedure(
                "gds.nodeSimilarity.cosine",
                parameters: params,
                yields: yields
            )
        }
        
        /// Euclidean distance
        public static func euclidean(
            graph: String? = nil,
            vectorProperty: String,
            topK: Int = 10,
            threshold: Double? = nil,
            yields: [String] = ["node1", "node2", "distance"]
        ) -> Call {
            var params: [String: any Sendable] = [
                "vectorProperty": vectorProperty,
                "topK": topK
            ]
            
            if let graph = graph {
                params["graph"] = graph
            }
            
            if let threshold = threshold {
                params["threshold"] = threshold
            }
            
            return Call.procedure(
                "gds.nodeSimilarity.euclidean",
                parameters: params,
                yields: yields
            )
        }
    }
    
    // MARK: - Path Finding Algorithms
    
    /// Advanced path finding algorithms
    public struct PathFinding {
        /// Breadth-first search
        public static func bfs(
            source: String,
            target: String? = nil,
            maxDepth: Int? = nil,
            yields: [String] = ["path"]
        ) -> Call {
            var params: [String: any Sendable] = [
                "source": source
            ]
            
            if let target = target {
                params["target"] = target
            }
            
            if let depth = maxDepth {
                params["maxDepth"] = depth
            }
            
            return Call.procedure(
                "gds.bfs",
                parameters: params,
                yields: yields
            )
        }
        
        /// Depth-first search
        public static func dfs(
            source: String,
            target: String? = nil,
            maxDepth: Int? = nil,
            yields: [String] = ["path"]
        ) -> Call {
            var params: [String: any Sendable] = [
                "source": source
            ]
            
            if let target = target {
                params["target"] = target
            }
            
            if let depth = maxDepth {
                params["maxDepth"] = depth
            }
            
            return Call.procedure(
                "gds.dfs",
                parameters: params,
                yields: yields
            )
        }
        
        /// K-shortest paths
        public static func kShortestPaths(
            source: String,
            target: String,
            k: Int = 3,
            weightProperty: String? = nil,
            yields: [String] = ["index", "path", "cost"]
        ) -> Call {
            var params: [String: any Sendable] = [
                "source": source,
                "target": target,
                "k": k
            ]
            
            if let weight = weightProperty {
                params["weightProperty"] = weight
            }
            
            return Call.procedure(
                "gds.kShortestPaths",
                parameters: params,
                yields: yields
            )
        }
    }
    
    // MARK: - Graph Generation
    
    /// Graph generation algorithms
    public struct Generate {
        /// Random graph generation
        public static func random(
            nodeCount: Int,
            relationshipCount: Int,
            seed: Int? = nil,
            yields: [String] = ["nodes", "relationships"]
        ) -> Call {
            var params: [String: any Sendable] = [
                "nodeCount": nodeCount,
                "relationshipCount": relationshipCount
            ]
            
            if let seed = seed {
                params["seed"] = seed
            }
            
            return Call.procedure(
                "gds.graph.generate.random",
                parameters: params,
                yields: yields
            )
        }
    }
}

// MARK: - Query Integration

public extension Query {
    /// Adds a graph algorithm call to the query
    func withAlgorithm(_ call: Call) -> Query {
        var newComponents = components
        newComponents.append(call)
        return Query(components: newComponents)
    }
}

// MARK: - Algorithm Result Processing

/// Helper for processing algorithm results
public struct AlgorithmResult<T: Decodable> {
    public let results: [T]
    public let metadata: [String: Any]?
    
    public init(results: [T], metadata: [String: Any]? = nil) {
        self.results = results
        self.metadata = metadata
    }
}

// MARK: - GraphContext Extensions for Algorithms

public extension GraphContext {
    /// Executes a graph algorithm and returns typed results
    func executeAlgorithm<T: Decodable>(
        _ type: T.Type,
        algorithm: Call
    ) async throws -> [T] {
        let cypher = try algorithm.toCypher()
        let result = try await raw(cypher.query, bindings: cypher.parameters)
        
        // Use the existing mapAll method from ResultMapper extensions
        return try result.mapAll(to: T.self)
    }
    
    /// Executes PageRank and returns scores
    func pageRank(
        damping: Double = 0.85,
        iterations: Int = 20
    ) async throws -> [(nodeId: String, score: Double)] {
        let algorithm = GraphAlgorithms.PageRank.compute(
            damping: damping,
            iterations: iterations
        )
        
        let cypher = try algorithm.toCypher()
        let result = try await raw(cypher.query, bindings: cypher.parameters)
        
        var scores: [(nodeId: String, score: Double)] = []
        while result.hasNext() {
            if let row = try result.getNext() {
                if let nodeId = try row.getValue(0) as? String,
                   let score = try row.getValue(1) as? Double {
                    scores.append((nodeId: nodeId, score: score))
                }
            }
        }
        
        return scores
    }
}