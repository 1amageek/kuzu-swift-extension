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
    public func queryValue<T>(@QueryBuilder _ builder: () -> [QueryComponent], at column: Int = 0) async throws -> T {
        let query = Query(components: builder())
        let cypher = try CypherCompiler.compile(query)
        let result = try await raw(cypher.query, bindings: cypher.parameters)
        
        return try result.mapFirstRequired(to: T.self, at: column)
    }
    
    /// Executes a query and returns an optional value
    public func queryOptional<T>(@QueryBuilder _ builder: () -> [QueryComponent], at column: Int = 0) async throws -> T? {
        let query = Query(components: builder())
        let cypher = try CypherCompiler.compile(query)
        let result = try await raw(cypher.query, bindings: cypher.parameters)
        
        guard result.hasNext() else { return nil }
        return try result.mapFirstRequired(to: T.self, at: column)
    }
    
    /// Executes a query and returns an array of values
    public func queryArray<T>(@QueryBuilder _ builder: () -> [QueryComponent], at column: Int = 0) async throws -> [T] {
        let query = Query(components: builder())
        let cypher = try CypherCompiler.compile(query)
        let result = try await raw(cypher.query, bindings: cypher.parameters)
        
        return try result.column(result.getColumnNames()[column], as: T.self)
    }
    
    /// Executes a query and returns a dictionary
    public func queryRow(@QueryBuilder _ builder: () -> [QueryComponent]) async throws -> [String: Any] {
        let query = Query(components: builder())
        let cypher = try CypherCompiler.compile(query)
        let result = try await raw(cypher.query, bindings: cypher.parameters)
        
        guard let row = try result.mapFirst() else {
            throw GraphError.invalidOperation(message: "No rows returned from query")
        }
        return row
    }
    
    /// Executes a query and returns an array of dictionaries
    public func queryRows(@QueryBuilder _ builder: () -> [QueryComponent]) async throws -> [[String: Any]] {
        let query = Query(components: builder())
        let cypher = try CypherCompiler.compile(query)
        let result = try await raw(cypher.query, bindings: cypher.parameters)
        
        return try result.mapRows()
    }
    
    /// Executes a query and decodes the result to a Codable type
    public func query<T: Decodable>(_ type: T.Type, @QueryBuilder _ builder: () -> [QueryComponent]) async throws -> T {
        let query = Query(components: builder())
        let cypher = try CypherCompiler.compile(query)
        let result = try await raw(cypher.query, bindings: cypher.parameters)
        
        return try result.decode(type)
    }
    
    /// Executes a query and decodes all results to an array of Codable types
    public func queryArray<T: Decodable>(_ type: T.Type, @QueryBuilder _ builder: () -> [QueryComponent]) async throws -> [T] {
        let query = Query(components: builder())
        let cypher = try CypherCompiler.compile(query)
        let result = try await raw(cypher.query, bindings: cypher.parameters)
        
        return try result.decodeArray(type)
    }
    
    /// Executes a query and returns the raw QueryResult
    public func query(@QueryBuilder _ builder: () -> [QueryComponent]) async throws -> QueryResult {
        let query = Query(components: builder())
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
    
    // Create schema only if table doesn't exist
    public func createSchemaIfNotExists<T: _KuzuGraphModel>(for type: T.Type) async throws {
        let tableName = String(describing: type)
        
        // Check if table exists
        let checkQuery = "SHOW TABLES"
        do {
            let result = try await raw(checkQuery)
            let tables = try result.mapRows()
            let exists = tables.contains { row in
                (row["name"] as? String) == tableName
            }
            
            if !exists {
                // Try to create the table
                do {
                    _ = try await raw(type._kuzuDDL)
                } catch {
                    // Check if it's an "already exists" error
                    let errorMessage = String(describing: error).lowercased()
                    if errorMessage.contains("already exists") || 
                       errorMessage.contains("catalog") ||
                       errorMessage.contains("binder exception") {
                        // Table exists - ignore the error
                        return
                    }
                    throw error
                }
            }
        } catch {
            // If SHOW TABLES fails, try to create the table anyway
            do {
                _ = try await raw(type._kuzuDDL)
            } catch {
                // Check if it's an "already exists" error
                let errorMessage = String(describing: error).lowercased()
                if errorMessage.contains("already exists") || 
                   errorMessage.contains("catalog") ||
                   errorMessage.contains("binder exception") {
                    // Table exists - ignore the error
                    return
                }
                throw error
            }
        }
    }
    
    // Create schemas for multiple types, skipping existing ones
    public func createSchemasIfNotExist(for types: [any _KuzuGraphModel.Type]) async throws {
        for type in types {
            try await createSchemaIfNotExists(for: type)
        }
    }
    
    // MARK: - Utility
    
    public func close() async {
        await container.close()
    }
    
}