import Foundation

/// Direction of graph traversal
public enum Direction: Sendable {
    case outgoing  // ->
    case incoming  // <-
    case both      // -
    
    var cypherSymbol: String {
        switch self {
        case .outgoing: return "->"
        case .incoming: return "<-"
        case .both: return "-"
        }
    }
}

// MARK: - GraphContext Relationship Extensions

extension GraphContext {
    
    // MARK: - Edge Creation
    
    /// Creates a relationship (edge) between two nodes
    /// - Parameters:
    ///   - edge: The edge instance to create
    ///   - from: The source node (must have an ID property)
    ///   - to: The target node (must have an ID property)
    /// - Returns: The created edge
    public func connect<E: GraphEdgeModel & Encodable>(
        _ edge: E,
        from: any GraphNodeModel,
        to: any GraphNodeModel
    ) async throws {
        // Extract IDs from the nodes
        guard let fromId = extractId(from: from),
              let toId = extractId(from: to) else {
            throw GraphError.missingIdentifier
        }
        
        // Get type names
        let fromType = String(describing: type(of: from))
        let toType = String(describing: type(of: to))
        let edgeType = String(describing: E.self)
        
        // Encode edge properties
        let encoder = KuzuEncoder()
        let edgeProperties = try encoder.encode(edge)
        
        // Build the Cypher query with edge properties inline
        // Handle TIMESTAMP properties specially
        var propAssignments: [String] = []
        for (key, value) in edgeProperties {
            // Check if this is likely a Date/TIMESTAMP property (encoded as String)
            // Look for specific patterns that indicate Date/timestamp fields, but avoid false positives like "metadata"
            let keyLower = key.lowercased()
            let isTimestampField = value is String && (
                keyLower.hasSuffix("at") || keyLower.hasSuffix("date") || keyLower.hasSuffix("time") ||
                keyLower.hasPrefix("created") || keyLower.hasPrefix("updated") || keyLower.hasPrefix("deleted") ||
                keyLower.contains("timestamp") || keyLower == "date" || keyLower == "time"
            )
            
            if isTimestampField {
                // Wrap in TIMESTAMP() function for Kuzu
                propAssignments.append("\(key): TIMESTAMP($\(key))")
            } else {
                propAssignments.append("\(key): $\(key)")
            }
        }
        let propsString = edgeProperties.isEmpty ? "" : " {" + propAssignments.joined(separator: ", ") + "}"
        
        let cypher = """
            MATCH (from:\(fromType) {id: $fromId}), (to:\(toType) {id: $toId})
            CREATE (from)-[e:\(edgeType)\(propsString)]->(to)
            RETURN e
            """
        
        var bindings: [String: any Sendable] = [
            "fromId": convertToSendable(fromId),
            "toId": convertToSendable(toId)
        ]
        
        // Add edge properties to bindings (without e_ prefix)
        for (key, value) in edgeProperties {
            bindings[key] = value
        }
        
        _ = try await raw(cypher, bindings: bindings)
        
        // Original query DSL implementation - needs KeyPath fix
        /*
        let query = try await self.query {
            Match.node(type(of: from), alias: "from")
            Where.condition(property("from", "id") == fromId)
            
            Match.node(type(of: to), alias: "to")
            Where.condition(property("to", "id") == toId)
            
            Create.edge(
                E.self,
                from: "from",
                to: "to",
                alias: "e",
                properties: edgeProperties
            )
            
            Return.node("e")
        }
        */
    }
    
    /// Creates a simple relationship without properties
    public func connect<E: GraphEdgeModel>(
        _ edgeType: E.Type,
        from: any GraphNodeModel,
        to: any GraphNodeModel
    ) async throws {
        // Extract IDs from the nodes
        guard let fromId = extractId(from: from),
              let toId = extractId(from: to) else {
            throw GraphError.missingIdentifier
        }
        
        // Get type names
        let fromType = String(describing: type(of: from))
        let toType = String(describing: type(of: to))
        let edgeTypeName = String(describing: E.self)
        
        // Build and execute the query
        let cypher = """
            MATCH (from:\(fromType) {id: $fromId}), (to:\(toType) {id: $toId})
            CREATE (from)-[e:\(edgeTypeName)]->(to)
            RETURN e
            """
        
        _ = try await raw(cypher, bindings: [
            "fromId": convertToSendable(fromId),
            "toId": convertToSendable(toId)
        ])
    }
    
    // MARK: - Relationship Queries
    
