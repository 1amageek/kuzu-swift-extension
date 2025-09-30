import Foundation
import Kuzu

/// GraphContainer manages the database and connection pool.
///
/// SwiftData ModelContainer equivalent for Kuzu graph database.
/// Automatically creates schemas and indexes for registered models on initialization.
///
/// Thread Safety: This struct conforms to Sendable because:
/// - All properties are immutable (let)
/// - Database and Connection are internally thread-safe (verified via Kuzu documentation)
/// - ConnectionPool is an actor providing synchronized access to connections
///
/// The underlying Kuzu C++ library guarantees thread-safe access to Database instances,
/// and each Connection is independent and can be safely used from different threads.
///
/// Usage (SwiftData-style):
/// ```swift
/// let container = try await GraphContainer(
///     for: [User.self, Post.self],
///     configuration: GraphConfiguration(databasePath: ":memory:")
/// )
/// ```
public struct GraphContainer: Sendable {
    /// The registered model types (equivalent to ModelContainer.schema)
    public let models: [any _KuzuGraphModel.Type]

    /// The configuration for this container
    public let configuration: GraphConfiguration

    private let database: Database
    private let connectionPool: ConnectionPool
    private let isInitialized: Bool

    /// Create a container for specified model types (variadic parameters)
    /// Equivalent to: ModelContainer(for: User.self, Post.self)
    /// - Parameters:
    ///   - forTypes: The model types to manage (variadic)
    ///   - configuration: Database configuration
    public init(
        for forTypes: (any _KuzuGraphModel.Type)...,
        configuration: GraphConfiguration = GraphConfiguration()
    ) async throws {
        self.models = forTypes
        self.configuration = configuration

        self.database = try Database(configuration.databasePath)

        let connectionConfig = ConnectionConfiguration(
            maxNumThreadsPerQuery: configuration.options.maxNumThreadsPerQuery,
            queryTimeout: configuration.options.queryTimeout
        )

        self.connectionPool = try await ConnectionPool(
            database: database,
            maxConnections: configuration.options.maxConnections,
            minConnections: configuration.options.minConnections,
            timeout: configuration.options.connectionTimeout,
            connectionConfig: connectionConfig
        )

        self.isInitialized = true

        // Load extensions after all properties are initialized
        try await Self.loadExtensions(configuration: configuration, connectionPool: connectionPool)

        // SwiftData pattern: Automatically create schemas for registered models
        if !forTypes.isEmpty {
            try await Self.ensureSchemas(
                models: Array(forTypes),
                connectionPool: connectionPool
            )
        }
    }

    /// Create a container for specified model types (array version)
    /// Equivalent to: ModelContainer(for: givenSchema)
    /// - Parameters:
    ///   - models: The model types to manage (array)
    ///   - configuration: Database configuration
    public init(
        for models: [any _KuzuGraphModel.Type],
        configuration: GraphConfiguration = GraphConfiguration()
    ) async throws {
        self.models = models
        self.configuration = configuration

        self.database = try Database(configuration.databasePath)

        let connectionConfig = ConnectionConfiguration(
            maxNumThreadsPerQuery: configuration.options.maxNumThreadsPerQuery,
            queryTimeout: configuration.options.queryTimeout
        )

        self.connectionPool = try await ConnectionPool(
            database: database,
            maxConnections: configuration.options.maxConnections,
            minConnections: configuration.options.minConnections,
            timeout: configuration.options.connectionTimeout,
            connectionConfig: connectionConfig
        )

        self.isInitialized = true

        // Load extensions after all properties are initialized
        try await Self.loadExtensions(configuration: configuration, connectionPool: connectionPool)

        // SwiftData pattern: Automatically create schemas for registered models
        if !models.isEmpty {
            try await Self.ensureSchemas(
                models: models,
                connectionPool: connectionPool
            )
        }
    }

    /// Create a container without models (for manual schema management)
    /// - Parameter configuration: Database configuration
    internal init(configuration: GraphConfiguration) async throws {
        self.models = []
        self.configuration = configuration

        self.database = try Database(configuration.databasePath)

        let connectionConfig = ConnectionConfiguration(
            maxNumThreadsPerQuery: configuration.options.maxNumThreadsPerQuery,
            queryTimeout: configuration.options.queryTimeout
        )

        self.connectionPool = try await ConnectionPool(
            database: database,
            maxConnections: configuration.options.maxConnections,
            minConnections: configuration.options.minConnections,
            timeout: configuration.options.connectionTimeout,
            connectionConfig: connectionConfig
        )

        self.isInitialized = true

        // Load extensions
        try await Self.loadExtensions(configuration: configuration, connectionPool: connectionPool)
    }
    
