import Foundation
import Kuzu
import Synchronization

/// GraphContext provides a thread-safe interface to the graph database with SwiftData-compatible API.
///
/// Thread Safety: This class conforms to Sendable using Mutex for state protection:
/// - Pending operations are protected by Mutex<PendingOperations>
/// - Each context has its own dedicated Connection
/// - Kuzu's Connection and Database are internally thread-safe
///
/// Usage Pattern (SwiftData-compatible):
/// ```swift
/// let context = GraphContext(container)
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
    private let connection: Connection

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

    /// Primary initializer - Create a context from a container (ModelContext equivalent)
    /// - Parameter container: The container to use for this context
    public init(_ container: GraphContainer) {
        self.container = container
        self.configuration = container.configuration
        self.encoder = KuzuEncoder(configuration: configuration.encodingConfiguration)
        self.decoder = KuzuDecoder(configuration: configuration.decodingConfiguration)

        // Each context gets its own connection
        do {
            self.connection = try Connection(container.database)
        } catch {
            fatalError("Failed to create connection: \(error)")
        }
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
    public func save() throws {
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

        try executeBatchOperations(operations)
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
    /// SwiftData-compatible API.
    ///
    /// Example:
    /// ```swift
    /// try context.transaction {
    ///     context.insert(user1)
    ///     context.insert(user2)
    ///     context.delete(oldUser)
    ///     // Automatically saved when block completes
    /// }
    /// ```
    ///
    /// - Parameter block: A closure containing the operations to perform
    /// - Throws: Any error thrown by the block or save operation
    public func transaction(_ block: () throws -> Void) throws {
        do {
            try block()
            try save()
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
    ) throws {
        // Execute in a transaction
        _ = try connection.query("BEGIN TRANSACTION")

        do {
            // Execute batch inserts (UNWIND + MERGE)
            for (_, models) in operations.inserts {
                guard let firstModel = models.first else { continue }
                try executeBatchInsert(models, firstModel: firstModel)
            }

            // Execute batch deletes (UNWIND + MATCH/DELETE)
            for (_, models) in operations.deletes {
                guard let firstModel = models.first else { continue }
                try executeBatchDelete(models, firstModel: firstModel)
            }

            _ = try connection.query("COMMIT")
        } catch {
            _ = try? connection.query("ROLLBACK")
            throw GraphError.transactionFailed(reason: "\(error)")
        }
    }

    private func executeBatchInsert(
        _ models: [any GraphNodeModel],
        firstModel: any GraphNodeModel
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
        firstModel: any GraphNodeModel
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
    public func raw(_ query: String, bindings: [String: any Sendable] = [:]) throws -> QueryResult {
        if bindings.isEmpty {
            return try connection.query(query)
        } else {
            let statement = try connection.prepare(query)
            // Convert values to Kuzu-compatible types using KuzuEncoder
            let kuzuParams = try encoder.encodeParameters(bindings)
            return try connection.execute(statement, kuzuParams)
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
    /// try graph.withRawTransaction { connection in
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
        _ block: (Connection) throws -> T
    ) throws -> T {
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

        // Use the component's own mapResult method
        return try queryComponent.mapResult(result, decoder: decoder)
    }

    // MARK: - Transaction Management
    // Transaction support is available through the withTransaction extension method

    // MARK: - Node Operations

    public func find<T: GraphNodeModel & Decodable>(
        _ type: T.Type,
        where conditions: [String: any Sendable] = [:]
    ) throws -> [T] {
        let modelName = T.modelName

        var query = "MATCH (n:\(modelName)"
        if !conditions.isEmpty {
            let conditionStrings = conditions.keys.map { "n.\($0) = $\($0)" }
            query += ") WHERE \(conditionStrings.joined(separator: " AND "))"
        } else {
            query += ")"
        }
        query += " RETURN n"

        let result = try raw(query, bindings: conditions)
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
    ) throws where From: Encodable, To: Encodable {
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

        _ = try raw(query, bindings: bindings)
    }

    // MARK: - Helper Methods
    // Note: mapResult was removed as it was unused and overly complex.
    // Result mapping is now handled by QueryComponent.mapResult() and ResultMapper.

    // MARK: - Schema Operations

    public func createSchema<T: _KuzuGraphModel>(for type: T.Type) throws {
        let ddl = type._kuzuDDL
        _ = try raw(ddl)
    }

    public func createSchema(for types: [any _KuzuGraphModel.Type]) throws {
        // DDL commands cannot be executed within transactions in Kuzu
        // Execute each DDL statement separately
        for type in types {
            _ = try raw(type._kuzuDDL)
        }
    }

    // Create schema only if table doesn't exist
    public func createSchemaIfNotExists<T: _KuzuGraphModel>(for type: T.Type) throws {
        let tableName = String(describing: type)

        // Check if table exists
        let checkQuery = "SHOW TABLES"
        do {
            let result = try raw(checkQuery)
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
                    _ = try raw(type._kuzuDDL)
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
                _ = try raw(type._kuzuDDL)
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
    public func createSchemasIfNotExist(for types: [any _KuzuGraphModel.Type]) throws {
        guard !types.isEmpty else { return }

        // Fetch existing tables and indexes once
        let existingTables = try Self.fetchExistingTables(connection)
        let existingIndexes = try Self.fetchExistingIndexes(connection)

        // Create schema and indexes for each model
        for model in types {
            try Self.createSchemaForModel(
                model,
                existingTables: existingTables,
                existingIndexes: existingIndexes,
                connection: connection
            )
        }
    }

    /// Fetch existing table names from the database
    private static func fetchExistingTables(_ connection: Connection) throws -> Set<String> {
        var tables = Set<String>()

        do {
            let result = try connection.query("SHOW TABLES")
            while result.hasNext() {
                if let row = try result.getNext(),
                   let name = try row.getValue(0) as? String {
                    tables.insert(name)
                }
            }
        } catch {
            // If SHOW TABLES fails, return empty set
            return []
        }

        return tables
    }

    /// Fetch existing vector indexes from the database
    private static func fetchExistingIndexes(_ connection: Connection) throws -> Set<String> {
        var indexes = Set<String>()

        do {
            let result = try connection.query("CALL SHOW_INDEXES() RETURN *")
            while result.hasNext() {
                if let row = try result.getNext(),
                   let tableName = try row.getValue(0) as? String,
                   let indexName = try row.getValue(1) as? String {
                    // Format: "TableName.indexName" for unique identification
                    indexes.insert("\(tableName).\(indexName)")
                }
            }
        } catch {
            // If SHOW_INDEXES fails, return empty set
            return []
        }

        return indexes
    }

    /// Create schema and indexes for a single model
    private static func createSchemaForModel(
        _ type: any _KuzuGraphModel.Type,
        existingTables: Set<String>,
        existingIndexes: Set<String>,
        connection: Connection
    ) throws {
        let tableName = String(describing: type)

        // Step 1: Create table (if it doesn't exist)
        if !existingTables.contains(tableName) {
            do {
                _ = try connection.query(type._kuzuDDL)
            } catch {
                // Ignore "already exists" error (race condition handling)
                let errorMessage = String(describing: error).lowercased()
                if !errorMessage.contains("already exists") &&
                   !errorMessage.contains("catalog") &&
                   !errorMessage.contains("binder exception") {
                    throw error
                }
            }
        }

        // Step 2: Create vector indexes (if they don't exist)
        guard let vectorType = type as? any HasVectorProperties.Type else {
            return
        }

        for property in vectorType._vectorProperties {
            let indexName = property.indexName(for: tableName)
            let indexKey = "\(tableName).\(indexName)"

            // Skip if index already exists
            if existingIndexes.contains(indexKey) {
                continue
            }

            // Create the index
            try VectorIndexManager.createVectorIndex(
                table: tableName,
                column: property.propertyName,
                indexName: indexName,
                metric: property.metric,
                connection: connection
            )
        }
    }
}
