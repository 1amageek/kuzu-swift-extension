import Foundation
import KuzuFramework

public actor GraphContext {
    private let connectionPool: ConnectionPool
    private let configuration: GraphConfiguration
    private var pendingInserts: [any _KuzuGraphModel] = []
    private var pendingDeletes: [any _KuzuGraphModel] = []
    
    init(connectionPool: ConnectionPool, configuration: GraphConfiguration) {
        self.connectionPool = connectionPool
        self.configuration = configuration
    }
    
    // MARK: - Data Manipulation
    
    public func insert<T: _KuzuGraphModel>(_ model: T) {
        pendingInserts.append(model)
    }
    
    public func delete<T: _KuzuGraphModel>(_ model: T) {
        pendingDeletes.append(model)
    }
    
    public func save() async throws {
        guard !pendingInserts.isEmpty || !pendingDeletes.isEmpty else {
            return
        }
        
        try await connectionPool.withConnection { connection in
            // Process all operations in a single transaction
            try await withTransaction(connection) { conn in
                // Process inserts
                for model in pendingInserts {
                    let cypher = try buildInsertCypher(for: model)
                    if cypher.bindings.isEmpty {
                        _ = try conn.query(cypher.query)
                    } else {
                        let prepared = try conn.prepare(cypher.query)
                        _ = try conn.execute(prepared, cypher.bindings)
                    }
                }
                
                // Process deletes
                for model in pendingDeletes {
                    let cypher = try buildDeleteCypher(for: model)
                    if cypher.bindings.isEmpty {
                        _ = try conn.query(cypher.query)
                    } else {
                        let prepared = try conn.prepare(cypher.query)
                        _ = try conn.execute(prepared, cypher.bindings)
                    }
                }
            }
        }
        
        // Clear pending operations
        pendingInserts.removeAll()
        pendingDeletes.removeAll()
    }
    
    // MARK: - Transactions
    
    public func transaction<T>(_ operation: @escaping (GraphContext) async throws -> T) async throws -> T {
        // Execute operation within this context
        // Since GraphContext is an actor, operations are already serialized
        try await operation(self)
    }
    
    // MARK: - Query Execution
    
    public func query<T: Decodable>(@QueryBuilder _ builder: () -> [QueryComponent]) async throws -> [T] {
        let components = builder()
        let query = Query(components: components, returnType: T.self)
        let compiled = try CypherCompiler.compile(query)
        
        return try await connectionPool.withConnection { connection in
            let result: QueryResult
            
            if compiled.bindings.isEmpty {
                result = try connection.query(compiled.cypher)
            } else {
                let prepared = try connection.prepare(compiled.cypher)
                
                // Bind parameters
                for (key, value) in compiled.bindings {
                    try bindParameter(prepared, key: key, value: value)
                }
                
                result = try prepared.execute()
            }
            
            return try decodeResults(result, as: T.self)
        }
    }
    
    public func raw<T: Decodable>(
        _ cypher: String,
        bindings: [String: any Encodable] = [:]
    ) async throws -> T {
        try await connectionPool.withConnection { connection in
            let result: QueryResult
            
            if bindings.isEmpty {
                result = try connection.query(cypher)
            } else {
                let prepared = try connection.prepare(cypher)
                
                // Bind parameters
                for (key, value) in bindings {
                    try bindParameter(prepared, key: key, value: value)
                }
                
                result = try prepared.execute()
            }
            
            // Check if T is an array type
            if T.self is any Collection.Type {
                return try decodeResults(result, as: T.self) as! T
            } else {
                return try decodeSingleResult(result, as: T.self)
            }
        }
    }
    
    public func rawQuery(
        _ cypher: String,
        bindings: [String: any Encodable] = [:]
    ) async throws -> QueryResult {
        try await connectionPool.withConnection { connection in
            if bindings.isEmpty {
                return try connection.query(cypher)
            } else {
                let prepared = try connection.prepare(cypher)
                
                // Bind parameters
                for (key, value) in bindings {
                    try bindParameter(prepared, key: key, value: value)
                }
                
                return try prepared.execute()
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func buildInsertCypher(for model: any _KuzuGraphModel) throws -> (query: String, bindings: [String: any Encodable]) {
        let tableName = type(of: model)._kuzuTableName
        let isNode = model is any GraphNodeProtocol
        
        // Use Mirror to extract property values
        let mirror = Mirror(reflecting: model)
        var properties: [(String, Any)] = []
        
        for child in mirror.children {
            if let label = child.label {
                properties.append((label, child.value))
            }
        }
        
        if isNode {
            // CREATE (:TableName {prop1: $p1, prop2: $p2})
            var propStrings: [String] = []
            var bindings: [String: any Encodable] = [:]
            
            for (index, (name, value)) in properties.enumerated() {
                let paramName = "p\(index + 1)"
                propStrings.append("\(name): $\(paramName)")
                
                if let encodableValue = value as? any Encodable {
                    bindings[paramName] = encodableValue
                }
            }
            
            let query = "CREATE (:\(tableName) {\(propStrings.joined(separator: ", "))})"
            return (query, bindings)
        } else {
            // For edges, we need FROM and TO
            throw QueryError.compileFailure(
                message: "Edge creation not yet implemented",
                location: "buildInsertCypher"
            )
        }
    }
    
    private func buildDeleteCypher(for model: any _KuzuGraphModel) throws -> (query: String, bindings: [String: any Encodable]) {
        let tableName = type(of: model)._kuzuTableName
        
        // Find ID property
        let mirror = Mirror(reflecting: model)
        var idValue: (String, Any)?
        
        for child in mirror.children {
            if let label = child.label {
                // Check if this is an ID property (simplified check)
                if label == "id" || label.hasSuffix("ID") {
                    idValue = (label, child.value)
                    break
                }
            }
        }
        
        guard let (idName, id) = idValue,
              let encodableId = id as? any Encodable else {
            throw QueryError.compileFailure(
                message: "No ID property found for deletion",
                location: "buildDeleteCypher"
            )
        }
        
        let query = "MATCH (n:\(tableName) {\(idName): $id}) DELETE n"
        return (query, ["id": encodableId])
    }
    
    private func bindParameter(_ prepared: PreparedStatement, key: String, value: any Encodable) throws {
        // Convert Encodable to appropriate Kuzu value type
        // This is a simplified version - in production, we'd handle all types properly
        switch value {
        case let v as Int:
            try prepared.bind(key, Int64(v))
        case let v as Int64:
            try prepared.bind(key, v)
        case let v as String:
            try prepared.bind(key, v)
        case let v as Bool:
            try prepared.bind(key, v)
        case let v as Double:
            try prepared.bind(key, v)
        case let v as Float:
            try prepared.bind(key, Double(v))
        case let v as Date:
            try prepared.bind(key, v.timeIntervalSince1970)
        default:
            // Try to encode as JSON string
            let encoder = JSONEncoder()
            let data = try encoder.encode(value)
            let jsonString = String(data: data, encoding: .utf8) ?? "{}"
            try prepared.bind(key, jsonString)
        }
    }
    
    private func decodeResults<T: Decodable>(_ result: QueryResult, as type: T.Type) throws -> [T] {
        var results: [T] = []
        
        while result.hasNext() {
            guard let tuple = try result.getNext() else {
                continue
            }
            
            // For now, this is a simplified implementation
            // In production, we'd properly decode from FlatTuple to T
            if T.self == Void.self {
                results.append(() as! T)
            } else {
                // This would need proper implementation based on Kuzu's result format
                throw QueryError.executionFailed(
                    cypher: "Unknown",
                    underlying: NSError(
                        domain: "GraphContext",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Result decoding for generic types not yet implemented"]
                    )
                )
            }
        }
        
        return results
    }
    
    private func decodeSingleResult<T: Decodable>(_ result: QueryResult, as type: T.Type) throws -> T {
        guard result.hasNext() else {
            throw QueryError.executionFailed(
                cypher: "Unknown",
                underlying: NSError(domain: "GraphContext", code: 1, userInfo: [NSLocalizedDescriptionKey: "No results returned"])
            )
        }
        
        // This is a placeholder - proper implementation would decode from QueryResult
        // For now, return a default value if T is Void
        if T.self == Void.self {
            return () as! T
        }
        
        throw QueryError.executionFailed(
            cypher: "Unknown",
            underlying: NSError(domain: "GraphContext", code: 2, userInfo: [NSLocalizedDescriptionKey: "Result decoding not yet implemented"])
        )
    }
    
    private func withTransaction<T>(_ connection: Connection, _ block: (Connection) async throws -> T) async throws -> T {
        // Kuzu handles transactions at the connection level
        // For now, we execute operations directly
        // In a full implementation, we'd use BEGIN/COMMIT/ROLLBACK
        try await block(connection)
    }
}