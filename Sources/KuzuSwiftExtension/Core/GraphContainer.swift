import Foundation
import Kuzu

/// GraphContainer manages the database and schema.
///
/// SwiftData ModelContainer equivalent for Kuzu graph database.
/// Automatically creates schemas and indexes for registered models on initialization.
///
/// Thread Safety: This struct conforms to Sendable because:
/// - All properties are immutable (let)
/// - Database is internally thread-safe (verified via Kuzu documentation)
///
/// The underlying Kuzu C++ library guarantees thread-safe access to Database instances.
///
/// Usage (SwiftData-style):
/// ```swift
/// let container = try GraphContainer(
///     for: User.self, Post.self,
///     configuration: GraphConfiguration(databasePath: ":memory:")
/// )
/// ```
public struct GraphContainer: Sendable {
    /// The registered model types (equivalent to ModelContainer.schema)
    public let models: [any _KuzuGraphModel.Type]

    /// The configuration for this container
    public let configuration: GraphConfiguration

    internal let database: Database

    /// Create a container for specified model types (variadic parameters)
    /// Equivalent to: ModelContainer(for: User.self, Post.self)
    /// - Parameters:
    ///   - forTypes: The model types to manage (variadic)
    ///   - configuration: Database configuration
    public init(
        for forTypes: (any _KuzuGraphModel.Type)...,
        configuration: GraphConfiguration = GraphConfiguration()
    ) throws {
        self.models = forTypes
        self.configuration = configuration
        self.database = try Database(configuration.databasePath)

        // SwiftData pattern: Automatically create schemas for registered models
        if !forTypes.isEmpty {
            try Self.createSchemas(database: database, models: forTypes)
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
    ) throws {
        self.models = models
        self.configuration = configuration
        self.database = try Database(configuration.databasePath)

        // SwiftData pattern: Automatically create schemas for registered models
        if !models.isEmpty {
            try Self.createSchemas(database: database, models: models)
        }
    }

    /// Create a container without models (for manual schema management)
    /// - Parameter configuration: Database configuration
    internal init(configuration: GraphConfiguration) throws {
        self.models = []
        self.configuration = configuration
        self.database = try Database(configuration.databasePath)
    }

    /// Main context bound to the main actor (SwiftData ModelContainer.mainContext equivalent)
    ///
    /// This property provides a convenient way to access a GraphContext that's automatically
    /// bound to the main actor, making it safe for use in SwiftUI views and other UI code.
    ///
    /// Usage:
    /// ```swift
    /// let container = try GraphContainer(for: User.self)
    /// let context = container.mainContext  // @MainActor bound
    /// ```
    @MainActor
    public var mainContext: GraphContext {
        GraphContext(self)
    }

    // MARK: - Schema Management (SwiftData Pattern)

    /// Automatically create schemas for registered models
    /// - Parameters:
    ///   - database: Database instance
    ///   - models: Models to create schemas for
    private static func createSchemas(
        database: Database,
        models: [any _KuzuGraphModel.Type]
    ) throws {
        let connection = try Connection(database)

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