    private static func loadExtensions(configuration: GraphConfiguration, connectionPool: ConnectionPool) async throws {
        guard !configuration.options.extensions.isEmpty else { return }

        let connection = try await connectionPool.checkout()
        defer {
            Task {
                await connectionPool.checkin(connection)
            }
        }

        var loadedExtensions: [KuzuExtension] = []
        var failedExtensions: [(KuzuExtension, String)] = []

        for ext in configuration.options.extensions {
            do {
                // Vector extension is statically linked in kuzu-swift
                if ext == .vector {
                    // Check if vector functions are available
                    do {
                        // Check loaded extensions
                        _ = try connection.query("CALL SHOW_LOADED_EXTENSIONS()")

                        // Vector extension is built into kuzu-swift via static linking
                        // We can also verify with array functions
                        _ = try connection.query("RETURN CAST([1.0, 2.0, 3.0] AS FLOAT[3]) AS test")

                        loadedExtensions.append(ext)
                        print("Vector extension enabled (statically linked)")
                    } catch {
                        // Try to explicitly load if not available
                        do {
                            _ = try connection.query("LOAD EXTENSION vector")
                            loadedExtensions.append(ext)
                            print("Vector extension loaded dynamically")
                        } catch {
                            print("Vector extension not available: \(error)")
                            failedExtensions.append((ext, error.localizedDescription))
                        }
                    }
                    continue
                }

                // For FTS, also check if statically linked
                if ext == .fts {
                    // FTS might also be statically linked
                    loadedExtensions.append(ext)
                    continue
                }

                // For other extensions, try normal loading
                #if os(iOS) || os(tvOS) || os(watchOS)
                // On iOS, dynamic loading is not supported
                // Extensions must be statically linked
                if ext != .json {
                    failedExtensions.append((ext, "Dynamic loading not supported on iOS"))
                    continue
                }
                #else
                // On other platforms, try INSTALL first, then LOAD
                do {
                    _ = try connection.query("INSTALL \(ext.extensionName)")
                } catch {
                    // INSTALL might fail if extension is built-in or not needed
                }
                _ = try connection.query("LOAD EXTENSION \(ext.extensionName)")
                #endif

                loadedExtensions.append(ext)
            } catch {
                // Log the failure but don't throw immediately
                let reason = error.localizedDescription
                failedExtensions.append((ext, reason))

                #if DEBUG
                print("Warning: Failed to load extension '\(ext.extensionName)': \(reason)")
                #endif
            }
        }

        // Handle extension loading results
        if !failedExtensions.isEmpty {
            // Check if only vector/fts failed (these might work anyway if statically linked)
            let criticalFailures = failedExtensions.filter { ext, _ in
                // Only non-vector/fts extensions are critical
                ext != .vector && ext != .fts
            }

            if !criticalFailures.isEmpty {
                // Throw only for critical extension failures
                throw GraphError.extensionLoadFailed(
                    extension: criticalFailures.map { $0.0.rawValue }.joined(separator: ", "),
                    reason: "Failed to load required extensions"
                )
            }

            // For vector/fts, just warn
            if failedExtensions.contains(where: { ext, _ in ext == .vector || ext == .fts }) {
                print("Note: Vector/FTS extensions could not be explicitly loaded, but basic operations may still work.")
            }
        }

        // Log successful loads
        if !loadedExtensions.isEmpty {
            #if DEBUG
            print("Successfully loaded extensions: \(loadedExtensions.map { $0.rawValue }.joined(separator: ", "))")
            #endif
        }
    }
    
    public func withConnection<T>(_ block: @Sendable (Connection) throws -> T) async throws -> T {
        let connection = try await connectionPool.checkout()
        
        return try await withTaskCancellationHandler {
            do {
                let result = try block(connection)
                await connectionPool.checkin(connection)
                return result
            } catch {
                await connectionPool.checkin(connection)
                throw error
            }
        } onCancel: {
            Task {
                await connectionPool.checkin(connection)
            }
        }
    }
    
    // Internal transaction support - use GraphContext.withTransaction for public API
    internal func withTransaction<T>(_ block: @Sendable (Connection) throws -> T) async throws -> T {
        let connection = try await connectionPool.checkout()
        
        do {
            _ = try connection.query("BEGIN TRANSACTION")
            
            do {
                let result = try block(connection)
                _ = try connection.query("COMMIT")
                await connectionPool.checkin(connection)
                return result
            } catch {
                do {
                    _ = try connection.query("ROLLBACK")
                } catch let rollbackError {
                    // Log rollback error but throw original error
                    print("Warning: Failed to rollback transaction: \(rollbackError)")
                }
                await connectionPool.checkin(connection)

                // Provide detailed error information for debugging
                let errorDescription = "\(error)"
                throw GraphError.transactionFailed(reason: errorDescription)
            }
        } catch {
            await connectionPool.checkin(connection)
            throw error
        }
    }
    
    public func close() async {
        await connectionPool.drain()
    }

    // MARK: - Schema Management (SwiftData Pattern)

    /// Automatically create schemas for registered models
    /// - Parameters:
    ///   - models: Models to create schemas for
    ///   - connectionPool: Connection pool to use
    private static func ensureSchemas(
        models: [any _KuzuGraphModel.Type],
        connectionPool: ConnectionPool
    ) async throws {
        let connection = try await connectionPool.checkout()
        defer {
            Task {
                await connectionPool.checkin(connection)
            }
        }

        // Fetch existing tables and indexes once
        let existingTables = try fetchExistingTables(connection)
        let existingIndexes = try fetchExistingIndexes(connection)

        // Create schema and indexes for each model
        for model in models {
            try createSchemaForModel(
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
            // This allows graceful handling of new databases
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
            // This allows graceful handling when no indexes exist
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
