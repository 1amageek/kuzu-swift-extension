import Foundation
import Kuzu

/// Protocol for types that can execute queries with debugging
public protocol QueryDebuggable {
    func raw(_ query: String, bindings: [String: any Sendable]) async throws -> QueryResult
}

// Default implementation for async contexts
public extension QueryDebuggable {
    /// Executes a query with debugging enabled
    func debugQuery(
        debug: QueryDebug.Configuration = .verbose,
        @QueryBuilder _ builder: () -> [QueryComponent]
    ) async throws -> QueryResult {
        let previousConfig = QueryDebug.configuration
        QueryDebug.configuration = debug
        defer { QueryDebug.configuration = previousConfig }
        
        let query = Query(components: builder())
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
    func analyzeQuery(@QueryBuilder _ builder: () -> [QueryComponent]) throws -> QueryAnalysis {
        let query = Query(components: builder())
        return try QueryIntrospection.analyze(query)
    }
}

// Conform GraphContext to QueryDebuggable
extension GraphContext: QueryDebuggable {}

// Special implementation for TransactionalGraphContext (synchronous)
public extension TransactionalGraphContext {
    /// Executes a query with debugging enabled within a transaction
    func debugQuery(
        debug: QueryDebug.Configuration = .verbose,
        @QueryBuilder _ builder: () -> [QueryComponent]
    ) throws -> QueryResult {
        let previousConfig = QueryDebug.configuration
        QueryDebug.configuration = debug
        defer { QueryDebug.configuration = previousConfig }
        
        let query = Query(components: builder())
        let cypher = try CypherCompiler.compile(query)
        
        let startTime = Date()
        let result = try raw(cypher.query, bindings: cypher.parameters)
        let executionTime = Date().timeIntervalSince(startTime)
        
        QueryDebug.logQuery(
            cypher,
            executionTime: executionTime,
            resultCount: nil
        )
        
        return result
    }
}