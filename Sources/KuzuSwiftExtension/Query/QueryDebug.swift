import Foundation
import Kuzu

/// Provides debugging and introspection capabilities for queries
public struct QueryDebug {
    
    /// Configuration for query debugging
    public struct Configuration: Sendable {
        /// Whether to print generated Cypher queries
        public var printCypher: Bool = false
        
        /// Whether to print query parameters
        public var printParameters: Bool = false
        
        /// Whether to print query execution time
        public var printExecutionTime: Bool = false
        
        /// Whether to print result count
        public var printResultCount: Bool = false
        
        /// Custom logger function
        public var logger: (@Sendable (String) -> Void)? = { print($0) }
        
        public init(
            printCypher: Bool = false,
            printParameters: Bool = false,
            printExecutionTime: Bool = false,
            printResultCount: Bool = false,
            logger: (@Sendable (String) -> Void)? = nil
        ) {
            self.printCypher = printCypher
            self.printParameters = printParameters
            self.printExecutionTime = printExecutionTime
            self.printResultCount = printResultCount
            self.logger = logger ?? { print($0) }
        }
        
        /// A configuration that prints everything
        public static let verbose = Configuration(
            printCypher: true,
            printParameters: true,
            printExecutionTime: true,
            printResultCount: true
        )
        
        /// A configuration that prints only the Cypher query
        public static let cypherOnly = Configuration(
            printCypher: true,
            printParameters: false,
            printExecutionTime: false,
            printResultCount: false
        )
        
        /// A configuration that prints performance metrics
        public static let performance = Configuration(
            printCypher: false,
            printParameters: false,
            printExecutionTime: true,
            printResultCount: true
        )
    }
    
    /// The current debug configuration
    nonisolated(unsafe) public static var configuration = Configuration()
    
    /// Enables verbose debugging
    public static func enableVerbose() {
        configuration = .verbose
    }
    
    /// Disables all debugging
    public static func disable() {
        configuration = Configuration()
    }
    
