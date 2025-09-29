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
                // Try to install and load the extension
                #if os(iOS) || os(tvOS) || os(watchOS)
                // On iOS platforms, skip INSTALL as it will fail due to sandbox
                // Some extensions might be built-in and LOAD might still work
                _ = try connection.query("LOAD EXTENSION \(ext.extensionName)")
                #else
                // On other platforms, try to install first
                _ = try connection.query("INSTALL \(ext.extensionName)")
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

        // Only throw if all extensions failed and at least one was critical
        if loadedExtensions.isEmpty && !configuration.options.extensions.isEmpty {
            #if os(iOS) || os(tvOS) || os(watchOS)
            // On iOS, extension failures are expected - just log
            if !failedExtensions.isEmpty {
                print("Note: Extensions are limited on iOS. Failed to load: \(failedExtensions.map { $0.0.rawValue }.joined(separator: ", "))")
            }
            #else
            // On other platforms, throw if no extensions loaded
            throw GraphError.extensionLoadFailed(
                extension: failedExtensions.map { $0.0.rawValue }.joined(separator: ", "),
                reason: "Failed to load any requested extensions"
            )
            #endif
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