import Foundation
import Kuzu
import Synchronization

/// GraphContext provides a thread-safe interface to the graph database with SwiftData-compatible API.
///
/// Thread Safety: This class conforms to Sendable using Mutex for state protection:
/// - Pending operations are protected by Mutex<PendingOperations>
/// - Kuzu's Connection and Database are internally thread-safe
/// - ConnectionPool is an actor providing synchronized access to connections
///
/// Usage Pattern (SwiftData-compatible):
/// ```swift
/// let context = try await GraphContext(configuration: config)
///
/// // Accumulate changes
/// context.insert(user1)
/// context.insert(user2)
/// context.delete(oldUser)
///
/// // Commit all changes in a single transaction
/// try await context.save()
/// ```
public final class GraphContext: Sendable {
    let container: GraphContainer
    let configuration: GraphConfiguration
    private let encoder: KuzuEncoder
    private let decoder: KuzuDecoder

    // Pending operations protected by Mutex
    private let pendingOperations = Mutex<PendingOperations>(
        PendingOperations()
    )

    private struct PendingOperations {
        // Type name -> Array of models to insert
        var insertsByType: [String: [any GraphNodeModel]] = [:]
        // Type name -> Array of models to delete
        var deletesByType: [String: [any GraphNodeModel]] = [:]
    }

    public init(configuration: GraphConfiguration = GraphConfiguration()) async throws {
        self.configuration = configuration
        self.container = try await GraphContainer(configuration: configuration)
        self.encoder = KuzuEncoder(configuration: configuration.encodingConfiguration)
        self.decoder = KuzuDecoder(configuration: configuration.decodingConfiguration)
    }

    // MARK: - SwiftData-Compatible API

    /// Registers a model for insertion during the next save operation
    ///
    /// This method accumulates the model in memory and does not immediately
    /// execute a database operation. Call `save()` to commit all pending changes.
    ///
    /// - Parameter model: The model to insert
    public func insert<T: GraphNodeModel>(_ model: T) {
        pendingOperations.withLock { ops in
            let typeName = T.modelName
            ops.insertsByType[typeName, default: []].append(model)
        }
    }

    /// Registers a model for deletion during the next save operation
    ///
    /// This method accumulates the model in memory and does not immediately
    /// execute a database operation. Call `save()` to commit all pending changes.
    ///
    /// - Parameter model: The model to delete
    public func delete<T: GraphNodeModel>(_ model: T) {
        pendingOperations.withLock { ops in
            let typeName = T.modelName
            ops.deletesByType[typeName, default: []].append(model)
        }
    }

    /// Commits all pending inserts and deletes to the database in a single transaction
    ///
    /// This method executes all accumulated insert and delete operations using
    /// batch optimization (UNWIND + MERGE/DELETE) for maximum performance.
    /// All operations are executed within a single transaction, providing ACID guarantees.
    ///
    /// - Throws: GraphError if the transaction fails
    public func save() async throws {
        let operations = pendingOperations.withLock { ops in
            let result = (
                inserts: ops.insertsByType,
                deletes: ops.deletesByType
            )
            ops.insertsByType.removeAll()
            ops.deletesByType.removeAll()
            return result
        }

        guard !operations.inserts.isEmpty || !operations.deletes.isEmpty else {
            return  // Nothing to save
        }

        try await executeBatchOperations(operations)
    }

    /// Discards all pending inserts and deletes without saving them
    ///
    /// Use this method to abandon changes that have been accumulated
    /// but not yet committed with `save()`.
    public func rollback() {
        pendingOperations.withLock { ops in
            ops.insertsByType.removeAll()
            ops.deletesByType.removeAll()
        }
    }

    /// Execute operations within an implicit transaction
    ///
    /// This method executes the provided block and automatically saves all
    /// accumulated changes when the block completes successfully. If an error
    /// is thrown, changes are rolled back.
    ///
    /// SwiftData-compatible API (async version due to actor isolation requirements).
    ///
    /// Example:
    /// ```swift
    /// try await context.transaction {
    ///     context.insert(user1)
    ///     context.insert(user2)
    ///     context.delete(oldUser)
    ///     // Automatically saved when block completes
    /// }
    /// ```
    ///
    /// - Parameter block: A closure containing the operations to perform
    /// - Throws: Any error thrown by the block or save operation
    public func transaction(_ block: () throws -> Void) async throws {
        do {
            try block()
            try await save()
        } catch {
            rollback()
            throw error
        }
    }

