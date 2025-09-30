import Foundation
import Kuzu
@_exported import KuzuSwiftProtocols

// MARK: - Simple CRUD Operations
public extension GraphContext {
    
    /// Save a model instance (insert or update) using MERGE for optimal performance
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

        // Build property assignments for CREATE and MATCH
        // ON CREATE SET cannot include primary key - it's already set in MERGE pattern
        // ON CREATE SET needs assignment form: n.prop = $param
        let nonIdColumns = Array(columns.dropFirst())

        let mergeQuery: String
        if nonIdColumns.isEmpty {
            // If only ID column exists, no properties to update
            mergeQuery = """
                MERGE (n:\(T.modelName) {\(idColumn.name): $\(idColumn.name)})
                RETURN n
                """
        } else {
            let createProps = QueryHelpers.buildPropertyAssignments(
                columns: nonIdColumns,
                isAssignment: true
            )
            .map { "n.\($0)" }
            .joined(separator: ", ")

            let updateProps = QueryHelpers.buildPropertyAssignments(
                columns: nonIdColumns,
                isAssignment: true
            )
            .map { "n.\($0)" }
            .joined(separator: ", ")

            mergeQuery = """
                MERGE (n:\(T.modelName) {\(idColumn.name): $\(idColumn.name)})
                ON CREATE SET \(createProps)
                ON MATCH SET \(updateProps)
                RETURN n
                """
        }

