import Foundation
import Kuzu
@_exported import KuzuSwiftProtocols

// MARK: - Simple CRUD Operations
public extension GraphContext {
    
    /// Save a model instance (insert or update)
    @discardableResult
    func save<T: GraphNodeModel>(_ model: T) async throws -> T {
        let columns = T._kuzuColumns
        
        // Extract properties using KuzuEncoder
        let encoder = KuzuEncoder()
        let properties = try encoder.encode(model)
        
        // Check if exists (assuming first column is ID)
        guard let idColumn = columns.first else {
            throw GraphError.invalidConfiguration(message: "Model must have at least one column")
        }
        
        let idValue = properties[idColumn.name]
        
        // Check if node exists
        let existsQuery = """
            MATCH (n:\(T.modelName))
            WHERE n.\(idColumn.name) = $id
            RETURN n
            """
        
        let existsResult = try await raw(existsQuery, bindings: ["id": idValue ?? NSNull()])
        
        if existsResult.hasNext() {
            // Update existing node (skip ID column as it's primary key)
            let setClause = columns
                .dropFirst()  // Skip the ID column
                .map { column in
                    // Check if this is a TIMESTAMP column
                    if column.type == "TIMESTAMP" {
                        return "n.\(column.name) = CAST($\(column.name) AS TIMESTAMP)"
                    } else {
                        return "n.\(column.name) = $\(column.name)"
                    }
                }
                .joined(separator: ", ")
            
            let updateQuery = """
                MATCH (n:\(T.modelName))
                WHERE n.\(idColumn.name) = $\(idColumn.name)
                SET \(setClause)
                RETURN n
                """
            
            
            let result = try await raw(updateQuery, bindings: properties)
            return try result.decode(T.self)
        } else {
            // Create new node
            let propertyList = columns
                .map { column in
                    // Check if this is a TIMESTAMP column
                    if column.type == "TIMESTAMP" {
                        return "\(column.name): CAST($\(column.name) AS TIMESTAMP)"
                    } else {
                        return "\(column.name): $\(column.name)"
                    }
                }
                .joined(separator: ", ")
            
            let createQuery = """
                CREATE (n:\(T.modelName) {\(propertyList)})
                RETURN n
                """
            
            let result = try await raw(createQuery, bindings: properties)
            
            return try result.decode(T.self)
        }
    }
    
    /// Save multiple model instances
    @discardableResult
    func save<T: GraphNodeModel>(_ models: [T]) async throws -> [T] {
        var results: [T] = []
        for model in models {
            let saved = try await save(model)
            results.append(saved)
        }
        return results
    }
    
    /// Fetch all instances of a model type
    func fetch<T: GraphNodeModel>(_ type: T.Type) async throws -> [T] {
        let query = """
            MATCH (n:\(type.modelName))
            RETURN n
            """
        let result = try await raw(query)
        return try result.decodeArray(T.self)
    }
    
    /// Fetch instances matching a simple equality predicate
    func fetch<T: GraphNodeModel>(
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
    func fetchOne<T: GraphNodeModel>(_ type: T.Type, id: any Sendable) async throws -> T? {
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
    func delete<T: GraphNodeModel>(_ model: T) async throws {
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
    func delete<T: GraphNodeModel>(_ models: [T]) async throws {
        for model in models {
            try await delete(model)
        }
    }
    
    /// Delete all instances of a model type
    func deleteAll<T: GraphNodeModel>(_ type: T.Type) async throws {
        let deleteQuery = "MATCH (n:\(type.modelName)) DELETE n"
        _ = try await raw(deleteQuery)
    }
    
    /// Count instances of a model type
    func count<T: GraphNodeModel>(_ type: T.Type) async throws -> Int {
        let countQuery = "MATCH (n:\(type.modelName)) RETURN count(n)"
        let result = try await raw(countQuery)
        return try result.mapFirstRequired(to: Int.self, at: 0)
    }
    
    /// Count instances matching a simple equality predicate
    func count<T: GraphNodeModel>(
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
    
    /// Batch insert with better performance
    func batchInsert<T: GraphNodeModel>(_ models: [T]) async throws {
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
                .map { column in
                    let paramName = "\(column.name)_\(index)"
                    // Check if this is a TIMESTAMP column
                    if column.type == "TIMESTAMP" {
                        return "\(column.name): CAST($\(paramName) AS TIMESTAMP)"
                    } else {
                        return "\(column.name): $\(paramName)"
                    }
                }
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
    func createRelationship<From: GraphNodeModel, To: GraphNodeModel, Edge: _KuzuGraphModel>(
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
            .map { column in
                let paramName = "edge_\(column.name)"
                // Check if this is a TIMESTAMP column
                if column.type == "TIMESTAMP" {
                    return "\(column.name): CAST($\(paramName) AS TIMESTAMP)"
                } else {
                    return "\(column.name): $\(paramName)"
                }
            }
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
    // If the instance is Encodable, use KuzuEncoder
    if let encodable = instance as? any Encodable {
        do {
            let encoder = KuzuEncoder()
            let allProperties = try encoder.encode(encodable)
            
            // Filter to only include properties defined in columns
            var filteredProperties: [String: any Sendable] = [:]
            for (key, value) in allProperties {
                if columns.contains(where: { $0.name == key }) {
                    filteredProperties[key] = value
                }
            }
            return filteredProperties
        } catch {
            // Fall through to Mirror-based extraction if encoding fails
        }
    }
    
    // Fallback to Mirror-based extraction
    let mirror = Mirror(reflecting: instance)
    var properties: [String: any Sendable] = [:]
    
    // Extract properties using Mirror
    for child in mirror.children {
        guard let propertyName = child.label else { continue }
        
        // Remove underscore prefix if present (for property wrappers)
        let cleanName = propertyName.hasPrefix("_") ? String(propertyName.dropFirst()) : propertyName
        
        // Check if this property is in the model's column definition
        if columns.contains(where: { $0.name == cleanName }) {
            // Extract basic Sendable values directly
            switch child.value {
            case let string as String:
                properties[cleanName] = string
            case let int as Int:
                properties[cleanName] = int
            case let int8 as Int8:
                properties[cleanName] = int8
            case let int16 as Int16:
                properties[cleanName] = int16
            case let int32 as Int32:
                properties[cleanName] = int32
            case let int64 as Int64:
                properties[cleanName] = int64
            case let uint as UInt:
                properties[cleanName] = uint
            case let uint8 as UInt8:
                properties[cleanName] = uint8
            case let uint16 as UInt16:
                properties[cleanName] = uint16
            case let uint32 as UInt32:
                properties[cleanName] = uint32
            case let uint64 as UInt64:
                properties[cleanName] = uint64
            case let float as Float:
                properties[cleanName] = float
            case let double as Double:
                properties[cleanName] = double
            case let bool as Bool:
                properties[cleanName] = bool
            case let date as Date:
                properties[cleanName] = date
            case let data as Data:
                properties[cleanName] = data
            case let uuid as UUID:
                properties[cleanName] = uuid
            case let url as URL:
                properties[cleanName] = url
            case is NSNull:
                properties[cleanName] = NSNull()
            case let array as [any Sendable]:
                properties[cleanName] = array
            case let dict as [String: any Sendable]:
                properties[cleanName] = dict
            default:
                // Skip non-Sendable values
                break
            }
        }
    }
    
    return properties
}