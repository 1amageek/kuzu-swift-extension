import Foundation
import Kuzu

public actor GraphContainer {
    private let configuration: GraphConfiguration
    private let database: Database
    private let connectionPool: ConnectionPool
    private var isInitialized = false
    
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
        
        try await initialize()
    }
    
    private func initialize() async throws {
        guard !isInitialized else { return }
        
        try await loadExtensions()
        
        isInitialized = true
    }
    
    private func loadExtensions() async throws {
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
                    // Vector extension is built into kuzu-swift
                    // No need to explicitly load it
                    loadedExtensions.append(ext)
                    print("Vector extension enabled (statically linked)")
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
    
    deinit {
        // Note: Cannot await in deinit
        // Caller should explicitly call close() before releasing the container
    }
}