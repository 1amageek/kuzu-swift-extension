import Foundation
import Kuzu

/// SchemaManager manages schema initialization and versioning for graph models.
///
/// SwiftData-inspired schema management for Kuzu graph database.
/// Handles DDL generation, index creation, and provides name-based model access.
///
/// Thread Safety: This class conforms to Sendable because:
/// - All properties are immutable (let)
/// - Schema operations are stateless
///
/// Usage:
/// ```swift
/// let manager = SchemaManager(User.self, Post.self, version: .v1)
/// try manager.ensureSchema(in: database)
/// ```
public final class SchemaManager: Sendable {
    /// The registered model types
    public let models: [any _KuzuGraphModel.Type]

    /// Schema version for migration tracking
    public let version: SchemaVersion

    /// Name-based model lookup
    public let modelsByName: [String: any _KuzuGraphModel.Type]

    /// Create a schema manager with specified model types and version
    /// - Parameters:
    ///   - models: The model types to include in this schema
    ///   - version: The schema version (default: .v1)
    public init(_ models: (any _KuzuGraphModel.Type)..., version: SchemaVersion = .v1) {
        self.models = models
        self.version = version
        self.modelsByName = Dictionary(uniqueKeysWithValues: models.map { ($0.name, $0) })
    }

    /// Create a schema manager from an array of model types
    /// - Parameters:
    ///   - models: Array of model types
    ///   - version: The schema version (default: .v1)
    public init(_ models: [any _KuzuGraphModel.Type], version: SchemaVersion = .v1) {
        self.models = models
        self.version = version
        self.modelsByName = Dictionary(uniqueKeysWithValues: models.map { ($0.name, $0) })
    }

    // MARK: - Schema Initialization

    /// Ensure schema is created in the database (idempotent)
    /// - Parameter database: Database instance to initialize
    /// - Throws: KuzuError if schema creation fails
    public func ensureSchema(in database: Database) throws {
        let connection = try Connection(database)

        // Fetch existing tables and indexes once
        let existingTables = try fetchExistingTables(connection)
        let existingIndexes = try fetchExistingIndexes(connection)

        // Create tables and indexes for each model
        for model in models {
            let tableName = model.name

            // Only create table if it doesn't exist
            if !existingTables.contains(tableName) {
                try createTable(for: model, connection: connection)
            }

            // Create indexes (will skip if already exist)
            try createIndexes(for: model, existingIndexes: existingIndexes, connection: connection)
        }
    }

    // MARK: - Existence Checks

    /// Fetch existing table names from the database
    /// - Parameter connection: Database connection
    /// - Returns: Set of existing table names
    private func fetchExistingTables(_ connection: Connection) throws -> Set<String> {
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
            // If SHOW TABLES fails, return empty set (new database)
            return []
        }

        return tables
    }

    /// Fetch existing indexes from the database
    /// - Parameter connection: Database connection
    /// - Returns: Set of existing index keys (format: "TableName.indexName")
    private func fetchExistingIndexes(_ connection: Connection) throws -> Set<String> {
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
            // If SHOW_INDEXES fails, return empty set (no indexes yet)
            return []
        }

        return indexes
    }

    // MARK: - Table Creation

    /// Create table for a model using DDL as-is
    /// - Parameters:
    ///   - model: The model type
    ///   - connection: Database connection
    /// - Throws: KuzuError if table creation fails
    /// - Note: This method should only be called after checking that the table doesn't exist
    private func createTable(
        for model: any _KuzuGraphModel.Type,
        connection: Connection
    ) throws {
        let ddl = model._kuzuDDL

        do {
            _ = try connection.query(ddl)
        } catch {
            // Safety check: If table already exists, don't fail
            // This can happen if SHOW TABLES didn't detect an existing table
            let errorMessage = String(describing: error).lowercased()
            if errorMessage.contains("already exists") || errorMessage.contains("catalog") {
                // Table exists, this is fine
                return
            }

            throw KuzuError.databaseInitializationFailed(
                "Table creation failed for '\(model.name)': \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Index Creation

    /// Create indexes for a model (checks existence first)
    /// - Parameters:
    ///   - model: The model type
    ///   - existingIndexes: Set of existing index keys
    ///   - connection: Database connection
    /// - Throws: KuzuError if index creation fails
    private func createIndexes(
        for model: any _KuzuGraphModel.Type,
        existingIndexes: Set<String>,
        connection: Connection
    ) throws {
        let tableName = model.name
        let metadata = model._metadata

        // Create vector indexes
        for property in metadata.vectorProperties {
            let indexName = property.indexName(for: tableName)
            let indexKey = "\(tableName).\(indexName)"

            // Skip if index already exists
            if existingIndexes.contains(indexKey) {
                continue
            }

            do {
                try VectorIndexManager.createVectorIndex(
                    table: tableName,
                    column: property.propertyName,
                    indexName: indexName,
                    metric: property.metric,
                    connection: connection
                )
            } catch {
                throw KuzuError.indexCreationFailed(
                    table: tableName,
                    index: indexName,
                    reason: "Vector index creation failed: \(error.localizedDescription)"
                )
            }
        }

        // Create Full-Text Search indexes
        for property in metadata.fullTextSearchProperties {
            let indexName = property.indexName(for: tableName)
            let indexKey = "\(tableName).\(indexName)"

            // Skip if index already exists
            if existingIndexes.contains(indexKey) {
                continue
            }

            do {
                try FullTextSearchIndexManager.createFullTextSearchIndex(
                    table: tableName,
                    column: property.propertyName,
                    indexName: indexName,
                    stemmer: property.stemmer,
                    connection: connection
                )
            } catch {
                throw KuzuError.indexCreationFailed(
                    table: tableName,
                    index: indexName,
                    reason: "Full-Text Search index creation failed: \(error.localizedDescription)"
                )
            }
        }
    }
}

// MARK: - Schema Version

/// Schema version for migration tracking
public struct SchemaVersion: Sendable, Hashable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int = 0, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Version 1.0.0 (default)
    public static let v1 = SchemaVersion(major: 1, minor: 0, patch: 0)

    public static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

extension SchemaVersion: CustomStringConvertible {
    public var description: String {
        "\(major).\(minor).\(patch)"
    }
}
