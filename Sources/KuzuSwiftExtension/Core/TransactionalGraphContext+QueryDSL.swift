import Foundation
import Kuzu

// MARK: - Query DSL Support for TransactionalGraphContext

public extension TransactionalGraphContext {
    
    /// Executes a query using the Query DSL within the transaction
    func query(@QueryBuilder _ builder: () -> Query) throws -> QueryResult {
        let query = builder()
        let cypher = try CypherCompiler.compile(query)
        return try raw(cypher.query, bindings: cypher.parameters)
    }
    
    /// Executes a query and returns an array of decoded results
    func queryArray<T: Decodable>(
        _ type: T.Type,
        @QueryBuilder _ builder: () -> Query
    ) throws -> [T] {
        let result = try query(builder)
        return try result.decodeArray(type)
    }
    
    /// Executes a query and returns a single decoded result
    func queryOne<T: Decodable>(
        _ type: T.Type,
        @QueryBuilder _ builder: () -> Query
    ) throws -> T? {
        let result = try query(builder)
        guard result.hasNext() else { return nil }
        return try result.decode(type)
    }
    
    /// Executes a query and returns a single value
    func queryValue<T>(
        _ type: T.Type = T.self,
        at column: Int = 0,
        @QueryBuilder _ builder: () -> Query
    ) throws -> T {
        let result = try query(builder)
        return try ResultMapper.value(result, at: column)
    }
    
    /// Executes a query and returns an optional value
    func queryOptional<T>(
        _ type: T.Type = T.self,
        at column: Int = 0,
        @QueryBuilder _ builder: () -> Query
    ) throws -> T? {
        let result = try query(builder)
        return try ResultMapper.optionalValue(result, at: column)
    }
    
    /// Executes a query and returns an array of values from a specific column
    func queryColumn<T>(
        _ type: T.Type = T.self,
        at column: Int = 0,
        @QueryBuilder _ builder: () -> Query
    ) throws -> [T] {
        let result = try query(builder)
        return try ResultMapper.column(result, at: column)
    }
    
    /// Executes a query and returns a dictionary (single row)
    func queryRow(@QueryBuilder _ builder: () -> Query) throws -> [String: Any]? {
        let result = try query(builder)
        guard result.hasNext() else { return nil }
        return try ResultMapper.row(result)
    }
    
    /// Executes a query and returns an array of dictionaries
    func queryRows(@QueryBuilder _ builder: () -> Query) throws -> [[String: Any]] {
        let result = try query(builder)
        return try ResultMapper.rows(result)
    }
}

// MARK: - Model-specific Query DSL

public extension TransactionalGraphContext {
    
    /// Queries for nodes matching the DSL criteria
    func query<T: GraphNodeModel>(
        for type: T.Type,
        @QueryBuilder _ builder: () -> Query
    ) throws -> [T] {
        let result = try query(builder)
        let modelName = T.modelName
        
        // Try to decode from the model's alias or common aliases
        let possibleAliases = [
            modelName.lowercased(),
            String(modelName.prefix(1)).lowercased(),
            "n",
            "node"
        ]
        
        for alias in possibleAliases {
            if result.getColumnNames().contains(alias) {
                return try result.decode(T.self, column: alias)
            }
        }
        
        // Fallback to first column
        return try result.decodeArray(T.self)
    }
    
    /// Counts nodes matching the DSL criteria
    func count<T: GraphNodeModel>(
        for type: T.Type,
        @QueryBuilder _ builder: () -> Query
    ) throws -> Int {
        // Build the query with components and add count
        let baseQuery = builder()
        var components = baseQuery.components
        components.append(Return.count())
        
        let countQuery = Query(components: components)
        let cypher = try CypherCompiler.compile(countQuery)
        let result = try raw(cypher.query, bindings: cypher.parameters)
        
        guard result.hasNext(),
              let tuple = try result.getNext(),
              let count = try tuple.getValue(0) as? Int64 else {
            return 0
        }
        
        return Int(count)
    }
}