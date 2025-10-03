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
        // Array of node models to insert
        var inserts: [any GraphNodeModel] = []
        // Array of node models to delete
        var deletes: [any GraphNodeModel] = []
        // Array of edge connections to create
        var connects: [ConnectOperation] = []
        // Array of edge connections to remove
        var disconnects: [DisconnectOperation] = []
    }

    private struct ConnectOperation {
        let edge: any GraphEdgeModel & Codable
        let fromID: String
        let toID: String
        let edgeType: any GraphEdgeModel.Type
    }

    private struct DisconnectOperation {
        let edge: any GraphEdgeModel & Codable
        let fromID: String
        let toID: String
        let edgeType: any GraphEdgeModel.Type
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
            !ops.inserts.isEmpty || !ops.deletes.isEmpty ||
            !ops.connects.isEmpty || !ops.disconnects.isEmpty
        }
    }

    /// The array of inserted node models that the context is yet to persist
    ///
    /// SwiftData-compatible API.
    public var insertedModelsArray: [any GraphNodeModel] {
        pendingOperations.withLock { ops in
            ops.inserts
        }
    }

    /// The array of registered node models that the context will remove from persistent storage during the next save
    ///
    /// SwiftData-compatible API.
    public var deletedModelsArray: [any GraphNodeModel] {
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

    /// Creates a connection (edge) between two existing nodes
    ///
    /// This method accumulates the edge connection in memory and does not immediately
    /// execute a database operation. Call `save()` to commit all pending changes.
    ///
    /// Example:
    /// ```swift
    /// let author = Author(role: "primary", since: Date())
    /// context.connect(author, from: user.id, to: post.id)
    /// try await context.save()
    /// ```
    ///
    /// - Parameters:
    ///   - edge: The edge model containing relationship properties
    ///   - fromID: The ID of the source node (must exist in database)
    ///   - toID: The ID of the target node (must exist in database)
    public func connect<E: GraphEdgeModel>(_ edge: E, from fromID: String, to toID: String) {
        let operation = ConnectOperation(
            edge: edge,
            fromID: fromID,
            toID: toID,
            edgeType: E.self
        )
        pendingOperations.withLock { ops in
            ops.connects.append(operation)
        }
    }

    /// Creates a connection (edge) between two existing node models
    ///
    /// This overload extracts IDs from node models automatically.
    ///
    /// Example:
    /// ```swift
    /// let user = User(id: "user-123", name: "Alice")
    /// let post = Post(id: "post-456", title: "Hello")
    /// context.insert(user)
    /// context.insert(post)
    ///
    /// let author = Author(role: "primary", since: Date())
    /// context.connect(author, from: user, to: post)
    /// try await context.save()
    /// ```
    ///
    /// - Parameters:
    ///   - edge: The edge model containing relationship properties
    ///   - from: The source node model
    ///   - to: The target node model
    public func connect<E: GraphEdgeModel, F: GraphNodeModel, T: GraphNodeModel>(
        _ edge: E,
        from: F,
        to: T
    ) throws {
        let fromType = type(of: from)
        let toType = type(of: to)
        let fromGraphModelType = fromType as any _KuzuGraphModel.Type
        let toGraphModelType = toType as any _KuzuGraphModel.Type

        // Get ID column (first column should be ID)
        guard let fromIDColumn = fromGraphModelType._kuzuColumns.first else {
            throw KuzuError.invalidConfiguration(message: "Source node must have at least one column (ID)")
        }
        guard let toIDColumn = toGraphModelType._kuzuColumns.first else {
            throw KuzuError.invalidConfiguration(message: "Target node must have at least one column (ID)")
        }

        // Encode nodes to get their IDs
        let encodable = from as any Encodable
        let fromProperties = try encoder.encode(encodable)
        guard let fromID = fromProperties[fromIDColumn.columnName] as? String else {
            throw KuzuError.invalidConfiguration(message: "Could not extract ID from source node")
        }

        let toEncodable = to as any Encodable
        let toProperties = try encoder.encode(toEncodable)
        guard let toID = toProperties[toIDColumn.columnName] as? String else {
            throw KuzuError.invalidConfiguration(message: "Could not extract ID from target node")
        }

        connect(edge, from: fromID, to: toID)
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

    /// Removes a connection (edge) between two nodes
    ///
    /// This method accumulates the disconnection in memory and does not immediately
    /// execute a database operation. Call `save()` to commit all pending changes.
    ///
    /// Example:
    /// ```swift
    /// let author = Author(role: "primary", since: Date())
    /// context.disconnect(author, from: user.id, to: post.id)
    /// try await context.save()
    /// ```
    ///
    /// - Parameters:
    ///   - edge: The edge model to identify which connection to remove
    ///   - fromID: The ID of the source node
    ///   - toID: The ID of the target node
    public func disconnect<E: GraphEdgeModel>(_ edge: E, from fromID: String, to toID: String) {
        let operation = DisconnectOperation(
            edge: edge,
            fromID: fromID,
            toID: toID,
            edgeType: E.self
        )
        pendingOperations.withLock { ops in
            ops.disconnects.append(operation)
        }
    }

    /// Commits all pending inserts, deletes, connects, and disconnects to the database in a single transaction
    ///
    /// This method executes all accumulated operations using
    /// batch optimization (UNWIND + MERGE/DELETE/CREATE) for maximum performance.
    /// All operations are executed within a single transaction, providing ACID guarantees.
    ///
    /// Posts `willSave` notification before saving and `didSave` notification after successful save.
    ///
    /// - Throws: KuzuError if the transaction fails
    public func save() throws {
        let operations = pendingOperations.withLock { ops in
            let result = (
                inserts: ops.inserts,
                deletes: ops.deletes,
                connects: ops.connects,
                disconnects: ops.disconnects
            )
            ops.inserts.removeAll()
            ops.deletes.removeAll()
            ops.connects.removeAll()
            ops.disconnects.removeAll()
            return result
        }

        guard !operations.inserts.isEmpty || !operations.deletes.isEmpty ||
              !operations.connects.isEmpty || !operations.disconnects.isEmpty else {
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
        try executeBatchOperations(
            inserts: insertsByType,
            deletes: deletesByType,
            connects: operations.connects,
            disconnects: operations.disconnects
        )

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
                if let idValue = properties[idColumn.columnName] {
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
            ops.connects.removeAll()
            ops.disconnects.removeAll()
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
        inserts: [String: [any GraphNodeModel]],
        deletes: [String: [any GraphNodeModel]],
        connects: [ConnectOperation],
        disconnects: [DisconnectOperation]
    ) throws {
        // Execute in a transaction
        _ = try connection.query("BEGIN TRANSACTION")

        do {
            // Execute batch inserts (UNWIND + MERGE for Nodes)
            for (_, models) in inserts {
                guard let firstModel = models.first else { continue }
                try executeBatchInsert(models, firstModel: firstModel)
            }

            // Execute batch deletes (UNWIND + MATCH/DELETE for Nodes)
            for (_, models) in deletes {
                guard let firstModel = models.first else { continue }
                try executeBatchDelete(models, firstModel: firstModel)
            }

            // Execute batch connects (CREATE edges)
            if !connects.isEmpty {
                try executeConnectOperations(connects)
            }

            // Execute batch disconnects (DELETE edges)
            if !disconnects.isEmpty {
                try executeDisconnectOperations(disconnects)
            }

            _ = try connection.query("COMMIT")
        } catch {
            _ = try? connection.query("ROLLBACK")
            throw KuzuError.transactionFailed(reason: "\(error)")
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

        // ⚠️ WORKAROUND: Vector properties require sequential execution to avoid HNSW index crash
        // Issue: Kuzu's HNSW index has race condition in CSR array access during batch DELETE+CREATE
        // When UNWIND processes multiple items, parallel HNSW index updates cause array out of bounds
        // See: https://github.com/kuzudb/kuzu/issues/5184
        if hasVectorProperties {
            // Execute DELETE + CREATE sequentially for each item
            // Issue 1: Kuzu's HNSW index has race condition in CSR array access during batch operations
            // Issue 2: Vector properties with indexes cannot be updated via SET - must DELETE + INSERT
            // See: https://github.com/kuzudb/kuzu/issues/5184
            for item in items {
                let allColumns = [idColumn] + nonIdColumns
                let singleQuery: String

                // Build property list for CREATE
                let propertyAssignments = allColumns.map { column -> String in
                    let value = column.type == "TIMESTAMP"
                        ? "timestamp($\(column.propertyName))"
                        : "$\(column.propertyName)"
                    return "\(column.columnName): \(value)"
                }.joined(separator: ", ")

                singleQuery = """
                    OPTIONAL MATCH (n:\(modelName) {\(idColumn.columnName): $\(idColumn.propertyName)})
                    DELETE n
                    CREATE (m:\(modelName) {\(propertyAssignments)})
                    """

                let statement = try connection.prepare(singleQuery)
                let kuzuParams = try encoder.encodeParameters(item)
                _ = try connection.execute(statement, kuzuParams)
            }
            return
        }

        // Normal path (no vector indexes): Use UNWIND + MERGE for batch efficiency
        let query: String
        if nonIdColumns.isEmpty {
            query = """
                UNWIND $items AS item
                MERGE (n:\(modelName) {\(idColumn.columnName): item.\(idColumn.propertyName)})
                """
        } else {
            let createAssignments = nonIdColumns.map { column -> String in
                let value = column.type == "TIMESTAMP"
                    ? "timestamp(item.\(column.propertyName))"
                    : "item.\(column.propertyName)"
                return "n.\(column.columnName) = \(value)"
            }.joined(separator: ", ")

            let updateAssignments = nonIdColumns.map { column -> String in
                let value = column.type == "TIMESTAMP"
                    ? "timestamp(item.\(column.propertyName))"
                    : "item.\(column.propertyName)"
                return "n.\(column.columnName) = \(value)"
            }.joined(separator: ", ")

            query = """
                UNWIND $items AS item
                MERGE (n:\(modelName) {\(idColumn.columnName): item.\(idColumn.propertyName)})
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
            guard let id = properties[idColumn.columnName] else {
                throw GraphError.invalidOperation(message: "Model missing ID property")
            }
            return id
        }

        // Build UNWIND + MATCH/DELETE query
        let query = """
            UNWIND $ids AS id
            MATCH (n:\(modelName) {\(idColumn.columnName): id})
            DELETE n
            """

        // Execute query with parameter binding
        let statement = try connection.prepare(query)
        let kuzuParams = try encoder.encodeParameters(["ids": iDs])
        _ = try connection.execute(statement, kuzuParams)
    }

    private func executeConnectOperations(_ operations: [ConnectOperation]) throws {
        guard !operations.isEmpty else { return }

        // Group by edge type for batch execution
        let operationsByType = Dictionary(grouping: operations) {
            String(describing: $0.edgeType)
        }

        for (_, ops) in operationsByType {
            guard let firstOp = ops.first else { continue }

            let edgeType = firstOp.edgeType
            let graphModelType = edgeType as any _KuzuGraphModel.Type
            let columns = graphModelType._kuzuColumns
            let edgeName = String(describing: edgeType)

            // Get from/to types from the edge model
            let fromType = edgeType._fromType
            let toType = edgeType._toType
            let fromNodeName = String(describing: fromType).replacingOccurrences(of: ".Type", with: "")
            let toNodeName = String(describing: toType).replacingOccurrences(of: ".Type", with: "")

            // Encode all edges
            let items: [[String: any Sendable]] = try ops.map { op in
                let encodable = op.edge as any Encodable
                var properties = try encoder.encode(encodable)
                // Add fromID and toID for MATCH
                properties["_fromID"] = op.fromID
                properties["_toID"] = op.toID
                return properties
            }

            // Build query
            let query: String
            if columns.isEmpty {
                query = """
                    UNWIND $items AS item
                    MATCH (src:\(fromNodeName) {id: item._fromID})
                    MATCH (dst:\(toNodeName) {id: item._toID})
                    CREATE (src)-[:\(edgeName)]->(dst)
                    """
            } else {
                let propAssignments = columns.map { column -> String in
                    let value = column.type == "TIMESTAMP"
                        ? "timestamp(item.\(column.propertyName))"
                        : "item.\(column.propertyName)"
                    return "\(column.columnName): \(value)"
                }.joined(separator: ", ")

                query = """
                    UNWIND $items AS item
                    MATCH (src:\(fromNodeName) {id: item._fromID})
                    MATCH (dst:\(toNodeName) {id: item._toID})
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
    }

    private func executeDisconnectOperations(_ operations: [DisconnectOperation]) throws {
        guard !operations.isEmpty else { return }

        // Group by edge type for batch execution
        let operationsByType = Dictionary(grouping: operations) {
            String(describing: $0.edgeType)
        }

        for (_, ops) in operationsByType {
            guard let firstOp = ops.first else { continue }

            let edgeType = firstOp.edgeType
            let edgeName = String(describing: edgeType)

            // Get from/to types
            let fromType = edgeType._fromType
            let toType = edgeType._toType
            let fromNodeName = String(describing: fromType).replacingOccurrences(of: ".Type", with: "")
            let toNodeName = String(describing: toType).replacingOccurrences(of: ".Type", with: "")

            // Build items with fromID and toID
            let items: [[String: any Sendable]] = ops.map { op in
                ["_fromID": op.fromID, "_toID": op.toID]
            }

            // Build query
            let query = """
                UNWIND $items AS item
                MATCH (src:\(fromNodeName) {id: item._fromID})-[r:\(edgeName)]->(dst:\(toNodeName) {id: item._toID})
                DELETE r
                """

            // Execute query with parameter binding
            if !items.isEmpty {
                let statement = try connection.prepare(query)
                let kuzuParams = try encoder.encodeParameters(["items": items])
                _ = try connection.execute(statement, kuzuParams)
            }
        }
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

}
