import Foundation
import Kuzu

/// GraphContext provides a thread-safe interface to the graph database.
///
/// Thread Safety: This struct conforms to Sendable because:
/// - All properties are immutable (let)
/// - Kuzu's Connection and Database are internally thread-safe
/// - ConnectionPool is an actor providing synchronized access to connections
/// - Multiple concurrent operations can safely use different connections from the pool
///
/// Performance: Using a struct with no actor isolation allows true concurrent access to the
/// connection pool, enabling multiple tasks to execute queries in parallel across different connections.
public struct GraphContext: Sendable {
    let container: GraphContainer  // Made internal for TransactionalGraphContext
    let configuration: GraphConfiguration  // Made internal for TransactionalGraphContext
    private let encoder: KuzuEncoder
    private let decoder: KuzuDecoder

    public init(configuration: GraphConfiguration = GraphConfiguration()) async throws {
        self.configuration = configuration
        self.container = try await GraphContainer(configuration: configuration)
        self.encoder = KuzuEncoder(configuration: configuration.encodingConfiguration)
        self.decoder = KuzuDecoder(configuration: configuration.decodingConfiguration)
    }
    
    // MARK: - Raw Query Execution
    @discardableResult
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
    
    // MARK: - New Query DSL
    
    /// Execute a query using the new type-safe DSL
    public func query<T: QueryComponent>(@QueryBuilder _ builder: () -> T) async throws -> T.Result {
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
        
        let result = try await raw(finalQuery, bindings: cypher.parameters)
        
        // Use the component's own mapResult method
        return try queryComponent.mapResult(result, decoder: decoder)
    }
    
    // MARK: - Transaction Management
    // Transaction support is available through the withTransaction extension method
    
    // MARK: - Node Operations
    
    public func find<T: GraphNodeModel & Decodable>(
        _ type: T.Type,
        where conditions: [String: any Sendable] = [:]
    ) async throws -> [T] {
        let modelName = T.modelName
        
        var query = "MATCH (n:\(modelName)"
        if !conditions.isEmpty {
            let conditionStrings = conditions.keys.map { "n.\($0) = $\($0)" }
            query += ") WHERE \(conditionStrings.joined(separator: " AND "))"
        } else {
            query += ")"
        }
        query += " RETURN n"
        
        let result = try await raw(query, bindings: conditions)
        var nodes: [T] = []
        
        while result.hasNext() {
            guard let row = try result.getNext() else {
                continue
            }
            let nodeData = try row.getValue(0)
            
            if let kuzuNode = nodeData as? KuzuNode {
                let node = try decoder.decode(T.self, from: kuzuNode.properties)
                nodes.append(node)
            }
        }
        
        return nodes
    }
    
    // MARK: - Edge Operations
    
    public func connect<E: GraphEdgeModel & Encodable, From: GraphNodeModel, To: GraphNodeModel>(
        from source: From,
        to target: To,
        edge: E
    ) async throws where From: Encodable, To: Encodable {
        let sourceProps = try encoder.encode(source)
        let targetProps = try encoder.encode(target)
        let edgeProps = try encoder.encode(edge)
        
        let edgeName = E.edgeName
        let fromModel = From.modelName
        let toModel = To.modelName
        
        // Assume both nodes have id property
        guard let sourceId = sourceProps["id"],
              let targetId = targetProps["id"] else {
            throw GraphError.invalidOperation(message: "Both nodes must have id properties")
        }
        
        var query = """
            MATCH (from:\(fromModel) {id: $fromId}), (to:\(toModel) {id: $toId})
            CREATE (from)-[e:\(edgeName)
            """
        
        if !edgeProps.isEmpty {
            let propStrings = edgeProps.map { key, _ in "\(key): $edge_\(key)" }
            query += " {\(propStrings.joined(separator: ", "))}"
        }
        query += "]->(to)"
        
        var bindings: [String: any Sendable] = [
            "fromId": sourceId,
            "toId": targetId
        ]
        
        for (key, value) in edgeProps {
            bindings["edge_\(key)"] = value
        }
        
        _ = try await raw(query, bindings: bindings)
    }
    
    // MARK: - Helper Methods
    // Note: mapResult was removed as it was unused and overly complex.
    // Result mapping is now handled by QueryComponent.mapResult() and ResultMapper.
    
    // MARK: - Schema Operations
    
    public func createSchema<T: _KuzuGraphModel>(for type: T.Type) async throws {
        let ddl = type._kuzuDDL
        _ = try await raw(ddl)
    }
    
    public func createSchema(for types: [any _KuzuGraphModel.Type]) async throws {
        // DDL commands cannot be executed within transactions in Kuzu
        // Execute each DDL statement separately
        for type in types {
            _ = try await raw(type._kuzuDDL)
        }
    }
    
    // Create schema only if table doesn't exist
    public func createSchemaIfNotExists<T: _KuzuGraphModel>(for type: T.Type) async throws {
        let tableName = String(describing: type)
        
        // Check if table exists
        let checkQuery = "SHOW TABLES"
        do {
            let result = try await raw(checkQuery)
            var tables: [String] = []
            while result.hasNext() {
                guard let row = try result.getNext() else { continue }
                if let name = try row.getValue(0) as? String {
                    tables.append(name)
                }
            }
            
            if !tables.contains(tableName) {
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
