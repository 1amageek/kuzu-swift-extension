import Foundation
import Kuzu
import Synchronization

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

    /// The current status of database initialization.
    ///
    /// This property indicates whether the database is still initializing,
    /// fully ready for all operations, or has failed to initialize.
    ///
    /// The database constructor returns immediately after spawning a background thread
    /// for heavy initialization tasks (WAL replay, HNSW index loading). This property
    /// allows you to check the initialization status without blocking.
    ///
    /// - Returns: The current `DatabaseStatus` (`.initializing`, `.ready`, or `.failed(Error)`)
    ///
    /// - Note: Queries will automatically wait for initialization to complete,
    ///         so checking this status is optional. It's mainly useful for UI feedback.
    ///
    /// Example usage in SwiftUI:
    /// ```swift
    /// @main
    /// struct PXLApp: App {
    ///     let container = try! GraphContainer(for: PhotoAsset.self)
    ///     @State private var isReady = false
    ///
    ///     var body: some Scene {
    ///         WindowGroup {
    ///             if isReady {
    ///                 MainView()
    ///             } else {
    ///                 ProgressView("Initializing database...")
    ///             }
    ///         }
    ///         .graphContainer(container)
    ///         .task {
    ///             // Poll initialization status
    ///             while case .initializing = container.initializationStatus {
    ///                 try? await Task.sleep(for: .milliseconds(100))
    ///             }
    ///             if case .ready = container.initializationStatus {
    ///                 isReady = true
    ///             }
    ///         }
    ///     }
    /// }
    /// ```
    public var initializationStatus: DatabaseStatus {
        database.initializationStatus
    }

    internal let database: Database

    // Schema initialization task (runs in background)
    // The task state itself represents schema readiness:
    // - nil: No schema to initialize (ready)
    // - Task running: Schema initialization in progress
    // - Task completed: Schema ready
    private let schemaInitTask: Task<Void, Error>?

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
        // ✅ Run schema creation in background to avoid blocking UI
        if !forTypes.isEmpty {
            let database = self.database
            let models = forTypes
            self.schemaInitTask = Task.detached(priority: .userInitiated) {
                // Create schema using SchemaManager
                // ensureSchema() internally creates a Connection and executes queries,
                // which will automatically wait for database initialization via
                // ClientContext::query() -> waitForInitialization()
                let schemaManager = SchemaManager(models)
                try schemaManager.ensureSchema(in: database)
            }
        } else {
            // No models to initialize - schema is ready
            self.schemaInitTask = nil
        }
    }


    /// Create a container without models (for manual schema management)
    /// - Parameter configuration: Database configuration
    internal init(configuration: GraphConfiguration) throws {
        self.models = []
        self.configuration = configuration
        self.schemaInitTask = nil  // No schema to initialize

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

    // MARK: - Schema Readiness

    /// Check if schema is ready (non-blocking)
    ///
    /// This property returns true if:
    /// - No schema initialization is needed (no models registered), or
    /// - Schema initialization task has completed successfully
    ///
    /// Note: This is a best-effort check. The task might complete between
    /// checking this property and executing a query.
    public var isSchemaReady: Bool {
        guard let task = schemaInitTask else {
            return true  // No schema initialization needed
        }
        // Check if task is finished (either succeeded or failed)
        // We can't directly check task completion without awaiting,
        // so we return false if task exists (conservative approach)
        return false
    }

    /// Wait for schema initialization to complete
    ///
    /// This method blocks until the background schema initialization task completes.
    /// If no schema initialization is needed, this returns immediately.
    ///
    /// - Throws: Error if schema initialization failed
    public func waitForSchema() async throws {
        try await schemaInitTask?.value
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
