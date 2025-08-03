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
        public let extensions: Set<Extension>
        public let migrationPolicy: MigrationPolicy
        public let enableLogging: Bool
        
        public init(
            maxConnections: Int = 10,
            minConnections: Int = 1,
            connectionTimeout: TimeInterval = 30,
            extensions: Set<Extension> = [],
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
    
    public enum Extension: String, CaseIterable, Hashable, Sendable {
        case httpfs
        case json
        case parquet
        case postgres_scanner
        case rdf
        case s3
        case vector
        case fts
        
        var installCommand: String {
            "INSTALL \(rawValue)"
        }
        
        var loadCommand: String {
            "LOAD EXTENSION \(rawValue)"
        }
    }
}