    /// Execute async operations within an implicit transaction
    ///
    /// Async version of transaction that supports async/await operations
    /// within the transaction block.
    ///
    /// Example:
    /// ```swift
    /// try await context.transaction {
    ///     context.insert(user1)
    ///     let count = try await context.count(User.self)
    ///     context.insert(user2)
    ///     // Automatically saved when block completes
    /// }
    /// ```
    ///
    /// - Parameter block: An async closure containing the operations to perform
    /// - Throws: Any error thrown by the block or save operation
    public func transaction(_ block: () async throws -> Void) async throws {
        do {
            try await block()
            try await save()
        } catch {
            rollback()
            throw error
        }
    }

    // MARK: - Batch Execution

    private func executeBatchOperations(
        _ operations: (
            inserts: [String: [any GraphNodeModel]],
            deletes: [String: [any GraphNodeModel]]
        )
    ) async throws {
        // withTransaction already handles BEGIN/COMMIT/ROLLBACK
        try await container.withTransaction { connection in
            // Execute batch inserts (UNWIND + MERGE)
            for (_, models) in operations.inserts {
                guard let firstModel = models.first else { continue }
                try executeBatchInsert(models, firstModel: firstModel, connection: connection)
            }

            // Execute batch deletes (UNWIND + MATCH/DELETE)
            for (_, models) in operations.deletes {
                guard let firstModel = models.first else { continue }
                try executeBatchDelete(models, firstModel: firstModel, connection: connection)
            }
        }
    }

    private func executeBatchInsert(
        _ models: [any GraphNodeModel],
        firstModel: any GraphNodeModel,
        connection: Connection
    ) throws {
        guard !models.isEmpty else { return }

        // Get type information from the first model
        let modelType = type(of: firstModel)
        let graphModelType = modelType as any _KuzuGraphModel.Type

        let columns = graphModelType._kuzuColumns
        let modelName = String(describing: graphModelType)

        guard let idColumn = columns.first else {
            throw GraphError.invalidConfiguration(message: "Model must have at least one column")
        }

        // Encode all models
        let items: [[String: any Sendable]] = try models.map { model in
            let encodable = model as any Encodable
            return try encoder.encode(encodable)
        }

        // Check if model has vector properties (requires special handling)
        let hasVectorProperties = graphModelType is any HasVectorProperties.Type

        // Build query
        let nonIdColumns = Array(columns.dropFirst())

        let query: String
        if hasVectorProperties {
            // For models with vector indexes, use DELETE + CREATE instead of MERGE
            // This avoids the "Cannot set property in table because it is used in indexes" error
            if nonIdColumns.isEmpty {
                query = """
                    UNWIND $items AS item
                    OPTIONAL MATCH (n:\(modelName) {\(idColumn.name): item.\(idColumn.name)})
                    DELETE n
                    WITH item
                    CREATE (n:\(modelName) {\(idColumn.name): item.\(idColumn.name)})
                    """
            } else {
                let allAssignments = ([idColumn] + nonIdColumns).map { column -> String in
                    let value = column.type == "TIMESTAMP"
                        ? "timestamp(item.\(column.name))"
                        : "item.\(column.name)"
                    return "\(column.name): \(value)"
                }.joined(separator: ", ")

                query = """
                    UNWIND $items AS item
                    OPTIONAL MATCH (n:\(modelName) {\(idColumn.name): item.\(idColumn.name)})
                    DELETE n
                    WITH item
                    CREATE (n:\(modelName) {\(allAssignments)})
                    """
            }
        } else if nonIdColumns.isEmpty {
            query = """
                UNWIND $items AS item
                MERGE (n:\(modelName) {\(idColumn.name): item.\(idColumn.name)})
                """
        } else {
            let createAssignments = nonIdColumns.map { column -> String in
                let value = column.type == "TIMESTAMP"
                    ? "timestamp(item.\(column.name))"
                    : "item.\(column.name)"
                return "n.\(column.name) = \(value)"
            }.joined(separator: ", ")

            let updateAssignments = nonIdColumns.map { column -> String in
                let value = column.type == "TIMESTAMP"
                    ? "timestamp(item.\(column.name))"
                    : "item.\(column.name)"
                return "n.\(column.name) = \(value)"
            }.joined(separator: ", ")

            query = """
                UNWIND $items AS item
                MERGE (n:\(modelName) {\(idColumn.name): item.\(idColumn.name)})
                ON CREATE SET \(createAssignments)
                ON MATCH SET \(updateAssignments)
                """
        }

        // Execute query with parameter binding
        if !items.isEmpty {
            let statement = try connection.prepare(query)
            let kuzuParams = try encoder.encodeParameters(["items": items])
            _ = try connection.execute(statement, kuzuParams)
        }
    }

