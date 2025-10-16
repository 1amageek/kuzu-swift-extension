import Foundation
import Kuzu

/// GraphContainer manages the database and schema.
///
/// SwiftData ModelContainer equivalent for Kuzu graph database.
/// Automatically creates schemas and indexes for registered models on initialization.
///
/// Thread Safety: This class conforms to @unchecked Sendable because:
/// - Database is internally thread-safe (verified via Kuzu documentation)
/// - All properties are immutable after initialization
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
public final class GraphContainer: @unchecked Sendable {
    /// The registered model types (equivalent to ModelContainer.schema)
    public let models: [any _KuzuGraphModel.Type]

    /// The configuration for this container
    public let configuration: GraphConfiguration

    /// The current status of vector indexes loading.
    ///
    /// This property queries the database for the current loading status.
    /// SwiftUI views can observe this property to show loading indicators or error states.
    ///
    /// - Returns: The current `VectorIndexesStatus` (`.loading`, `.ready`, or `.failed(Error)`)
    public var vectorIndexesStatus: VectorIndexesStatus {
        database.vectorIndexesStatus
    }

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

    // MARK: - Vector Index Loading

    /// Registers a callback to be invoked when vector indexes finish loading.
    ///
    /// The callback is invoked on a background thread when loading completes.
    /// If indexes are already loaded when this method is called, the callback
    /// will be invoked immediately on the calling thread.
    ///
    /// - Parameter completion: A closure that receives a `Result<Void, Error>`.
    ///   - `.success` if all indexes loaded successfully
    ///   - `.failure` if loading failed
    ///
    /// - Note: Only one callback can be registered at a time. Calling this method
    ///         again will replace the previous callback.
    ///
    /// Example usage in SwiftUI:
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     let container = try! GraphContainer(for: Photo.self)
    ///     @State private var isIndexReady = false
    ///
    ///     var body: some Scene {
    ///         WindowGroup {
    ///             ContentView()
    ///                 .task {
    ///                     container.onVectorIndexesLoaded { result in
    ///                         Task { @MainActor in
    ///                             isIndexReady = result.map { true } ?? false
    ///                         }
    ///                     }
    ///                 }
    ///         }
    ///         .graphContainer(container)
    ///     }
    /// }
    /// ```
    public func onVectorIndexesLoaded(_ completion: @escaping (Result<Void, Error>) -> Void) {
        database.onVectorIndexesLoaded(completion)
    }
}
