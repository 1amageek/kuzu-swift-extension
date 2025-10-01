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
        // Array of models to insert (Node or Edge)
        var inserts: [any _KuzuGraphModel & Codable] = []
        // Array of models to delete (Node or Edge)
        var deletes: [any _KuzuGraphModel & Codable] = []
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

    // MARK: - Notifications (SwiftData Compatible)

    /// Notification posted before the context saves changes
    public static let willSave = Notification.Name("GraphContext.willSave")

    /// Notification posted after the context saves changes
    ///
    /// The notification's userInfo dictionary contains the persistent identifiers
    /// of any inserted, updated, or deleted models. Use NotificationKey to access those identifiers.
    public static let didSave = Notification.Name("GraphContext.didSave")

    /// Keys for accessing data in notification userInfo dictionaries
    public enum NotificationKey: String {
        /// A set of values identifying the context's inserted models
        case insertedIdentifiers
        /// A set of values identifying the context's deleted models
        case deletedIdentifiers
        /// A set of values identifying the context's updated models
        case updatedIdentifiers
        /// A set of values identifying the context's invalidated models
        case invalidatedAllIdentifiers
        /// A token that indicates which generation of the model store is being used
        case queryGeneration
    }

    // MARK: - Change Tracking (SwiftData Compatible)

    /// A Boolean value that indicates whether the context has unsaved changes
    ///
    /// SwiftData-compatible API.
    ///
    /// Example:
    /// ```swift
    /// context.insert(user)
    /// print(context.hasChanges)  // true
    ///
    /// try context.save()
    /// print(context.hasChanges)  // false
    /// ```
    public var hasChanges: Bool {
        pendingOperations.withLock { ops in
            !ops.inserts.isEmpty || !ops.deletes.isEmpty
        }
    }

    /// The array of inserted models that the context is yet to persist
    ///
    /// Returns both Node and Edge models.
    ///
    /// SwiftData-compatible API.
    public var insertedModelsArray: [any _KuzuGraphModel & Codable] {
        pendingOperations.withLock { ops in
            ops.inserts
        }
    }

    /// The array of registered models that the context will remove from persistent storage during the next save
    ///
    /// Returns both Node and Edge models.
    ///
    /// SwiftData-compatible API.
    public var deletedModelsArray: [any _KuzuGraphModel & Codable] {
        pendingOperations.withLock { ops in
            ops.deletes
        }
    }

    /// The array of registered models that have unsaved changes
    ///
    /// Note: Currently returns empty array. In Kuzu, updates are handled via insert (MERGE operation).
    /// Modified models should be re-inserted.
    ///
    /// SwiftData-compatible API.
    public var changedModelsArray: [any _KuzuGraphModel & Codable] {
        // In Kuzu, updates are done via MERGE (insert with same ID)
        // So we don't track separate "changed" models
        []
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
            ops.inserts.append(model)
        }
    }

    /// Registers an edge model for insertion during the next save operation
    ///
    /// This method accumulates the edge in memory and does not immediately
    /// execute a database operation. Call `save()` to commit all pending changes.
    ///
    /// - Parameter model: The edge model to insert
    public func insert<T: GraphEdgeModel>(_ model: T) {
        pendingOperations.withLock { ops in
            ops.inserts.append(model)
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
            ops.deletes.append(model)
        }
    }

    /// Registers an edge model for deletion during the next save operation
    ///
    /// This method accumulates the edge in memory and does not immediately
    /// execute a database operation. Call `save()` to commit all pending changes.
    ///
    /// - Parameter model: The edge model to delete
    public func delete<T: GraphEdgeModel>(_ model: T) {
        pendingOperations.withLock { ops in
            ops.deletes.append(model)
        }
    }

    /// Commits all pending inserts and deletes to the database in a single transaction
    ///
    /// This method executes all accumulated insert and delete operations using
    /// batch optimization (UNWIND + MERGE/DELETE) for maximum performance.
    /// All operations are executed within a single transaction, providing ACID guarantees.
    ///
    /// Posts `willSave` notification before saving and `didSave` notification after successful save.
    ///
    /// - Throws: GraphError if the transaction fails
    public func save() throws {
        let operations = pendingOperations.withLock { ops in
            let result = (inserts: ops.inserts, deletes: ops.deletes)
            ops.inserts.removeAll()
            ops.deletes.removeAll()
            return result
        }

        guard !operations.inserts.isEmpty || !operations.deletes.isEmpty else {
            return  // Nothing to save
        }

        // Post willSave notification
        NotificationCenter.default.post(name: Self.willSave, object: self)

        // Group by type for batch execution
        let insertsByType = Dictionary(grouping: operations.inserts) {
            String(describing: type(of: $0))
        }
        let deletesByType = Dictionary(grouping: operations.deletes) {
            String(describing: type(of: $0))
        }

        // Collect identifiers for didSave notification
        let insertedIDs = try collectIdentifiers(from: insertsByType)
        let deletedIDs = try collectIdentifiers(from: deletesByType)

        // Execute the save
        try executeBatchOperations((inserts: insertsByType, deletes: deletesByType))

        // Post didSave notification with userInfo
        let userInfo: [String: Any] = [
            NotificationKey.insertedIdentifiers.rawValue: insertedIDs,
            NotificationKey.deletedIdentifiers.rawValue: deletedIDs,
            NotificationKey.updatedIdentifiers.rawValue: []  // Empty for now
        ]
        NotificationCenter.default.post(
            name: Self.didSave,
            object: self,
            userInfo: userInfo
        )
    }

    /// Collect model identifiers from operations
    private func collectIdentifiers(from operations: [String: [any _KuzuGraphModel & Codable]]) throws -> [String] {
        var identifiers: [String] = []

        for (typeName, models) in operations {
            guard let firstModel = models.first else { continue }

            // Get the model type to access _kuzuColumns
            let modelType = type(of: firstModel)
            let graphModelType = modelType as any _KuzuGraphModel.Type

            let columns = graphModelType._kuzuColumns
            guard let idColumn = columns.first else { continue }

            for model in models {
                let encodable = model as any Encodable
                let properties = try encoder.encode(encodable)

                // Get the ID value using the ID column name
                if let idValue = properties[idColumn.name] {
                    identifiers.append("\(typeName):\(idValue)")
                }
            }
        }

        return identifiers
    }

    /// Discards all pending inserts and deletes without saving them
    ///
    /// Use this method to abandon changes that have been accumulated
    /// but not yet committed with `save()`.
    public func rollback() {
        pendingOperations.withLock { ops in
            ops.inserts.removeAll()
            ops.deletes.removeAll()
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
            inserts: [String: [any _KuzuGraphModel & Codable]],
            deletes: [String: [any _KuzuGraphModel & Codable]]
        )
    ) throws {
        // Execute in a transaction
        _ = try connection.query("BEGIN TRANSACTION")

        do {
            // Execute batch inserts (UNWIND + MERGE for Nodes, CREATE for Edges)
            for (_, models) in operations.inserts {
                guard let firstModel = models.first else { continue }

                // Determine if Node or Edge
                if firstModel is any GraphNodeModel {
                    let nodeModels = models as! [any GraphNodeModel]
                    try executeBatchInsert(nodeModels, firstModel: nodeModels.first!)
                } else if firstModel is any GraphEdgeModel {
                    let edgeModels = models as! [any GraphEdgeModel]
                    try executeBatchEdgeInsert(edgeModels, firstModel: edgeModels.first!)
                }
            }

            // Execute batch deletes (UNWIND + MATCH/DELETE)
            for (_, models) in operations.deletes {
                guard let firstModel = models.first else { continue }

                // Determine if Node or Edge
                if firstModel is any GraphNodeModel {
                    let nodeModels = models as! [any GraphNodeModel]
                    try executeBatchDelete(nodeModels, firstModel: nodeModels.first!)
                } else if firstModel is any GraphEdgeModel {
                    let edgeModels = models as! [any GraphEdgeModel]
                    try executeBatchEdgeDelete(edgeModels, firstModel: edgeModels.first!)
                }
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
        let hasVectorProperties = !graphModelType._metadata.vectorProperties.isEmpty

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
        let iDs: [any Sendable] = try models.map { model in
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
        let kuzuParams = try encoder.encodeParameters(["ids": iDs])
        _ = try connection.execute(statement, kuzuParams)
    }

    private func executeBatchEdgeInsert(
        _ models: [any GraphEdgeModel],
        firstModel: any GraphEdgeModel
    ) throws {
        guard !models.isEmpty else { return }

        // Get type information from the first model
        let modelType = type(of: firstModel)
        let graphModelType = modelType as any _KuzuGraphModel.Type

        let columns = graphModelType._kuzuColumns
        let metadata = graphModelType._metadata
        let edgeName = String(describing: graphModelType)

        // Get EdgeMetadata
        guard let edgeMetadata = metadata.edgeMetadata else {
            throw GraphError.invalidOperation(
                message: "Edge model must have EdgeMetadata (missing @Since/@Target)"
            )
        }

        // Encode all models
        let items: [[String: any Sendable]] = try models.map { model in
            let encodable = model as any Encodable
            return try encoder.encode(encodable)
        }

        // Get since/target property names and node types from metadata
        let sinceProperty = edgeMetadata.sinceProperty
        let targetProperty = edgeMetadata.targetProperty
        let sinceNodeType = edgeMetadata.sinceNodeType
        let targetNodeType = edgeMetadata.targetNodeType
        let sinceNodeKeyPath = edgeMetadata.sinceNodeKeyPath
        let targetNodeKeyPath = edgeMetadata.targetNodeKeyPath

        // Get edge properties (excluding since/target properties)
        let edgeProperties = columns.filter { column in
            column.name != sinceProperty && column.name != targetProperty
        }

        // Build query
        let query: String
        if edgeProperties.isEmpty {
            query = """
                UNWIND $items AS item
                MATCH (src:\(sinceNodeType) {\(sinceNodeKeyPath): item.\(sinceProperty)})
                MATCH (dst:\(targetNodeType) {\(targetNodeKeyPath): item.\(targetProperty)})
                CREATE (src)-[:\(edgeName)]->(dst)
                """
        } else {
            let propAssignments = edgeProperties.map { column -> String in
                let value = column.type == "TIMESTAMP"
                    ? "timestamp(item.\(column.name))"
                    : "item.\(column.name)"
                return "\(column.name): \(value)"
            }.joined(separator: ", ")

            query = """
                UNWIND $items AS item
                MATCH (src:\(sinceNodeType) {\(sinceNodeKeyPath): item.\(sinceProperty)})
                MATCH (dst:\(targetNodeType) {\(targetNodeKeyPath): item.\(targetProperty)})
                CREATE (src)-[:\(edgeName) {\(propAssignments)}]->(dst)
                """
        }

        // Execute query with parameter binding
        if !items.isEmpty {
            let statement = try connection.prepare(query)
            let kuzuParams = try encoder.encodeParameters(["items": items])
            _ = try connection.execute(statement, kuzuParams)
        }
    }

    private func executeBatchEdgeDelete(
        _ models: [any GraphEdgeModel],
        firstModel: any GraphEdgeModel
    ) throws {
        guard !models.isEmpty else { return }

        // Edge deletion is complex as it requires identifying specific edge instances
        // This would need from/to node IDs or edge properties
        throw GraphError.invalidOperation(
            message: "Edge deletion via delete() is not yet supported. Edges are deleted when nodes are deleted."
        )
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

    /// Execute a block with direct connection access (without transaction)
    ///
    /// This method is useful for DDL operations (CREATE_VECTOR_INDEX, etc.)
    /// that cannot be executed within a transaction.
    ///
    /// Example:
    /// ```swift
    /// try context.withConnection { connection in
    ///     _ = try connection.query("CALL CREATE_VECTOR_INDEX(...)")
    /// }
    /// ```
    ///
    /// - Parameter block: A closure that receives a Connection and returns a result
    /// - Returns: The result of the block
    /// - Throws: Any error thrown by the block
    public func withConnection<T>(
        _ block: (Connection) throws -> T
    ) throws -> T {
        try block(connection)
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
    // Note: Edges are inserted using context.insert(edge)
    // The edge model should contain @Since/@Target properties with node IDs

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
        let metadata = type._metadata

        for property in metadata.vectorProperties {
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
