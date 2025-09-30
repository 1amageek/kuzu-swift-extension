import Foundation
import Kuzu
@_exported import KuzuSwiftProtocols

// MARK: - Fetch Operations
public extension GraphContext {
    
    /// Fetch all instances of a model type
    func fetch<T: GraphNodeModel>(_ type: T.Type) throws -> [T] {
        let query = """
            MATCH (n:\(type.modelName))
            RETURN n
            """
        let result = try raw(query)
        return try result.decodeArray(T.self)
    }
    
    /// Fetch instances matching a simple equality predicate
    func fetch<T: GraphNodeModel>(
        _ type: T.Type,
        where property: String,
        equals value: any Sendable
    ) throws -> [T] {
        let query = """
            MATCH (n:\(type.modelName) {\(property): $value})
            RETURN n
            """

        let result = try raw(query, bindings: ["value": value])
        return try result.decodeArray(T.self)
    }
    
    /// Fetch a single instance by ID
    func fetchOne<T: GraphNodeModel>(_ type: T.Type, id: any Sendable) throws -> T? {
        guard let idColumn = type._kuzuColumns.first else {
            throw GraphError.invalidConfiguration(message: "Model must have at least one column")
        }

        let query = """
            MATCH (n:\(type.modelName) {\(idColumn.name): $id})
            RETURN n
            """

        let result = try raw(query, bindings: ["id": id])

        if result.hasNext() {
            return try result.decode(type)
        }
        return nil
    }
    
    /// Delete all instances of a model type
    func deleteAll<T: GraphNodeModel>(_ type: T.Type) throws {
        let deleteQuery = "MATCH (n:\(type.modelName)) DELETE n"
        _ = try raw(deleteQuery)
    }
    
    /// Count instances of a model type
    func count<T: GraphNodeModel>(_ type: T.Type) throws -> Int {
        let countQuery = "MATCH (n:\(type.modelName)) RETURN count(n)"
        let result = try raw(countQuery)
        return try result.mapFirstRequired(to: Int.self, at: 0)
    }
    
    /// Count instances matching a simple equality predicate
    func count<T: GraphNodeModel>(
        _ type: T.Type,
        where property: String,
        equals value: any Sendable
    ) throws -> Int {
        let query = """
            MATCH (n:\(type.modelName) {\(property): $value})
            RETURN count(n)
            """

        let result = try raw(query, bindings: ["value": value])
        return try result.mapFirstRequired(to: Int.self, at: 0)
    }
}

// MARK: - Relationship Helpers
public extension GraphContext {
    
    /// Create a relationship between two nodes
    func createRelationship<From: GraphNodeModel, To: GraphNodeModel, Edge: _KuzuGraphModel>(
        from source: From,
        to target: To,
        edge: Edge
    ) throws {
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

        _ = try raw(query, bindings: bindings)
    }

    /// Create multiple relationships in a single batch operation using UNWIND
    func createRelationships<From: GraphNodeModel & Encodable, To: GraphNodeModel & Encodable, Edge: _KuzuGraphModel & Encodable>(
        relationships: [(from: From, to: To, edge: Edge)]
    ) throws {
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

        _ = try raw(query, bindings: ["items": items])
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
