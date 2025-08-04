import Foundation
import Kuzu

// MARK: - GraphModel Protocol for ORM-like operations
public protocol GraphModel: _KuzuGraphModel, Codable {
    static var modelName: String { get }
}

public extension GraphModel {
    static var modelName: String {
        String(describing: Self.self)
    }
}

// MARK: - Simple CRUD Operations
public extension GraphContext {
    
    /// Save a model instance (insert or update)
    @discardableResult
    func save<T: GraphModel>(_ model: T) async throws -> T {
        let columns = T._kuzuColumns
        
        // Extract properties using the same pattern as Create.node
        let properties = extractProperties(from: model, columns: columns)
        
        // Check if exists (assuming first column is ID)
        guard let idColumn = columns.first else {
            throw GraphError.invalidConfiguration(message: "Model must have at least one column")
        }
        
        let idValue = properties[idColumn.name]
        
        let existsQuery = """
            MATCH (n:\(T.modelName) {\(idColumn.name): $id})
            RETURN count(n) > 0
            """
        
        let existsResult = try await raw(existsQuery, bindings: ["id": idValue ?? NSNull()])
        let exists = try existsResult.mapFirstRequired(to: Bool.self, at: 0)
        
        if exists {
            // Update existing
            let setClause = columns.dropFirst()
                .map { "n.\($0.name) = $\($0.name)" }
                .joined(separator: ", ")
            
            if !setClause.isEmpty {
                let updateQuery = """
                    MATCH (n:\(T.modelName) {\(idColumn.name): $\(idColumn.name)})
                    SET \(setClause)
                    RETURN n
                    """
                
                let result = try await raw(updateQuery, bindings: properties)
                return try result.decode(T.self)
            }
        } else {
            // Insert new
            let propertyList = columns
                .map { "\($0.name): $\($0.name)" }
                .joined(separator: ", ")
            
            let createQuery = """
                CREATE (n:\(T.modelName) {\(propertyList)})
                RETURN n
                """
            
            let result = try await raw(createQuery, bindings: properties)
            return try result.decode(T.self)
        }
        
        return model
    }
    
    /// Save multiple model instances
    @discardableResult
    func save<T: GraphModel>(_ models: [T]) async throws -> [T] {
        var results: [T] = []
        for model in models {
            let saved = try await save(model)
            results.append(saved)
        }
        return results
    }
    
    /// Fetch all instances of a model type
    func fetch<T: GraphModel>(_ type: T.Type) async throws -> [T] {
        let query = """
            MATCH (n:\(type.modelName))
            RETURN n
            """
        let result = try await raw(query)
        return try result.decodeArray(T.self)
    }
    
    /// Fetch instances matching a simple equality predicate
    func fetch<T: GraphModel>(
        _ type: T.Type,
        where property: String,
        equals value: any Sendable
    ) async throws -> [T] {
        let query = """
            MATCH (n:\(type.modelName) {\(property): $value})
            RETURN n
            """
        
        let result = try await raw(query, bindings: ["value": value])
        return try result.decodeArray(T.self)
    }
    
    /// Fetch a single instance by ID
    func fetchOne<T: GraphModel>(_ type: T.Type, id: any Sendable) async throws -> T? {
        guard let idColumn = type._kuzuColumns.first else {
            throw GraphError.invalidConfiguration(message: "Model must have at least one column")
        }
        
        let query = """
            MATCH (n:\(type.modelName) {\(idColumn.name): $id})
            RETURN n
            """
        
        let result = try await raw(query, bindings: ["id": id])
        
        if result.hasNext() {
            return try result.decode(type)
        }
        return nil
    }
    
    /// Delete a model instance
    func delete<T: GraphModel>(_ model: T) async throws {
        guard let idColumn = T._kuzuColumns.first else {
            throw GraphError.invalidConfiguration(message: "Model must have at least one column")
        }
        
        // Extract ID from model
        let properties = extractProperties(from: model, columns: T._kuzuColumns)
        let id = properties[idColumn.name]
        
        let deleteQuery = """
            MATCH (n:\(T.modelName) {\(idColumn.name): $id})
            DELETE n
            """
        
        _ = try await raw(deleteQuery, bindings: ["id": id ?? NSNull()])
    }
    
    /// Delete multiple model instances
    func delete<T: GraphModel>(_ models: [T]) async throws {
        for model in models {
            try await delete(model)
        }
    }
    
    /// Delete all instances of a model type
    func deleteAll<T: GraphModel>(_ type: T.Type) async throws {
        let deleteQuery = "MATCH (n:\(type.modelName)) DELETE n"
        _ = try await raw(deleteQuery)
    }
    