    /// Finds nodes related to the given node via a specific edge type
    /// - Parameters:
    ///   - node: The source node
    ///   - edgeType: The type of edge to traverse
    ///   - direction: The direction to traverse (outgoing, incoming, or both)
    /// - Returns: Array of related nodes
    public func related<N: GraphNodeModel & Decodable, E: GraphEdgeModel>(
        to node: any GraphNodeModel,
        via edgeType: E.Type,
        direction: Direction = .outgoing
    ) async throws -> [N] {
        guard let nodeId = extractId(from: node) else {
            throw GraphError.missingIdentifier
        }
        
        let nodeType = String(describing: type(of: node))
        let edgeTypeName = String(describing: E.self)
        let targetType = String(describing: N.self)
        
        // Build the appropriate pattern based on direction
        let pattern: String
        switch direction {
        case .outgoing:
            pattern = "(n:\(nodeType) {id: $nodeId})-[:\(edgeTypeName)]->(target:\(targetType))"
        case .incoming:
            pattern = "(n:\(nodeType) {id: $nodeId})<-[:\(edgeTypeName)]-(target:\(targetType))"
        case .both:
            pattern = "(n:\(nodeType) {id: $nodeId})-[:\(edgeTypeName)]-(target:\(targetType))"
        }
        
        let cypher = """
            MATCH \(pattern)
            RETURN target
            """
        
        let result = try await raw(cypher, bindings: ["nodeId": convertToSendable(nodeId)])
        return try result.decode(N.self, column: "target")
    }
    
    /// Finds nodes and their connecting edges
    public func relatedWithEdges<N: GraphNodeModel & Decodable, E: GraphEdgeModel & Decodable>(
        to node: any GraphNodeModel,
        via edgeType: E.Type,
        direction: Direction = .outgoing
    ) async throws -> [(node: N, edge: E)] {
        guard let nodeId = extractId(from: node) else {
            throw GraphError.missingIdentifier
        }
        
        let nodeType = String(describing: type(of: node))
        let edgeTypeName = String(describing: E.self)
        let targetType = String(describing: N.self)
        
        // Build the appropriate pattern based on direction
        let pattern: String
        switch direction {
        case .outgoing:
            pattern = "(n:\(nodeType) {id: $nodeId})-[e:\(edgeTypeName)]->(target:\(targetType))"
        case .incoming:
            pattern = "(n:\(nodeType) {id: $nodeId})<-[e:\(edgeTypeName)]-(target:\(targetType))"
        case .both:
            pattern = "(n:\(nodeType) {id: $nodeId})-[e:\(edgeTypeName)]-(target:\(targetType))"
        }
        
        let cypher = """
            MATCH \(pattern)
            RETURN target, e
            """
        
        let result = try await raw(cypher, bindings: ["nodeId": convertToSendable(nodeId)])
        return try result.decodePairs(nodeType: N.self, edgeType: E.self, nodeColumn: "target", edgeColumn: "e")
    }
    
    // MARK: - Relationship Deletion
    
    /// Disconnects two nodes by removing their relationship
    public func disconnect<E: GraphEdgeModel>(
        from: any GraphNodeModel,
        to: any GraphNodeModel,
        via edgeType: E.Type
    ) async throws {
        guard let fromId = extractId(from: from),
              let toId = extractId(from: to) else {
            throw GraphError.missingIdentifier
        }
        
        let fromType = String(describing: type(of: from))
        let toType = String(describing: type(of: to))
        let edgeTypeName = String(describing: E.self)
        
        let cypher = """
            MATCH (from:\(fromType) {id: $fromId})-[e:\(edgeTypeName)]->(to:\(toType) {id: $toId})
            DELETE e
            """
        
        _ = try await raw(cypher, bindings: [
            "fromId": convertToSendable(fromId),
            "toId": convertToSendable(toId)
        ])
    }
    
    /// Disconnects all relationships of a specific type from a node
    public func disconnectAll<E: GraphEdgeModel>(
        from node: any GraphNodeModel,
        edgeType: E.Type,
        direction: Direction = .both
    ) async throws {
        guard let nodeId = extractId(from: node) else {
            throw GraphError.missingIdentifier
        }
        
        let nodeType = String(describing: type(of: node))
        let edgeTypeName = String(describing: E.self)
        
        // Build the appropriate pattern based on direction
        let pattern: String
        switch direction {
        case .outgoing:
            pattern = "(n:\(nodeType) {id: $nodeId})-[e:\(edgeTypeName)]->()"
        case .incoming:
            pattern = "(n:\(nodeType) {id: $nodeId})<-[e:\(edgeTypeName)]-()"
        case .both:
            pattern = "(n:\(nodeType) {id: $nodeId})-[e:\(edgeTypeName)]-()"
        }
        
        let cypher = """
            MATCH \(pattern)
            DELETE e
            """
        
        _ = try await raw(cypher, bindings: ["nodeId": convertToSendable(nodeId)])
    }
    
