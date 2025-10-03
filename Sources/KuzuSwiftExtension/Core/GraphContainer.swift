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
        do {
            // Create SystemConfig with explicit iOS-optimized settings
            // Based on kuzu-swift-demo approach
            let systemConfig = SystemConfig(
                bufferPoolSize: UInt64(configuration.options.bufferPoolSize),
                maxNumThreads: UInt64(configuration.options.maxNumThreadsPerQuery ?? 1),
                enableCompression: true,
                readOnly: false,
                autoCheckpoint: true,
                checkpointThreshold: 1024 * 1024
            )
            self.database = try Database(configuration.databasePath, systemConfig)
        } catch {
            throw error
        }

        // SwiftData pattern: Automatically create schemas for registered models
        if !forTypes.isEmpty {
            let schemaManager = SchemaManager(forTypes)
            try schemaManager.ensureSchema(in: database)
        }
    }


    /// Create a container without models (for manual schema management)
    /// - Parameter configuration: Database configuration
    internal init(configuration: GraphConfiguration) throws {
        self.models = []
        self.configuration = configuration

        do {
            // Create SystemConfig with explicit iOS-optimized settings
            // Based on kuzu-swift-demo approach
            let systemConfig = SystemConfig(
                bufferPoolSize: UInt64(configuration.options.bufferPoolSize),
                maxNumThreads: UInt64(configuration.options.maxNumThreadsPerQuery ?? 1),
                enableCompression: true,
                readOnly: false,
                autoCheckpoint: true,
                checkpointThreshold: 1024 * 1024
            )

            self.database = try Database(configuration.databasePath, systemConfig)
        } catch {
            throw error
        }
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
}