        let result = try await raw(mergeQuery, bindings: properties)
        return try result.decode(T.self)
    }
    
    /// Save multiple model instances using batch operation
    /// This method automatically uses saveAll() for optimal performance
    @discardableResult
    func save<T: GraphNodeModel>(_ models: [T]) async throws -> [T] {
        return try await saveAll(models)
    }

    /// Save multiple model instances in a single batch operation using UNWIND + MERGE.
    /// This is significantly faster than calling save() repeatedly.
    ///
    /// - Parameter models: Array of models to save (insert or update)
    /// - Returns: Array of saved models
    /// - Note: This performs an UPSERT operation - creates new nodes or updates existing ones
    @discardableResult
    func saveAll<T: GraphNodeModel>(_ models: [T]) async throws -> [T] {
        guard !models.isEmpty else { return [] }

        let columns = T._kuzuColumns
        guard let idColumn = columns.first else {
            throw GraphError.invalidConfiguration(message: "Model must have at least one column")
        }

        // Encode all models to property dictionaries
        let encoder = KuzuEncoder()
        let items: [[String: any Sendable]] = try models.map { model in
            try encoder.encode(model)
        }

        // Build property assignments for CREATE and MATCH
        // ON CREATE SET cannot include primary key - it's already set in MERGE pattern
        let nonIdColumns = Array(columns.dropFirst())

        // UNWIND + MERGE query for batch UPSERT
        let query: String
        if nonIdColumns.isEmpty {
            // If only ID column exists, no properties to update
            query = """
                UNWIND $items AS item
                MERGE (n:\(T.modelName) {\(idColumn.name): item.\(idColumn.name)})
                RETURN n
                """
        } else {
            // Build property assignments with proper TIMESTAMP handling
            let createAssignments = nonIdColumns.map { column -> String in
                let value = column.type == "TIMESTAMP"
                    ? "timestamp(item.\(column.name))"
                    : "item.\(column.name)"
                return "n.\(column.name) = \(value)"
            }.joined(separator: ", ")

            let updateAssignments = nonIdColumns.map { column -> String in
                let value = column.type == "TIMESTAMP"
                    ? "timestamp(item.\(column.name))"
                    : "item.\(column.name)"
                return "n.\(column.name) = \(value)"
            }.joined(separator: ", ")

            query = """
                UNWIND $items AS item
                MERGE (n:\(T.modelName) {\(idColumn.name): item.\(idColumn.name)})
                ON CREATE SET \(createAssignments)
                ON MATCH SET \(updateAssignments)
                RETURN n
                """
        }

        let result = try await raw(query, bindings: ["items": items])
        return try result.decodeArray(T.self)
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
        let properties = try extractProperties(from: model, columns: T._kuzuColumns)
        let id = properties[idColumn.name]
        
        let deleteQuery = """
            MATCH (n:\(T.modelName) {\(idColumn.name): $id})
            DELETE n
            """
        
        _ = try await raw(deleteQuery, bindings: ["id": id ?? NSNull()])
    }
    
    /// Delete multiple model instances in a single batch operation using UNWIND
    func delete<T: GraphNodeModel>(_ models: [T]) async throws {
        guard !models.isEmpty else { return }

        guard let idColumn = T._kuzuColumns.first else {
            throw GraphError.invalidConfiguration(message: "Model must have at least one column")
        }

        // Extract IDs from all models
        let encoder = KuzuEncoder()
        let ids: [any Sendable] = try models.map { model in
            let properties = try encoder.encode(model)
            guard let id = properties[idColumn.name] else {
                throw GraphError.invalidOperation(message: "Model missing ID property")
            }
            return id
        }

        // Use UNWIND for batch delete
        let deleteQuery = """
            UNWIND $ids AS id
            MATCH (n:\(T.modelName) {\(idColumn.name): id})
            DELETE n
            """

        _ = try await raw(deleteQuery, bindings: ["ids": ids])
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

    /// Batch insert multiple nodes in a single query using UNWIND.
    /// This is significantly faster than inserting nodes one by one.
    ///
    /// - Parameter models: Array of models to insert
    /// - Note: This performs INSERT only. For UPSERT behavior, use saveAll() instead.
    func batchInsert<T: GraphNodeModel>(_ models: [T]) async throws {
        guard !models.isEmpty else { return }

        let columns = T._kuzuColumns
        let modelName = T.modelName

        // Encode all models to property dictionaries
        let encoder = KuzuEncoder()
        let items: [[String: any Sendable]] = try models.map { model in
            try encoder.encode(model)
        }

        // Build property assignments for CREATE with proper TIMESTAMP handling
        let propsList = columns.map { column -> String in
            let value = column.type == "TIMESTAMP"
                ? "timestamp(item.\(column.name))"
                : "item.\(column.name)"
            return "\(column.name): \(value)"
        }.joined(separator: ", ")

        // UNWIND + CREATE for batch insert
        let query = """
            UNWIND $items AS item
            CREATE (:\(modelName) {\(propsList)})
            """

        _ = try await raw(query, bindings: ["items": items])
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
        let sourceProperties = try extractProperties(from: source, columns: From._kuzuColumns)
        let targetProperties = try extractProperties(from: target, columns: To._kuzuColumns)

        let fromId = sourceProperties[fromIdColumn.name]
        let toId = targetProperties[toIdColumn.name]

        let edgeColumns = Edge._kuzuColumns
        let edgeProperties = try extractProperties(from: edge, columns: edgeColumns)
        
        var edgeBindings: [String: any Sendable] = [:]
        for (key, value) in edgeProperties {
            edgeBindings["edge_\(key)"] = value
        }
        
        let edgePropertyList = QueryHelpers.buildPropertyAssignments(
            columns: edgeColumns,
            parameterPrefix: "edge",
            isAssignment: false
        )
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

    /// Create multiple relationships in a single batch operation using UNWIND
    func createRelationships<From: GraphNodeModel & Encodable, To: GraphNodeModel & Encodable, Edge: _KuzuGraphModel & Encodable>(
        relationships: [(from: From, to: To, edge: Edge)]
    ) async throws {
        guard !relationships.isEmpty else { return }

        guard let fromIdColumn = From._kuzuColumns.first,
              let toIdColumn = To._kuzuColumns.first else {
            throw GraphError.invalidConfiguration(message: "Models must have at least one column")
        }

        let edgeColumns = Edge._kuzuColumns
        let encoder = KuzuEncoder()

        // Build relationship data
        let items: [[String: any Sendable]] = try relationships.map { rel in
            let sourceProperties = try encoder.encode(rel.from)
            let targetProperties = try encoder.encode(rel.to)
            let edgeProperties = try encoder.encode(rel.edge)

            guard let fromId = sourceProperties[fromIdColumn.name],
                  let toId = targetProperties[toIdColumn.name] else {
                throw GraphError.invalidOperation(message: "Nodes must have ID properties")
            }

            var item: [String: any Sendable] = [
                "fromId": fromId,
                "toId": toId
            ]

            // Add edge properties with prefix
            for (key, value) in edgeProperties {
                item["edge_\(key)"] = value
            }

            return item
        }

        // Build edge property list
        let edgePropertyList = edgeColumns.map { column -> String in
            let value = column.type == "TIMESTAMP"
                ? "timestamp(item.edge_\(column.name))"
                : "item.edge_\(column.name)"
            return "\(column.name): \(value)"
        }.joined(separator: ", ")

        let edgePropsClause = edgePropertyList.isEmpty ? "" : " {\(edgePropertyList)}"

        // UNWIND + CREATE for batch relationship creation
        let query = """
            UNWIND $items AS item
            MATCH (from:\(From.modelName) {\(fromIdColumn.name): item.fromId})
            MATCH (to:\(To.modelName) {\(toIdColumn.name): item.toId})
            CREATE (from)-[:\(String(describing: Edge.self))\(edgePropsClause)]->(to)
            """

        _ = try await raw(query, bindings: ["items": items])
    }
}

// MARK: - Private Helpers

private func extractProperties(from instance: Any, columns: [(name: String, type: String, constraints: [String])]) throws -> [String: any Sendable] {
    guard let encodable = instance as? any Encodable else {
        throw GraphError.invalidConfiguration(
            message: "Model must conform to Encodable. Type: \(type(of: instance))"
        )
    }

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
}
