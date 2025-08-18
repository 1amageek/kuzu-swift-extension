import Foundation
import Kuzu

/// A transaction context that executes all operations within a single database transaction
/// 
/// This struct ensures that all operations use the same database connection,
/// providing true ACID transaction guarantees. It's a lightweight value type
/// that holds references to the connection and configuration.
public struct TransactionalGraphContext: Sendable {
    let connection: Connection
    let configuration: GraphConfiguration
    
    /// Initialize a transactional context with a specific connection
    init(connection: Connection, configuration: GraphConfiguration) {
        self.connection = connection
        self.configuration = configuration
    }
    
    // MARK: - Transaction Control
    
    /// Begin the transaction
    func begin() throws {
        _ = try connection.query("BEGIN TRANSACTION")
    }
    
    /// Commit the transaction
    func commit() throws {
        _ = try connection.query("COMMIT")
    }
    
    /// Rollback the transaction
    func rollback() throws {
        _ = try? connection.query("ROLLBACK")  // Ignore errors during rollback
    }
    
    // MARK: - Query Operations
    
    /// Execute a raw Cypher query
    public func raw(_ cypher: String, bindings: [String: any Sendable] = [:]) throws -> QueryResult {
        if bindings.isEmpty {
            return try connection.query(cypher)
        } else {
            let preparedStatement = try connection.prepare(cypher)
            // Convert values to Kuzu-compatible types using KuzuEncoder
            let encoder = KuzuEncoder()
            let kuzuParams = try encoder.encodeParameters(bindings)
            return try connection.execute(preparedStatement, kuzuParams)
        }
    }
    
    // MARK: - New Query DSL
    
    /// Execute a query using the new type-safe DSL
    public func query<T: QueryComponent>(@QueryBuilder _ builder: () -> T) throws -> T.Result {
        let queryComponent = builder()
        let cypher = try queryComponent.toCypher()
        
        // Check if we need to add RETURN clause
        let needsReturn = queryComponent.isReturnable && !cypher.query.contains("RETURN")
        var finalQuery = cypher.query
        
        if needsReturn {
            // Auto-generate RETURN clause for returnable components
            if let aliased = queryComponent as? any AliasedComponent {
                finalQuery += " RETURN \(aliased.alias)"
            }
        }
        
        let result = try raw(finalQuery, bindings: cypher.parameters)
        
        // Map result based on component type
        return try mapResult(result, to: T.Result.self)
    }
    
    // MARK: - Model Operations
    
    /// Save a model instance within the transaction
    public func save<T: GraphNodeModel>(_ model: T) throws -> T {
        let columns = T._kuzuColumns
        
        // Extract properties using KuzuEncoder
        let encoder = KuzuEncoder()
        let properties = try encoder.encode(model)
        
        // Check if exists (assuming first column is ID)
        guard let idColumn = columns.first else {
            throw GraphError.invalidConfiguration(message: "Model must have at least one column")
        }
        
        let idValue = properties[idColumn.name]
        
        let existsQuery = """
            MATCH (n:\(T.modelName) {\(idColumn.name): $id})
            RETURN count(n) > 0 as result
            """
        
        let existsResult = try raw(existsQuery, bindings: ["id": idValue ?? NSNull()])
        
        // Get the first row to check existence
        guard existsResult.hasNext(),
              let tuple = try existsResult.getNext(),
              let exists = try tuple.getValue(0) as? Bool else {
            throw GraphError.invalidOperation(message: "Failed to check existence")
        }
        
        if exists {
            // Update existing
            let setClause = QueryHelpers.buildPropertyAssignments(
                columns: Array(columns.dropFirst()),
                isAssignment: true
            )
            .map { "n.\($0)" }
            .joined(separator: ", ")
            
            if !setClause.isEmpty {
                let updateQuery = """
                    MATCH (n:\(T.modelName) {\(idColumn.name): $\(idColumn.name)})
                    SET \(setClause)
                    RETURN n
                    """
                
                _ = try raw(updateQuery, bindings: properties)
            }
        } else {
            // Insert new
            let propertyList = QueryHelpers.buildPropertyAssignments(
                columns: columns,
                isAssignment: false
            )
            .joined(separator: ", ")
            
            let createQuery = """
                CREATE (n:\(T.modelName) {\(propertyList)})
                RETURN n
                """
            
            _ = try raw(createQuery, bindings: properties)
        }
        
        return model
    }
    
