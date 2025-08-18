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
    
    private func mapResult<T>(_ result: QueryResult, to type: T.Type) throws -> T {
        // This is a simplified implementation
        // Real implementation would need proper type mapping based on T
        
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
        
        // Check if this is a tuple type by trying to get the first row and counting columns
        guard result.hasNext() else {
            // For collection types, return empty array
            if String(describing: type).contains("Array") {
                return [] as! T
            }
            throw GraphError.invalidOperation(message: "No results to map")
        }
        
        guard let firstRow = try result.getNext() else {
            throw GraphError.noResults
        }
        
        // Try to detect number of columns by attempting to get values
        var columnCount = 1
        for i in 1..<10 {
            do {
                _ = try firstRow.getValue(UInt64(i))
                columnCount = i + 1
            } catch {
                break
            }
        }
        
        // Handle based on column count
        if columnCount == 1 {
            // Single column result
            let value = try firstRow.getValue(0)
            
            // Check if we need to collect all rows for array types
            if String(describing: type).contains("Array") {
                var items: [Any] = []
                
                // Add first row
                if let kuzuNode = value as? KuzuNode {
                    // For now, just append the node - proper type inference would be needed
                    items.append(kuzuNode)
                } else {
                    items.append(value)
                }
                
                // Collect remaining rows
                while result.hasNext() {
                    guard let row = try result.getNext() else { continue }
                    let val = try row.getValue(0)
                    if let kuzuNode = val as? KuzuNode {
                        items.append(kuzuNode)
                    } else {
                        items.append(val)
                    }
                }
                return items as! T
            }
            
            // Single value result
            if let decodableType = type as? any Decodable.Type {
                if let kuzuNode = value as? KuzuNode {
                    return try decoder.decode(decodableType, from: kuzuNode.properties) as! T
                } else if let properties = value as? [String: Any] {
                    return try decoder.decode(decodableType, from: properties) as! T
                }
            }
            
            return value as! T
            
        } else if columnCount == 2 {
            // Two column result - handle as tuple
            let value0 = try firstRow.getValue(0)
            let value1 = try firstRow.getValue(1)
            
            // If values are already arrays (from COLLECT), use them directly
            if let array0 = value0 as? [Any], let array1 = value1 as? [Any] {
                // Decode KuzuNodes if present
                let decoded0 = array0.map { item -> Any in
                    if let node = item as? KuzuNode {
                        // Try to decode - for now just return the node
                        return node
                    }
                    return item
                }
                
                let decoded1 = array1.map { item -> Any in
                    if let node = item as? KuzuNode {
                        // Try to decode - for now just return the node
                        return node
                    }
                    return item
                }
                
                return (decoded0, decoded1) as! T
            }
            
            // Otherwise collect all rows for each column
            var col0Items: [Any] = []
            var col1Items: [Any] = []
            
            // Process first row
            col0Items.append(value0 as Any)
            col1Items.append(value1 as Any)
            
            // Process remaining rows
            while result.hasNext() {
                guard let row = try result.getNext() else { continue }
                
                let val0 = try row.getValue(0)
                let val1 = try row.getValue(1)
                
                col0Items.append(val0 as Any)
                col1Items.append(val1 as Any)
            }
            
            return (col0Items, col1Items) as! T
            
        } else {
            // Multiple columns - handle as larger tuples
            var columns: [[Any]] = Array(repeating: [], count: columnCount)
            
            // Process first row
            for i in 0..<columnCount {
                let value = try firstRow.getValue(UInt64(i))
                if let node = value as? KuzuNode {
                    // Would need proper type inference here
                    columns[i].append(node)
                } else {
                    columns[i].append(value as Any)
                }
            }
            
            // Process remaining rows
            while result.hasNext() {
                guard let row = try result.getNext() else { continue }
                for i in 0..<columnCount {
                    let value = try row.getValue(UInt64(i))
                    if let node = value as? KuzuNode {
                        columns[i].append(node)
                    } else {
                        columns[i].append(value as Any)
                    }
                }
            }
            
            // Convert to appropriate tuple type
            switch columnCount {
            case 3:
                return (columns[0], columns[1], columns[2]) as! T
            case 4:
                return (columns[0], columns[1], columns[2], columns[3]) as! T
            default:
                return columns as! T
            }
        }
    }
    
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