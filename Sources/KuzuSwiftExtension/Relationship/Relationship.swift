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
    // Note: createRelationship is implemented in GraphModel.swift
    
    /// Convenience method for connecting nodes without properties
    public func connect(
        from: any GraphNodeModel,
        to: any GraphNodeModel,
        edgeType: any GraphEdgeModel.Type
    ) async throws {
        guard let fromId = extractId(from: from),
              let toId = extractId(from: to) else {
            throw GraphError.missingIdentifier
        }
        
        let fromTypeName = String(describing: type(of: from))
        let toTypeName = String(describing: type(of: to))
        let edgeTypeName = String(describing: edgeType)
        
        let cypher = """
            MATCH (from:\(fromTypeName) {id: $fromId}), (to:\(toTypeName) {id: $toId})
            CREATE (from)-[:\(edgeTypeName)]->(to)
            """
        
        _ = try await raw(cypher, bindings: [
            "fromId": convertToSendable(fromId),
            "toId": convertToSendable(toId)
        ])
    }
    
    // MARK: - Edge Queries
    
    /// Finds edges between two nodes
    public func findEdges<Edge: GraphEdgeModel & Decodable>(
        from: any GraphNodeModel,
        to: any GraphNodeModel,
        edgeType: Edge.Type,
        direction: Direction = .outgoing
    ) async throws -> [Edge] {
        guard let fromId = extractId(from: from),
              let toId = extractId(from: to) else {
            throw GraphError.missingIdentifier
        }
        
        let fromTypeName = String(describing: type(of: from))
        let toTypeName = String(describing: type(of: to))
        let edgeTypeName = String(describing: edgeType)
        
        let pattern = switch direction {
        case .outgoing: "(from)-[e:\(edgeTypeName)]->(to)"
        case .incoming: "(from)<-[e:\(edgeTypeName)]-(to)"
        case .both: "(from)-[e:\(edgeTypeName)]-(to)"
        }
        
        let cypher = """
            MATCH (from:\(fromTypeName) {id: $fromId}), (to:\(toTypeName) {id: $toId})
            MATCH \(pattern)
            RETURN e
            """
        
        let result = try await raw(cypher, bindings: [
            "fromId": convertToSendable(fromId),
            "toId": convertToSendable(toId)
        ])
        
        return try result.map(to: Edge.self)
    }
    
    /// Checks if a relationship exists between two nodes
    public func hasRelationship(
        from: any GraphNodeModel,
        to: any GraphNodeModel,
        edgeType: any GraphEdgeModel.Type,
        direction: Direction = .outgoing
    ) async throws -> Bool {
        guard let fromId = extractId(from: from),
              let toId = extractId(from: to) else {
            throw GraphError.missingIdentifier
        }
        
        let fromTypeName = String(describing: type(of: from))
        let toTypeName = String(describing: type(of: to))
        let edgeTypeName = String(describing: edgeType)
        
        let pattern = switch direction {
        case .outgoing: "(from)-[:\(edgeTypeName)]->(to)"
        case .incoming: "(from)<-[:\(edgeTypeName)]-(to)"
        case .both: "(from)-[:\(edgeTypeName)]-(to)"
        }
        
        let cypher = """
            MATCH (from:\(fromTypeName) {id: $fromId}), (to:\(toTypeName) {id: $toId})
            RETURN EXISTS { MATCH \(pattern) } as exists
            """
        
        let result = try await raw(cypher, bindings: [
            "fromId": convertToSendable(fromId),
            "toId": convertToSendable(toId)
        ])
        
        guard let row = try result.mapFirst(),
              let exists = row["exists"] as? Bool else {
            return false
        }
        
        return exists
    }
    
    // MARK: - Node Traversal
    
    /// Finds all nodes connected to the given node via the specified edge type
    public func findConnectedNodes<Node: GraphNodeModel & Decodable, Edge: GraphEdgeModel>(
        from node: any GraphNodeModel,
        via edgeType: Edge.Type,
        direction: Direction = .outgoing,
        nodeType: Node.Type
    ) async throws -> [Node] {
        guard let nodeId = extractId(from: node) else {
            throw GraphError.missingIdentifier
        }
        
        let sourceTypeName = String(describing: type(of: node))
        let targetTypeName = String(describing: nodeType)
        let edgeTypeName = String(describing: edgeType)
        
        let pattern = switch direction {
        case .outgoing: "(source)-[:\(edgeTypeName)]->(target:\(targetTypeName))"
        case .incoming: "(source)<-[:\(edgeTypeName)]-(target:\(targetTypeName))"
        case .both: "(source)-[:\(edgeTypeName)]-(target:\(targetTypeName))"
        }
        
        let cypher = """
            MATCH (source:\(sourceTypeName) {id: $nodeId})
            MATCH \(pattern)
            RETURN target
            """
        
        let result = try await raw(cypher, bindings: [
            "nodeId": convertToSendable(nodeId)
        ])
        
        return try result.map(to: Node.self)
    }
    
    /// Counts nodes connected to the given node
    public func countConnectedNodes<Edge: GraphEdgeModel>(
        from node: any GraphNodeModel,
        via edgeType: Edge.Type,
        direction: Direction = .outgoing
    ) async throws -> Int64 {
        guard let nodeId = extractId(from: node) else {
            throw GraphError.missingIdentifier
        }
        
        let nodeTypeName = String(describing: type(of: node))
        let edgeTypeName = String(describing: edgeType)
        
        let pattern = switch direction {
        case .outgoing: "(n)-[:\(edgeTypeName)]->()"
        case .incoming: "(n)<-[:\(edgeTypeName)]-()"
        case .both: "(n)-[:\(edgeTypeName)]-()"
        }
        
        let cypher = """
            MATCH (n:\(nodeTypeName) {id: $nodeId})
            MATCH \(pattern)
            RETURN COUNT(*) as count
            """
        
        let result = try await raw(cypher, bindings: [
            "nodeId": convertToSendable(nodeId)
        ])
        
        guard let row = try result.mapFirst(),
              let count = row["count"] as? Int64 else {
            return 0
        }
        
        return count
    }
    
    // MARK: - Helper Methods
    
    /// Extracts the ID from a node
    private func extractId(from node: any GraphNodeModel) -> Any? {
        let mirror = Mirror(reflecting: node)
        for child in mirror.children {
            if child.label == "id" || child.label == "_id" {
                return child.value
            }
        }
        return nil
    }
    
    /// Converts a value to Sendable
    private func convertToSendable(_ value: Any) -> any Sendable {
        switch value {
        case let sendable as any Sendable:
            return sendable
        default:
            return String(describing: value)
        }
    }
}

// MARK: - TransactionalGraphContext Extensions

extension TransactionalGraphContext {
    
    /// Creates a relationship within a transaction
    public func createRelationship<From: GraphNodeModel, To: GraphNodeModel, Edge: _KuzuGraphModel>(
        from: From,
        to: To,
        edge: Edge
    ) async throws {
        // Implementation would need to be in the transaction context file
        // to avoid circular dependencies
        fatalError("createRelationship should be called directly on TransactionalGraphContext")
    }
}