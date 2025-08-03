import Foundation

public struct GraphConfiguration: Sendable {
    public var schema: GraphSchema
    public var url: URL
    public var name: String
    public var options: Options
    
    public struct Options: Sendable {
        public var inMemory: Bool = false
        public var extensions: [KuzuExtension] = []
        public var migrationPolicy: MigrationPolicy = .safeOnly
        public var connectionPoolSize: Int = 5
        public var queryTimeout: TimeInterval? = nil
        
        public init(
            inMemory: Bool = false,
            extensions: [KuzuExtension] = [],
            migrationPolicy: MigrationPolicy = .safeOnly,
            connectionPoolSize: Int = 5,
            queryTimeout: TimeInterval? = nil
        ) {
            self.inMemory = inMemory
            self.extensions = extensions
            self.migrationPolicy = migrationPolicy
            self.connectionPoolSize = connectionPoolSize
            self.queryTimeout = queryTimeout
        }
    }
    
    public init(schema: GraphSchema, url: URL, name: String, options: Options = .init()) {
        self.schema = schema
        self.url = url
        self.name = name
        self.options = options
    }
    
    public init(schema: GraphSchema, inMemory: Bool = false, name: String = "default", options: Options = .init()) {
        self.schema = schema
        self.url = URL(string: ":memory:")!
        self.name = name
        var modifiedOptions = options
        modifiedOptions.inMemory = true
        self.options = modifiedOptions
    }
}