    private func executeBatchDelete(
        _ models: [any GraphNodeModel],
        firstModel: any GraphNodeModel,
        connection: Connection
    ) throws {
        guard !models.isEmpty else { return }

        // Get type information from the first model
        let modelType = type(of: firstModel)
        let graphModelType = modelType as any _KuzuGraphModel.Type

        let columns = graphModelType._kuzuColumns
        let modelName = String(describing: graphModelType)

        guard let idColumn = columns.first else {
            throw GraphError.invalidConfiguration(message: "Model must have at least one column")
        }

        // Extract IDs from all models
        let ids: [any Sendable] = try models.map { model in
            let encodable = model as any Encodable
            let properties = try encoder.encode(encodable)
            guard let id = properties[idColumn.name] else {
                throw GraphError.invalidOperation(message: "Model missing ID property")
            }
            return id
        }

        // Build UNWIND + MATCH/DELETE query
        let query = """
            UNWIND $ids AS id
            MATCH (n:\(modelName) {\(idColumn.name): id})
            DELETE n
            """

        // Execute query with parameter binding
        let statement = try connection.prepare(query)
        let kuzuParams = try encoder.encodeParameters(["ids": ids])
        _ = try connection.execute(statement, kuzuParams)
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

    /// Execute multiple raw Cypher queries in a single transaction
    ///
    /// This method is useful when you need to execute multiple raw Cypher queries
    /// that must all succeed or all fail together. The block receives a Connection
    /// that can be used to execute queries within the transaction.
    ///
    /// Example:
    /// ```swift
    /// try await graph.withRawTransaction { connection in
    ///     _ = try connection.query("CREATE (n:User {id: 1, name: 'Alice'})")
    ///     _ = try connection.query("CREATE (p:Post {id: 1, title: 'Hello'})")
    ///     return "Success"
    /// }
    /// ```
    ///
    /// - Parameter block: A closure that receives a Connection and returns a result
    /// - Returns: The result of the block
    /// - Throws: GraphError if the transaction fails
    public func withRawTransaction<T>(
        _ block: @escaping @Sendable (Connection) throws -> T
    ) async throws -> T {
        return try await container.withTransaction { connection in
            _ = try connection.query("BEGIN TRANSACTION")

            do {
                let result = try block(connection)
                _ = try connection.query("COMMIT")
                return result
            } catch {
                _ = try? connection.query("ROLLBACK")
                throw error
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
        guard !types.isEmpty else { return }

        // Get all existing tables in a single query
        var existingTables: Set<String> = []
        do {
            let result = try await raw("SHOW TABLES")
            while result.hasNext() {
                guard let row = try result.getNext() else { continue }
                if let name = try row.getValue(0) as? String {
                    existingTables.insert(name)
                }
            }
        } catch {
            // If SHOW TABLES fails, proceed with creating all tables
            existingTables = []
        }

        // Create only non-existing tables
        for type in types {
            let tableName = String(describing: type)

            // Skip if table already exists
            if existingTables.contains(tableName) {
                continue
            }

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
                    continue
                }
                throw error
            }
        }

        // Create vector indexes for models with @Vector properties
        for type in types {
            // Check if the type has vector properties
            if let vectorType = type as? any HasVectorProperties.Type {
                // Use type erasure to call the static method
                try await createVectorIndexesForType(vectorType, context: self)
            }
        }
    }

    /// Helper function to create vector indexes with type erasure
    private func createVectorIndexesForType(
        _ type: any HasVectorProperties.Type,
        context: GraphContext
    ) async throws {
        // We need to cast to a specific type that conforms to both protocols
        // This is safe because the macro ensures both conformances
        guard let graphModelType = type as? any _KuzuGraphModel.Type else {
            return
        }

        // Extract table name
        let tableName = String(describing: graphModelType)

        // Use VectorIndexManager to create indexes
        for property in type._vectorProperties {
            let indexName = property.indexName(for: tableName)

            // Check if index exists
            if try await VectorIndexManager.hasVectorIndex(
                table: tableName,
                indexName: indexName,
                context: context
            ) {
                continue
            }

            // Create the index
            try await VectorIndexManager.createVectorIndex(
                table: tableName,
                column: property.propertyName,
                indexName: indexName,
                metric: property.metric,
                context: context
            )
        }
    }
    
    // MARK: - Utility
    
    public func close() async {
        await container.close()
    }
}