    /// Logs a Cypher query if debugging is enabled
    internal static func logQuery(_ cypher: CypherFragment, executionTime: TimeInterval? = nil, resultCount: Int? = nil) {
        guard let logger = configuration.logger else { return }
        
        var output = ""
        
        if configuration.printCypher {
            output += "[Query DSL] Cypher:\n\(cypher.query)\n"
        }
        
        if configuration.printParameters && !cypher.parameters.isEmpty {
            output += "[Query DSL] Parameters:\n"
            for (key, value) in cypher.parameters {
                output += "  $\(key): \(String(describing: value))\n"
            }
        }
        
        if configuration.printExecutionTime, let time = executionTime {
            output += "[Query DSL] Execution Time: \(String(format: "%.3f", time * 1000))ms\n"
        }
        
        if configuration.printResultCount, let count = resultCount {
            output += "[Query DSL] Result Count: \(count)\n"
        }
        
        if !output.isEmpty {
            logger(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

// MARK: - Query Introspection

/// Provides introspection capabilities for queries
public struct QueryIntrospection {
    
    /// Analyzes a query and returns information about it
    public static func analyze(_ query: Query) throws -> QueryAnalysis {
        let cypher = try CypherCompiler.compile(query)
        
        var nodeTypes = Set<String>()
        var edgeTypes = Set<String>()
        var operations = Set<String>()
        var hasAggregation = false
        var hasSubquery = false
        var estimatedComplexity = 0
        
        for component in query.components {
            switch component {
            case let match as Match:
                operations.insert("MATCH")
                analyzePatterns(match.patterns, nodeTypes: &nodeTypes, edgeTypes: &edgeTypes)
                estimatedComplexity += match.patterns.count * 2
                
            case let optionalMatch as OptionalMatch:
                operations.insert("OPTIONAL MATCH")
                analyzePatterns(optionalMatch.patterns, nodeTypes: &nodeTypes, edgeTypes: &edgeTypes)
                estimatedComplexity += optionalMatch.patterns.count * 3
                
            case is Create:
                operations.insert("CREATE")
                estimatedComplexity += 1
                
            case is Merge:
                operations.insert("MERGE")
                estimatedComplexity += 2
                
            case is Delete:
                operations.insert("DELETE")
                estimatedComplexity += 1
                
            case is SetClause:
                operations.insert("SET")
                estimatedComplexity += 1
                
            case let returnClause as Return:
                operations.insert("RETURN")
                if hasAggregationInReturn(returnClause) {
                    hasAggregation = true
                    estimatedComplexity += 3
                }
                
            case is With:
                operations.insert("WITH")
                hasSubquery = true
                estimatedComplexity += 2
                
            case is Unwind:
                operations.insert("UNWIND")
                estimatedComplexity += 2
                
            default:
                break
            }
        }
        
        return QueryAnalysis(
            cypher: cypher.query,
            parameters: cypher.parameters,
            nodeTypes: Array(nodeTypes),
            edgeTypes: Array(edgeTypes),
            operations: Array(operations),
            hasAggregation: hasAggregation,
            hasSubquery: hasSubquery,
            estimatedComplexity: estimatedComplexity
        )
    }
    
    private static func analyzePatterns(
        _ patterns: [MatchPattern],
        nodeTypes: inout Set<String>,
        edgeTypes: inout Set<String>
    ) {
        for pattern in patterns {
            switch pattern {
            case .node(let type, _, _):
                nodeTypes.insert(type)
            case .edge(let type, _, _, _, _):
                edgeTypes.insert(type)
            case .path(_, _, let edgeType, _, _, _):
                if let edgeType = edgeType {
                    edgeTypes.insert(edgeType)
                }
            case .custom:
                break
            }
        }
    }
    
    private static func hasAggregationInReturn(_ returnClause: Return) -> Bool {
        for item in returnClause.items {
            if case .aliased(let expression, _) = item {
                let aggregationFunctions = ["COUNT", "MAX", "MIN", "SUM", "AVG", "COLLECT"]
                for function in aggregationFunctions {
                    if expression.uppercased().contains(function) {
                        return true
                    }
                }
            }
        }
        return false
    }
}

/// Analysis result for a query
public struct QueryAnalysis {
    /// The generated Cypher query
    public let cypher: String
    
    /// The query parameters
    public let parameters: [String: any Sendable]
    
    /// Node types referenced in the query
    public let nodeTypes: [String]
    
    /// Edge types referenced in the query
    public let edgeTypes: [String]
    
    /// Operations used in the query
    public let operations: [String]
    
    /// Whether the query contains aggregation
    public let hasAggregation: Bool
    
    /// Whether the query contains subqueries
    public let hasSubquery: Bool
    
    /// Estimated complexity score
    public let estimatedComplexity: Int
    
    /// Returns a human-readable description
    public var description: String {
        """
        Query Analysis:
        - Operations: \(operations.joined(separator: ", "))
        - Node Types: \(nodeTypes.isEmpty ? "none" : nodeTypes.joined(separator: ", "))
        - Edge Types: \(edgeTypes.isEmpty ? "none" : edgeTypes.joined(separator: ", "))
        - Has Aggregation: \(hasAggregation)
        - Has Subquery: \(hasSubquery)
        - Complexity Score: \(estimatedComplexity)
        - Parameters: \(parameters.count)
        """
    }
}

// MARK: - Query Profiling

/// Provides profiling capabilities for queries
public struct QueryProfiler {
    /// Profiles a query execution
    public static func profile<T>(
        _ block: () throws -> T
    ) rethrows -> (result: T, profile: QueryProfile) {
        let startTime = Date()
        let result = try block()
        let endTime = Date()
        
        let profile = QueryProfile(
            startTime: startTime,
            endTime: endTime,
            executionTime: endTime.timeIntervalSince(startTime)
        )
        
        return (result, profile)
    }
    
    /// Profiles an async query execution
    public static func profile<T>(
        _ block: () async throws -> T
    ) async rethrows -> (result: T, profile: QueryProfile) {
        let startTime = Date()
        let result = try await block()
        let endTime = Date()
        
        let profile = QueryProfile(
            startTime: startTime,
            endTime: endTime,
            executionTime: endTime.timeIntervalSince(startTime)
        )
        
        return (result, profile)
    }
}

/// Profile information for a query execution
public struct QueryProfile: Sendable {
    /// Start time of the query
    public let startTime: Date
    
    /// End time of the query
    public let endTime: Date
    
    /// Total execution time in seconds
    public let executionTime: TimeInterval
    
    /// Execution time in milliseconds
    public var executionTimeMs: Double {
        executionTime * 1000
    }
    
    /// Returns a human-readable description
    public var description: String {
        "Query executed in \(String(format: "%.3f", executionTimeMs))ms"
    }
}

// MARK: - Debug Extensions

public extension GraphContext {
    /// Executes a query with debugging enabled
    func debugQuery(
        debug: QueryDebug.Configuration = .verbose,
        @QueryBuilder _ builder: () -> Query
    ) async throws -> QueryResult {
        let previousConfig = QueryDebug.configuration
        QueryDebug.configuration = debug
        defer { QueryDebug.configuration = previousConfig }
        
        let query = builder()
        let cypher = try CypherCompiler.compile(query)
        
        // Capture query and parameters locally to avoid sending non-Sendable types
        let queryString = cypher.query
        let queryParams = cypher.parameters
        
        let startTime = Date()
        let result = try await raw(queryString, bindings: queryParams)
        let executionTime = Date().timeIntervalSince(startTime)
        
        // Note: We can't count results without consuming them
        // Log the query without result count
        QueryDebug.logQuery(
            cypher,
            executionTime: executionTime,
            resultCount: nil
        )
        
        return result
    }
    
    /// Analyzes a query without executing it
    func analyzeQuery(@QueryBuilder _ builder: () -> Query) throws -> QueryAnalysis {
        let query = builder()
        return try QueryIntrospection.analyze(query)
    }
}

public extension TransactionalGraphContext {
    /// Executes a query with debugging enabled within a transaction
    func debugQuery(
        debug: QueryDebug.Configuration = .verbose,
        @QueryBuilder _ builder: () -> Query
    ) throws -> QueryResult {
        let previousConfig = QueryDebug.configuration
        QueryDebug.configuration = debug
        defer { QueryDebug.configuration = previousConfig }
        
        let query = builder()
        let cypher = try CypherCompiler.compile(query)
        
        let startTime = Date()
        let result = try raw(cypher.query, bindings: cypher.parameters)
        let executionTime = Date().timeIntervalSince(startTime)
        
        // Note: We can't count results without consuming them
        // Log the query without result count
        QueryDebug.logQuery(
            cypher,
            executionTime: executionTime,
            resultCount: nil
        )
        
        return result
    }
}