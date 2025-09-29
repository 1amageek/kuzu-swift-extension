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
        databasePath: String? = nil,
        options: Options = Options(),
        encodingConfiguration: KuzuEncoder.Configuration = KuzuEncoder.Configuration(),
        decodingConfiguration: KuzuDecoder.Configuration = KuzuDecoder.Configuration(),
        statementCacheSize: Int = 100,
        statementCacheTTL: TimeInterval = 3600,
        migrationMode: MigrationMode = .automatic
    ) {
        // Use platform-appropriate default path if not specified
        self.databasePath = databasePath ?? Self.defaultDatabasePath()
        self.options = options
        self.encodingConfiguration = encodingConfiguration
        self.decodingConfiguration = decodingConfiguration
        self.statementCacheSize = statementCacheSize
        self.statementCacheTTL = statementCacheTTL
        self.migrationMode = migrationMode
    }

    /// Returns platform-appropriate default database path
    private static func defaultDatabasePath() -> String {
        #if os(iOS) || os(tvOS) || os(watchOS)
        // iOS/tvOS/watchOS: Use Documents directory (like SQLite)
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("kuzu.db").path
        #elseif os(macOS)
        // macOS: Use Application Support with bundle identifier
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.kuzu.default"
        let dbURL = appSupportURL.appendingPathComponent(bundleID).appendingPathComponent("kuzu.db")
        // Create directory if needed
        try? FileManager.default.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        return dbURL.path
        #else
        // Default to in-memory for other platforms
        return ":memory:"
        #endif
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
            maxConnections: Int? = nil,
            minConnections: Int = 1,
            connectionTimeout: TimeInterval = 30.0,
            extensions: Set<KuzuExtension> = [],
            enableLogging: Bool = false,
            maxNumThreadsPerQuery: Int? = nil,
            queryTimeout: TimeInterval? = nil,
            bufferPoolSize: Int? = nil
        ) {
            // Platform-specific defaults
            self.maxConnections = maxConnections ?? Self.defaultMaxConnections
            self.minConnections = minConnections
            self.connectionTimeout = connectionTimeout
            self.extensions = Self.filterExtensions(extensions)
            self.enableLogging = enableLogging
            self.maxNumThreadsPerQuery = maxNumThreadsPerQuery
            self.queryTimeout = queryTimeout ?? Self.defaultQueryTimeout
            self.bufferPoolSize = bufferPoolSize ?? Self.defaultBufferPoolSize
        }

        private static var defaultMaxConnections: Int {
            #if os(watchOS)
            return 1
            #elseif os(iOS) || os(tvOS)
            return 3
            #else
            return 5
            #endif
        }

        private static var defaultQueryTimeout: TimeInterval {
            #if os(watchOS)
            return 5.0
            #elseif os(iOS) || os(tvOS)
            return 30.0
            #else
            return 60.0
            #endif
        }

        private static var defaultBufferPoolSize: Int {
            #if os(watchOS)
            return 16 * 1024 * 1024  // 16MB
            #elseif os(iOS)
            // Adaptive based on device memory
            let physicalMemory = ProcessInfo.processInfo.physicalMemory
            return physicalMemory > 2_000_000_000 ? 128 * 1024 * 1024 : 64 * 1024 * 1024
            #elseif os(tvOS)
            return 128 * 1024 * 1024  // 128MB
            #else
            return 256 * 1024 * 1024  // 256MB
            #endif
        }

        private static func filterExtensions(_ requested: Set<KuzuExtension>) -> Set<KuzuExtension> {
            #if os(iOS) || os(tvOS) || os(watchOS)
            // On iOS platforms, we now support vector extension as it's statically linked in kuzu-swift
            // FTS extension support is also available through static linking
            let supported: Set<KuzuExtension> = [.json, .vector, .fts]
            let filtered = requested.intersection(supported)
            if filtered != requested {
                let unsupported = requested.subtracting(filtered)
                print("Warning: Extensions \(unsupported) are not supported on this platform")
            }
            return filtered
            #else
            return requested
            #endif
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