    /// Count instances of a model type
    func count<T: GraphModel>(_ type: T.Type) async throws -> Int {
        let countQuery = "MATCH (n:\(type.modelName)) RETURN count(n)"
        let result = try await raw(countQuery)
        return try result.mapFirstRequired(to: Int.self, at: 0)
    }
    
    /// Count instances matching a simple equality predicate
    func count<T: GraphModel>(
        _ type: T.Type,
        where property: String,
        equals value: any Sendable
    ) async throws -> Int {
        let query = """
            MATCH (n:\(type.modelName) {\(property): $value})
            RETURN count(n)
            """
        
        let result = try await raw(query, bindings: ["value": value])
        return try result.mapFirstRequired(to: Int.self, at: 0)
    }
}

// MARK: - Batch Operations
public extension GraphContext {
    
    /// Perform multiple operations in a transaction
    func transaction<T: Sendable>(_ operations: @escaping @Sendable (GraphContext) async throws -> T) async throws -> T {
        // Since GraphContext already handles transactions internally,
        // we can directly execute the operations
        try await operations(self)
    }
    
    /// Batch insert with better performance
    func batchInsert<T: GraphModel>(_ models: [T]) async throws {
        guard !models.isEmpty else { return }
        
        let columns = T._kuzuColumns
        let modelName = T.modelName
        
        // Create parameter lists
        var allBindings: [[String: any Sendable]] = []
        
        for model in models {
            let properties = extractProperties(from: model, columns: columns)
            allBindings.append(properties)
        }
        
        // Execute batch insert
        for (index, bindings) in allBindings.enumerated() {
            let propertyList = columns
                .map { "\($0.name): $\($0.name)_\(index)" }
                .joined(separator: ", ")
            
            var renamedBindings: [String: any Sendable] = [:]
            for (key, value) in bindings {
                renamedBindings["\(key)_\(index)"] = value
            }
            
            let createQuery = """
                CREATE (:\(modelName) {\(propertyList)})
                """
            
            _ = try await raw(createQuery, bindings: renamedBindings)
        }
    }
}

// MARK: - Relationship Helpers
public extension GraphContext {
    
    /// Create a relationship between two nodes
    func createRelationship<From: GraphModel, To: GraphModel, Edge: _KuzuGraphModel>(
        from source: From,
        to target: To,
        edge: Edge
    ) async throws {
        guard let fromIdColumn = From._kuzuColumns.first,
              let toIdColumn = To._kuzuColumns.first else {
            throw GraphError.invalidConfiguration(message: "Models must have at least one column")
        }
        
        // Extract IDs from models
        let sourceProperties = extractProperties(from: source, columns: From._kuzuColumns)
        let targetProperties = extractProperties(from: target, columns: To._kuzuColumns)
        
        let fromId = sourceProperties[fromIdColumn.name]
        let toId = targetProperties[toIdColumn.name]
        
        let edgeColumns = Edge._kuzuColumns
        let edgeProperties = extractProperties(from: edge, columns: edgeColumns)
        
        var edgeBindings: [String: any Sendable] = [:]
        for (key, value) in edgeProperties {
            edgeBindings["edge_\(key)"] = value
        }
        
        let edgePropertyList = edgeColumns
            .map { "\($0.name): $edge_\($0.name)" }
            .joined(separator: ", ")
        
        let query = """
            MATCH (from:\(From.modelName) {\(fromIdColumn.name): $fromId})
            MATCH (to:\(To.modelName) {\(toIdColumn.name): $toId})
            CREATE (from)-[:\(String(describing: Edge.self)) {\(edgePropertyList)}]->(to)
            """
        
        var bindings = edgeBindings
        bindings["fromId"] = fromId
        bindings["toId"] = toId
        
        _ = try await raw(query, bindings: bindings)
    }
}

// MARK: - Private Helpers

private func extractProperties(from instance: Any, columns: [(name: String, type: String, constraints: [String])]) -> [String: any Sendable] {
    let mirror = Mirror(reflecting: instance)
    var properties: [String: any Sendable] = [:]
    
    // Extract properties using Mirror
    for child in mirror.children {
        guard let propertyName = child.label else { continue }
        
        // Remove underscore prefix if present (for property wrappers)
        let cleanName = propertyName.hasPrefix("_") ? String(propertyName.dropFirst()) : propertyName
        
        // Check if this property is in the model's column definition
        if columns.contains(where: { $0.name == cleanName }) {
            if let sendableValue = SendableExtractor.extract(from: child.value) {
                properties[cleanName] = sendableValue
            }
        }
    }
    
    return properties
}