    /// Delete a model instance within the transaction
    public func delete<T: GraphNodeModel>(_ model: T) throws {
        guard let idColumn = T._kuzuColumns.first else {
            throw GraphError.invalidConfiguration(message: "Model must have at least one column")
        }
        
        // Extract ID from model
        let encoder = KuzuEncoder()
        let properties = try encoder.encode(model)
        let id = properties[idColumn.name]
        
        let deleteQuery = """
            MATCH (n:\(T.modelName) {\(idColumn.name): $id})
            DELETE n
            """
        
        _ = try raw(deleteQuery, bindings: ["id": id ?? NSNull()])
    }
    
    /// Count instances within the transaction
    public func count<T: GraphNodeModel>(_ type: T.Type) throws -> Int {
        let countQuery = "MATCH (n:\(type.modelName)) RETURN count(n) as count"
        let result = try raw(countQuery)
        
        guard result.hasNext(),
              let tuple = try result.getNext(),
              let count = try tuple.getValue(0) as? Int64 else {
            throw GraphError.invalidOperation(message: "Failed to get count")
        }
        
        return Int(count)
    }
    
    /// Fetch all instances within the transaction
    public func fetch<T: GraphNodeModel>(_ type: T.Type) throws -> [T] {
        let query = """
            MATCH (n:\(type.modelName))
            RETURN n
            """
        let result = try raw(query)
        return try result.decodeArray(T.self)
    }
    
    // MARK: - Helper Methods
    
    private func mapResult<T>(_ result: QueryResult, to type: T.Type) throws -> T {
        // This is a simplified implementation
        // Real implementation would need proper type mapping based on T
        let decoder = KuzuDecoder()
        
        if type == Void.self {
            return () as! T
        }
        
        if type == Int64.self {
            guard result.hasNext() else {
                return 0 as! T
            }
            guard let row = try result.getNext() else {
                return 0 as! T
            }
            let value = try row.getValue(0)
            return (value as? Int64 ?? 0) as! T
        }
        
        // For array types
        if let arrayType = type as? any Collection.Type {
            var items: [Any] = []
            while result.hasNext() {
                guard let row = try result.getNext() else {
                    continue
                }
                let value = try row.getValue(0)
                items.append(value)
            }
            return items as! T
        }
        
        // Default: try to decode first row
        guard result.hasNext() else {
            throw GraphError.invalidOperation(message: "No results to map")
        }
        
        guard let row = try result.getNext() else {
            throw GraphError.noResults
        }
        let value = try row.getValue(0)
        
        if let decodableType = type as? any Decodable.Type {
            if let kuzuNode = value as? KuzuNode {
                return try decoder.decode(decodableType, from: kuzuNode.properties) as! T
            } else if let properties = value as? [String: Any] {
                return try decoder.decode(decodableType, from: properties) as! T
            }
        }
        
        return value as! T
    }
}

// MARK: - GraphContext Extension for Transaction Support

public extension GraphContext {
    /// Execute operations within a database transaction
    /// 
    /// All operations within the closure share the same connection and transaction context,
    /// ensuring ACID properties. If an error is thrown, the transaction is automatically rolled back.
    ///
    /// - Parameter operations: A closure containing the operations to perform within the transaction
    /// - Returns: The result of the operations
    /// - Throws: Any error thrown by the operations or transaction management
    func withTransaction<T: Sendable>(_ operations: @escaping @Sendable (TransactionalGraphContext) throws -> T) async throws -> T {
        return try await container.withConnection { connection in
            let txContext = TransactionalGraphContext(
                connection: connection,
                configuration: self.configuration
            )
            
            // Begin transaction
            try txContext.begin()
            
            do {
                // Execute operations
                let result = try operations(txContext)
                
                // Commit on success
                try txContext.commit()
                
                return result
            } catch {
                // Rollback on error
                try txContext.rollback()
                throw error
            }
        }
    }
}