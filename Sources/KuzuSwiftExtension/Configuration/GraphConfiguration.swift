import Foundation

public struct GraphConfiguration: Sendable {
    public let databasePath: String
    public let options: Options
    public let encodingConfiguration: KuzuEncoder.Configuration
    public let decodingConfiguration: KuzuDecoder.Configuration
    public let statementCacheSize: Int
    public let statementCacheTTL: TimeInterval
    public let migrationMode: MigrationMode
    
    public init(
        databasePath: String = ":memory:",
        options: Options = Options(),
        encodingConfiguration: KuzuEncoder.Configuration = KuzuEncoder.Configuration(),
        decodingConfiguration: KuzuDecoder.Configuration = KuzuDecoder.Configuration(),
        statementCacheSize: Int = 100,
        statementCacheTTL: TimeInterval = 3600,
        migrationMode: MigrationMode = .automatic
    ) {
        self.databasePath = databasePath
        self.options = options
        self.encodingConfiguration = encodingConfiguration
        self.decodingConfiguration = decodingConfiguration
        self.statementCacheSize = statementCacheSize
        self.statementCacheTTL = statementCacheTTL
        self.migrationMode = migrationMode
    }
    
    /// Migration mode for schema management
    public enum MigrationMode: Sendable {
        /// SwiftData-style: automatically create and update schemas (default)
        case automatic
        
        /// Traditional: use differential migration with policy
        case managed(policy: MigrationPolicy)
        
        /// No migration: schema management is handled externally
        case none
    }
    
    public struct Options: Sendable {
        public let maxConnections: Int
        public let minConnections: Int
        public let connectionTimeout: TimeInterval
        public let extensions: Set<KuzuExtension>
        public let migrationPolicy: MigrationPolicy
        public let enableLogging: Bool
        public let maxNumThreadsPerQuery: Int?
        public let queryTimeout: TimeInterval?
        
        public init(
            maxConnections: Int = 10,
            minConnections: Int = 1,
            connectionTimeout: TimeInterval = 30,
            extensions: Set<KuzuExtension> = [],
            migrationPolicy: MigrationPolicy = .safeOnly,
            enableLogging: Bool = false,
            maxNumThreadsPerQuery: Int? = nil,
            queryTimeout: TimeInterval? = nil
        ) {
            self.maxConnections = maxConnections
            self.minConnections = minConnections
            self.connectionTimeout = connectionTimeout
            self.extensions = extensions
            self.migrationPolicy = migrationPolicy
            self.enableLogging = enableLogging
            self.maxNumThreadsPerQuery = maxNumThreadsPerQuery
            self.queryTimeout = queryTimeout
        }
    }
    
    // Extension type has been moved to KuzuExtension.swift
}