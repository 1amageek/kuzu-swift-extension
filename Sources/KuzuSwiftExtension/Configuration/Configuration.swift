import Foundation

// MARK: - Main Configuration

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
        public let enableLogging: Bool
        public let maxNumThreadsPerQuery: Int?
        public let queryTimeout: TimeInterval?
        public let bufferPoolSize: Int
        
        public init(
            maxConnections: Int = 5,
            minConnections: Int = 1,
            connectionTimeout: TimeInterval = 30.0,
            extensions: Set<KuzuExtension> = [],
            enableLogging: Bool = false,
            maxNumThreadsPerQuery: Int? = nil,
            queryTimeout: TimeInterval? = nil,
            bufferPoolSize: Int = 256 * 1024 * 1024 // 256MB
        ) {
            self.maxConnections = maxConnections
            self.minConnections = minConnections
            self.connectionTimeout = connectionTimeout
            self.extensions = extensions
            self.enableLogging = enableLogging
            self.maxNumThreadsPerQuery = maxNumThreadsPerQuery
            self.queryTimeout = queryTimeout
            self.bufferPoolSize = bufferPoolSize
        }
    }
}

// MARK: - Kuzu Extensions

/// Represents available Kuzu extensions
public enum KuzuExtension: String, CaseIterable, Sendable, Hashable {
    case httpfs
    case json
    case fts  // Full-text search
    case vector  // Vector similarity search
    
    public var extensionName: String {
        return self.rawValue
    }
    
    public var loadStatement: String {
        return "LOAD EXTENSION \(extensionName)"
    }
}

// MARK: - Migration Policy

/// Policy for handling schema migrations
public enum MigrationPolicy: Sendable {
    /// Automatically apply all migrations (default)
    case automatic
    
    /// Apply safe migrations only (add tables, add optional columns)
    case safe
    
    /// Manual migration - user handles all migrations
    case manual
    
    /// Destructive migrations allowed (drop tables, columns)
    case destructive
    
    /// Custom policy with specific rules
    case custom(rules: MigrationRules)
}

/// Rules for custom migration policies
public struct MigrationRules: Sendable {
    public let allowTableCreation: Bool
    public let allowTableDeletion: Bool
    public let allowColumnAddition: Bool
    public let allowColumnDeletion: Bool
    public let allowIndexCreation: Bool
    public let allowIndexDeletion: Bool
    public let allowConstraintChanges: Bool
    
    public init(
        allowTableCreation: Bool = true,
        allowTableDeletion: Bool = false,
        allowColumnAddition: Bool = true,
        allowColumnDeletion: Bool = false,
        allowIndexCreation: Bool = true,
        allowIndexDeletion: Bool = false,
        allowConstraintChanges: Bool = false
    ) {
        self.allowTableCreation = allowTableCreation
        self.allowTableDeletion = allowTableDeletion
        self.allowColumnAddition = allowColumnAddition
        self.allowColumnDeletion = allowColumnDeletion
        self.allowIndexCreation = allowIndexCreation
        self.allowIndexDeletion = allowIndexDeletion
        self.allowConstraintChanges = allowConstraintChanges
    }
    
    /// Pre-defined safe rules
    public static let safe = MigrationRules()
    
    /// Pre-defined destructive rules
    public static let destructive = MigrationRules(
        allowTableCreation: true,
        allowTableDeletion: true,
        allowColumnAddition: true,
        allowColumnDeletion: true,
        allowIndexCreation: true,
        allowIndexDeletion: true,
        allowConstraintChanges: true
    )
}