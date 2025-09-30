import Foundation
import Kuzu

/// GraphContainer manages the database and connection pool.
///
/// Thread Safety: This struct conforms to Sendable because:
/// - All properties are immutable (let)
/// - Database and Connection are internally thread-safe (verified via Kuzu documentation)
/// - ConnectionPool is an actor providing synchronized access to connections
///
/// The underlying Kuzu C++ library guarantees thread-safe access to Database instances,
/// and each Connection is independent and can be safely used from different threads.
public struct GraphContainer: Sendable {
    private let configuration: GraphConfiguration
    private let database: Database
    private let connectionPool: ConnectionPool
    private let isInitialized: Bool
    
    public init(configuration: GraphConfiguration) async throws {
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

        // Mark as initialized before calling methods that use self
        self.isInitialized = true

        // Load extensions after all properties are initialized
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
                throw GraphError.transactionFailed(reason: error.localizedDescription)
            }
        } catch {
            await connectionPool.checkin(connection)
            throw error
        }
    }
    
    public func close() async {
        await connectionPool.drain()
    }
}
