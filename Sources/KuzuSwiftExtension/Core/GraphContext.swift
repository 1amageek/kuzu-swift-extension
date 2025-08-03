import Foundation
import Kuzu

public actor GraphContext {
    private let container: GraphContainer
    private let configuration: GraphConfiguration
    
    public init(configuration: GraphConfiguration = GraphConfiguration()) async throws {
        self.configuration = configuration
        self.container = try await GraphContainer(configuration: configuration)
    }
    
    // MARK: - Raw Query Execution
    
    public func raw(_ query: String, bindings: [String: any Sendable] = [:]) async throws -> QueryResult {
        return try await container.withConnection { connection in
            if bindings.isEmpty {
                return try connection.query(query)
            } else {
                let statement = try connection.prepare(query)
                // Convert Date and UUID to Kuzu-compatible types
                let kuzuParams = bindings.mapValues { value -> Any? in
                    switch value {
                    case let date as Date:
                        return date.timeIntervalSince1970
                    case let uuid as UUID:
                        return uuid.uuidString
                    case is NSNull:
                        return nil
                    default:
                        return value
                    }
                }
                return try connection.execute(statement, kuzuParams)
            }
        }
    }
    
    public func rawTransaction(_ query: String, bindings: [String: any Sendable] = [:]) async throws -> QueryResult {
        return try await container.withTransaction { connection in
            if bindings.isEmpty {
                return try connection.query(query)
            } else {
                let statement = try connection.prepare(query)
                // Convert Date and UUID to Kuzu-compatible types
                let kuzuParams = bindings.mapValues { value -> Any? in
                    switch value {
                    case let date as Date:
                        return date.timeIntervalSince1970
                    case let uuid as UUID:
                        return uuid.uuidString
                    case is NSNull:
                        return nil
                    default:
                        return value
                    }
                }
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
    
    /// Executes a query in a transaction and returns a single value
    public func transactionValue<T>(@QueryBuilder _ builder: () -> Query, at column: Int = 0) async throws -> T {
        let query = builder()
        let cypher = try CypherCompiler.compile(query)
        let result = try await rawTransaction(cypher.query, bindings: cypher.parameters)
        
        return try ResultMapper.value(result, at: column)
    }
    
    /// Executes a query in a transaction and returns an array of values
    public func transactionArray<T>(@QueryBuilder _ builder: () -> Query, at column: Int = 0) async throws -> [T] {
        let query = builder()
        let cypher = try CypherCompiler.compile(query)
        let result = try await rawTransaction(cypher.query, bindings: cypher.parameters)
        
        return try ResultMapper.column(result, at: column)
    }
    
    /// Executes a query in a transaction and decodes the result
    public func transaction<T: Decodable>(_ type: T.Type, @QueryBuilder _ builder: () -> Query) async throws -> T {
        let query = builder()
        let cypher = try CypherCompiler.compile(query)
        let result = try await rawTransaction(cypher.query, bindings: cypher.parameters)
        
        return try result.decode(type)
    }
    
    /// Executes a query in a transaction and returns the raw QueryResult
    public func transaction(@QueryBuilder _ builder: () -> Query) async throws -> QueryResult {
        let query = builder()
        let cypher = try CypherCompiler.compile(query)
        
        return try await rawTransaction(cypher.query, bindings: cypher.parameters)
    }
    
    // MARK: - Schema Operations
    
    public func createSchema<T: _KuzuGraphModel>(for type: T.Type) async throws {
        let ddl = type._kuzuDDL
        _ = try await raw(ddl)
    }
    
    public func createSchema(for types: [any _KuzuGraphModel.Type]) async throws {
        try await container.withTransaction { connection in
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