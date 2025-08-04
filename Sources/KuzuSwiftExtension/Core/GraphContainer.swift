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
        
        self.connectionPool = try await ConnectionPool(
            database: database,
            maxConnections: configuration.options.maxConnections,
            minConnections: configuration.options.minConnections,
            timeout: configuration.options.connectionTimeout
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
        
        do {
            for ext in configuration.options.extensions {
                do {
                    _ = try connection.query(ext.installCommand)
                    _ = try connection.query(ext.loadCommand)
                } catch {
                    await connectionPool.checkin(connection)
                    throw GraphError.extensionLoadFailed(
                        extension: ext.rawValue,
                        reason: error.localizedDescription
                    )
                }
            }
            await connectionPool.checkin(connection)
        } catch {
            // Connection already checked in if extension load failed
            throw error
        }
    }
    
    public func withConnection<T>(_ block: @Sendable (Connection) throws -> T) async throws -> T {
        let connection = try await connectionPool.checkout()
        
        do {
            let result = try block(connection)
            await connectionPool.checkin(connection)
            return result
        } catch {
            await connectionPool.checkin(connection)
            throw error
        }
    }
    
    public func withTransaction<T>(_ block: @Sendable (Connection) throws -> T) async throws -> T {
        let connection = try await connectionPool.checkout()
        
        do {
            _ = try connection.query("BEGIN TRANSACTION")
            
            do {
                let result = try block(connection)
                _ = try connection.query("COMMIT")
                await connectionPool.checkin(connection)
                return result
            } catch {
                _ = try? connection.query("ROLLBACK")
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