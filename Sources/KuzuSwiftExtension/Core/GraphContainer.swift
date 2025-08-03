import Foundation
import KuzuFramework

public final class GraphContainer: Sendable {
    private let databases: [String: Database]
    private let connections: [String: ConnectionPool]
    private let configurations: [String: GraphConfiguration]
    
    public init(for schema: GraphSchema, _ configs: GraphConfiguration...) async throws {
        var databases: [String: Database] = [:]
        var connections: [String: ConnectionPool] = [:]
        var configurations: [String: GraphConfiguration] = [:]
        
        for config in configs {
            // Create database
            let db: Database
            if config.options.inMemory || config.url.absoluteString == ":memory:" {
                db = try Database()
            } else {
                db = try Database(config.url.path)
            }
            databases[config.name] = db
            
            // Create connection pool
            let pool = try ConnectionPool(database: db, size: config.options.connectionPoolSize)
            connections[config.name] = pool
            
            // Install extensions
            try await pool.withConnection { conn in
                for ext in config.options.extensions {
                    _ = try conn.query("INSTALL \(ext.rawValue);")
                    _ = try conn.query("LOAD EXTENSION \(ext.rawValue);")
                }
            }
            
            // Apply schema migration
            try await pool.withConnection { conn in
                let migrationManager = MigrationManager(
                    connection: conn,
                    policy: config.options.migrationPolicy
                )
                try await migrationManager.migrate(schema: config.schema)
            }
            
            configurations[config.name] = config
        }
        
        self.databases = databases
        self.connections = connections
        self.configurations = configurations
    }
    
    public convenience init(for schema: GraphSchema, configuration: GraphConfiguration) async throws {
        try await self.init(for: schema, configuration)
    }
    
    public func context(for name: String) -> GraphContext? {
        guard let pool = connections[name],
              let config = configurations[name] else {
            return nil
        }
        return GraphContext(connectionPool: pool, configuration: config)
    }
    
    public var defaultContext: GraphContext {
        guard let firstKey = configurations.keys.first,
              let context = context(for: firstKey) else {
            fatalError("No configurations available")
        }
        return context
    }
    
    public var contextNames: [String] {
        Array(configurations.keys)
    }
}