import Foundation
import Kuzu

public actor GraphContext {
    let container: GraphContainer  // Made internal for TransactionalGraphContext
    let configuration: GraphConfiguration  // Made internal for TransactionalGraphContext
    private let encoder: KuzuEncoder
    private let decoder: KuzuDecoder
    private let statementCache: PreparedStatementCache
    
    public init(configuration: GraphConfiguration = GraphConfiguration()) async throws {
        self.configuration = configuration
        self.container = try await GraphContainer(configuration: configuration)
        self.encoder = KuzuEncoder(configuration: configuration.encodingConfiguration)
        self.decoder = KuzuDecoder(configuration: configuration.decodingConfiguration)
        self.statementCache = PreparedStatementCache(
            maxSize: configuration.statementCacheSize,
            ttl: configuration.statementCacheTTL
        )
    }
    
    // MARK: - Raw Query Execution
    
    public func raw(_ query: String, bindings: [String: any Sendable] = [:]) async throws -> QueryResult {
        return try await container.withConnection { connection in
            if bindings.isEmpty {
                return try connection.query(query)
            } else {
                let statement = try connection.prepare(query)
                // Convert values to Kuzu-compatible types using KuzuEncoder
                let kuzuParams = try encoder.encodeParameters(bindings)
                return try connection.execute(statement, kuzuParams)
            }
        }
    }
    
    // MARK: - Query DSL
    
    /// Executes a query and returns a single value
    public func queryValue<T>(@QueryBuilder _ builder: () -> Query, at column: Int = 0) async throws -> T {
        let query = builder()
        let cypher = try CypherCompiler.compile(query)
        let result = try await raw(cypher.query, bindings: cypher.parameters)
        
        return try ResultMapper.value(result, at: column)
    }
    
    /// Executes a query and returns an optional value
    public func queryOptional<T>(@QueryBuilder _ builder: () -> Query, at column: Int = 0) async throws -> T? {
        let query = builder()
        let cypher = try CypherCompiler.compile(query)
        let result = try await raw(cypher.query, bindings: cypher.parameters)
        
        return try ResultMapper.optionalValue(result, at: column)
    }
    
    /// Executes a query and returns an array of values
    public func queryArray<T>(@QueryBuilder _ builder: () -> Query, at column: Int = 0) async throws -> [T] {
        let query = builder()
        let cypher = try CypherCompiler.compile(query)
        let result = try await raw(cypher.query, bindings: cypher.parameters)
        
        return try ResultMapper.column(result, at: column)
    }
    
    /// Executes a query and returns a dictionary
    public func queryRow(@QueryBuilder _ builder: () -> Query) async throws -> [String: Any] {
        let query = builder()
        let cypher = try CypherCompiler.compile(query)
        let result = try await raw(cypher.query, bindings: cypher.parameters)
        
        return try ResultMapper.row(result)
    }
    
    /// Executes a query and returns an array of dictionaries
    public func queryRows(@QueryBuilder _ builder: () -> Query) async throws -> [[String: Any]] {
        let query = builder()
        let cypher = try CypherCompiler.compile(query)
        let result = try await raw(cypher.query, bindings: cypher.parameters)
        
        return try ResultMapper.rows(result)
    }
    
    /// Executes a query and decodes the result to a Codable type
    public func query<T: Decodable>(_ type: T.Type, @QueryBuilder _ builder: () -> Query) async throws -> T {
        let query = builder()
        let cypher = try CypherCompiler.compile(query)
        let result = try await raw(cypher.query, bindings: cypher.parameters)
        
        return try result.decode(type)
    }
    
    /// Executes a query and decodes all results to an array of Codable types
    public func queryArray<T: Decodable>(_ type: T.Type, @QueryBuilder _ builder: () -> Query) async throws -> [T] {
        let query = builder()
        let cypher = try CypherCompiler.compile(query)
        let result = try await raw(cypher.query, bindings: cypher.parameters)
        
        return try result.decodeArray(type)
    }
    
    /// Executes a query and returns the raw QueryResult
    public func query(@QueryBuilder _ builder: () -> Query) async throws -> QueryResult {
        let query = builder()
        let cypher = try CypherCompiler.compile(query)
        
        return try await raw(cypher.query, bindings: cypher.parameters)
    }
    
    // MARK: - Transaction Support
    // Use withTransaction for proper transaction semantics with TransactionalGraphContext
    
    // MARK: - Schema Operations
    
    public func createSchema<T: _KuzuGraphModel>(for type: T.Type) async throws {
        let ddl = type._kuzuDDL
        _ = try await raw(ddl)
    }
    
    public func createSchema(for types: [any _KuzuGraphModel.Type]) async throws {
        // DDL commands cannot be executed within transactions in Kuzu
        // Execute each DDL statement separately
        try await container.withConnection { connection in
            for type in types {
                _ = try connection.query(type._kuzuDDL)
            }
        }
    }
    
    // MARK: - Utility
    
    public func close() async {
        await container.close()
    }
    
}