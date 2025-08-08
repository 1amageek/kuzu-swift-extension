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

// MARK: - Query Extension for Debug Support

public extension Query {
    /// Returns the compiled Cypher string
    var cypherString: String? {
        try? CypherCompiler.compile(self).query
    }
    
    /// Returns debug information for the query
    func debugInfo() throws -> QueryDebugInfo {
        let compiled = try CypherCompiler.compile(self)
        let analysis = try? QueryIntrospection.analyze(self)
        
        return QueryDebugInfo(
            cypher: compiled.query,
            parameters: compiled.parameters,
            analysis: analysis
        )
    }
    
    /// Prints debug information to the console
    func printDebug() throws {
        let info = try debugInfo()
        print(info.formattedDescription)
    }
    
    /// Returns the query with explain plan
    func explain() -> Query {
        // Prepend EXPLAIN to the query
        var explainComponents = components
        if let firstComponent = explainComponents.first {
            // Wrap the first component with EXPLAIN
            explainComponents[0] = ExplainWrapper(component: firstComponent)
        }
        return Query(components: explainComponents)
    }
}

/// Debug information for a query
public struct QueryDebugInfo: CustomStringConvertible {
    public let cypher: String
    public let parameters: [String: any Sendable]
    public let analysis: QueryAnalysis?
    
    public init(
        cypher: String,
        parameters: [String: any Sendable],
        analysis: QueryAnalysis? = nil
    ) {
        self.cypher = cypher
        self.parameters = parameters
        self.analysis = analysis
    }
    
    /// Formatted description for debugging
    public var description: String {
        formattedDescription
    }
    
    /// Detailed formatted description
    public var formattedDescription: String {
        var output = "=== Query Debug Info ===\n"
        output += "Cypher:\n\(cypher)\n\n"
        
        if !parameters.isEmpty {
            output += "Parameters:\n"
            for (key, value) in parameters.sorted(by: { $0.key < $1.key }) {
                output += "  $\(key): \(value)\n"
            }
            output += "\n"
        }
        
        if let analysis = analysis {
            output += analysis.description + "\n"
        }
        
        output += "========================"
        return output
    }
    
    /// Returns a compact single-line description
    public var compactDescription: String {
        var parts: [String] = []
        
        // Truncate cypher if too long
        let truncatedCypher = cypher.count > 100 ? 
            String(cypher.prefix(97)) + "..." : cypher
        parts.append(truncatedCypher.replacingOccurrences(of: "\n", with: " "))
        
        if !parameters.isEmpty {
            parts.append("[\(parameters.count) params]")
        }
        
        return parts.joined(separator: " | ")
    }
}

/// A wrapper component that adds EXPLAIN to a query
private struct ExplainWrapper: QueryComponent {
    let component: QueryComponent
    
    func toCypher() throws -> CypherFragment {
        let inner = try component.toCypher()
        return CypherFragment(
            query: "EXPLAIN \(inner.query)",
            parameters: inner.parameters
        )
    }
}