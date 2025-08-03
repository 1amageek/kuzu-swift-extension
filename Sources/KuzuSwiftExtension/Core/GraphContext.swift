import Foundation
import Kuzu

public actor GraphContext {
    private let container: GraphContainer
    private let configuration: GraphConfiguration
    
    public init(configuration: GraphConfiguration = GraphConfiguration()) async throws {
        self.configuration = configuration
        self.container = try await GraphContainer(configuration: configuration)
    }
    
    // MARK: - Raw Query Execution
    
    public func raw(_ query: String, bindings: [String: any Encodable & Sendable] = [:]) async throws -> QueryResult {
        // Convert parameters before entering the @Sendable closure
        let sendableParams = try ParameterConverter.convert(bindings)
        
        return try await container.withConnection { connection in
            if sendableParams.isEmpty {
                return try connection.query(query)
            } else {
                let statement = try connection.prepare(query)
                let kuzuParams = ParameterConverter.toKuzuParameters(sendableParams)
                return try connection.execute(statement, kuzuParams)
            }
        }
    }
    
    public func rawTransaction(_ query: String, bindings: [String: any Encodable & Sendable] = [:]) async throws -> QueryResult {
        // Convert parameters before entering the @Sendable closure
        let sendableParams = try ParameterConverter.convert(bindings)
        
        return try await container.withTransaction { connection in
            if sendableParams.isEmpty {
                return try connection.query(query)
            } else {
                let statement = try connection.prepare(query)
                let kuzuParams = ParameterConverter.toKuzuParameters(sendableParams)
                return try connection.execute(statement, kuzuParams)
            }
        }
    }
    
    // MARK: - Query DSL
    
    public func query<T>(@QueryBuilder _ builder: () -> Query) async throws -> T {
        let query = builder()
        let cypher = try CypherCompiler.compile(query)
        // Convert SendableParameters back to [String: any Encodable & Sendable] for the raw method
        var bindings: [String: any Encodable & Sendable] = [:]
        for (key, value) in cypher.parameters {
            // Extract the underlying value from ParameterValue
            switch value {
            case .string(let v): bindings[key] = v
            case .int64(let v): bindings[key] = v
            case .double(let v): bindings[key] = v
            case .bool(let v): bindings[key] = v
            case .timestamp(let v): bindings[key] = Date(timeIntervalSince1970: v)
            case .uuid(let v): bindings[key] = v
            case .vector(let v): bindings[key] = v
            case .json(let v): bindings[key] = v
            case .null: bindings[key] = nil as String?
            }
        }
        let result = try await raw(cypher.query, bindings: bindings)
        
        // TODO: Implement result mapping
        fatalError("Result mapping not yet implemented")
    }
    
    public func transaction<T>(@QueryBuilder _ builder: () -> Query) async throws -> T {
        let query = builder()
        let cypher = try CypherCompiler.compile(query)
        // Convert SendableParameters back to [String: any Encodable & Sendable] for the rawTransaction method
        var bindings: [String: any Encodable & Sendable] = [:]
        for (key, value) in cypher.parameters {
            // Extract the underlying value from ParameterValue
            switch value {
            case .string(let v): bindings[key] = v
            case .int64(let v): bindings[key] = v
            case .double(let v): bindings[key] = v
            case .bool(let v): bindings[key] = v
            case .timestamp(let v): bindings[key] = Date(timeIntervalSince1970: v)
            case .uuid(let v): bindings[key] = v
            case .vector(let v): bindings[key] = v
            case .json(let v): bindings[key] = v
            case .null: bindings[key] = nil as String?
            }
        }
        let result = try await rawTransaction(cypher.query, bindings: bindings)
        
        // TODO: Implement result mapping
        fatalError("Result mapping not yet implemented")
    }
    
    // MARK: - Schema Operations
    
    public func createSchema<T: _KuzuGraphModel>(for type: T.Type) async throws {
        let ddl = type._kuzuDDL
        _ = try await raw(ddl)
    }
    
    public func createSchema(for types: [any _KuzuGraphModel.Type]) async throws {
        try await container.withTransaction { connection in
            for type in types {
                _ = try connection.query(type._kuzuDDL)
            }
        }
    }
    
    // MARK: - Utility
    
    public func close() async {
        await container.close()
    }
    
}