    // MARK: - Helper Methods
    
    /// Converts any value to a Sendable type
    private func convertToSendable(_ value: Any) -> any Sendable {
        if let uuid = value as? UUID {
            return uuid.uuidString
        } else if let string = value as? String {
            return string
        } else if let int = value as? Int {
            return int
        } else if let int64 = value as? Int64 {
            return int64
        } else if let double = value as? Double {
            return double
        } else if let bool = value as? Bool {
            return bool
        } else if let date = value as? Date {
            return date.timeIntervalSince1970
        } else {
            // Fallback to string representation
            return String(describing: value)
        }
    }
    
    /// Extracts the ID value from a GraphNodeModel
    private func extractId(from node: any GraphNodeModel) -> Any? {
        // Try to get the 'id' property using Mirror reflection
        let mirror = Mirror(reflecting: node)
        
        for child in mirror.children {
            if child.label == "id" || child.label == "_id" {
                // Handle wrapped property values
                // We can't cast to Sendable protocol, so return as Any and let caller handle it
                let wrappedValue = child.value
                
                // Check if it's a property wrapper by looking for wrappedValue
                let propertyMirror = Mirror(reflecting: child.value)
                for prop in propertyMirror.children {
                    if prop.label == "wrappedValue" {
                        return prop.value as Any
                    }
                }
                
                return wrappedValue as Any
            }
        }
        
        return nil
    }
    
    // MARK: - Path Queries
    
    /// Finds the shortest path between two nodes
    public func shortestPath(
        from: any GraphNodeModel,
        to: any GraphNodeModel,
        maxHops: Int? = nil
    ) async throws -> [[String: any Sendable]]? {
        guard let fromId = extractId(from: from),
              let toId = extractId(from: to) else {
            throw GraphError.missingIdentifier
        }
        
        let fromType = String(describing: type(of: from))
        let toType = String(describing: type(of: to))
        
        let hopsClause = maxHops.map { "1..\($0)" } ?? ""
        let cypher = """
            MATCH p = shortestPath((from:\(fromType) {id: $fromId})-[*\(hopsClause)]-(to:\(toType) {id: $toId}))
            RETURN p
            """
        
        let result = try await raw(cypher, bindings: [
            "fromId": convertToSendable(fromId),
            "toId": convertToSendable(toId)
        ])
        
        if let row = try? result.mapFirstRow() {
            // Convert to Sendable dictionary
            var sendableRow: [String: any Sendable] = [:]
            for (key, value) in row {
                sendableRow[key] = convertToSendable(value)
            }
            return [sendableRow]
        }
        return nil
    }
    
    /// Checks if two nodes are connected
    public func areConnected(
        _ node1: any GraphNodeModel,
        _ node2: any GraphNodeModel,
        via edgeType: (any GraphEdgeModel.Type)? = nil,
        maxHops: Int = 1
    ) async throws -> Bool {
        guard let id1 = extractId(from: node1),
              let id2 = extractId(from: node2) else {
            throw GraphError.missingIdentifier
        }
        
        let type1 = String(describing: type(of: node1))
        let type2 = String(describing: type(of: node2))
        
        let edgePattern: String
        if let edgeType = edgeType {
            edgePattern = ":\(String(describing: edgeType))"
        } else {
            edgePattern = ""
        }
        
        let hopsPattern = maxHops == 1 ? "" : "*1..\(maxHops)"
        
        let cypher = """
            MATCH (n1:\(type1) {id: $id1}), (n2:\(type2) {id: $id2})
            RETURN EXISTS { (n1)-[\(edgePattern)\(hopsPattern)]-(n2) } as connected
            """
        
        let result = try await raw(cypher, bindings: [
            "id1": convertToSendable(id1),
            "id2": convertToSendable(id2)
        ])
        
        return try result.mapFirst(to: Bool.self) ?? false
    }
}

// MARK: - Relationship Builder

/// A builder for creating complex relationship queries
public struct RelationshipBuilder {
    private let context: GraphContext
    
    init(context: GraphContext) {
        self.context = context
    }
    
    /// Creates multiple relationships in a single transaction
    public func createMany<E: GraphEdgeModel & Encodable & Sendable>(
        _ edges: [(from: any GraphNodeModel & Sendable, edge: E, to: any GraphNodeModel & Sendable)]
    ) async throws {
        // Implementation would batch create relationships
        for (from, edge, to) in edges {
            try await context.connect(edge, from: from, to: to)
        }
    }
}