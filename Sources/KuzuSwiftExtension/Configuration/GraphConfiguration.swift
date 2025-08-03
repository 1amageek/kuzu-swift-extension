import Foundation

public struct GraphConfiguration: Sendable {
    public let databasePath: String
    public let options: Options
    
    public init(
        databasePath: String = ":memory:",
        options: Options = Options()
    ) {
        self.databasePath = databasePath
        self.options = options
    }
    
    public struct Options: Sendable {
        public let maxConnections: Int
        public let minConnections: Int
        public let connectionTimeout: TimeInterval
        public let extensions: Set<KuzuExtension>
        public let migrationPolicy: MigrationPolicy
        public let enableLogging: Bool
        
        public init(
            maxConnections: Int = 10,
            minConnections: Int = 1,
            connectionTimeout: TimeInterval = 30,
            extensions: Set<KuzuExtension> = [],
            migrationPolicy: MigrationPolicy = .safeOnly,
            enableLogging: Bool = false
        ) {
            self.maxConnections = maxConnections
            self.minConnections = minConnections
            self.connectionTimeout = connectionTimeout
            self.extensions = extensions
            self.migrationPolicy = migrationPolicy
            self.enableLogging = enableLogging
        }
    }
    
    // Extension type has been moved to KuzuExtension.swift
}