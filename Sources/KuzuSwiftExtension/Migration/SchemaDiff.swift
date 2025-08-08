import Foundation
import Algorithms

public struct SchemaDiff {
    public let addedNodes: [NodeSchema]
    public let droppedNodes: [NodeSchema]
    public let modifiedNodes: [(current: NodeSchema, target: NodeSchema)]
    
    public let addedEdges: [EdgeSchema]
    public let droppedEdges: [EdgeSchema]
    public let modifiedEdges: [(current: EdgeSchema, target: EdgeSchema)]
    
    public var isEmpty: Bool {
        addedNodes.isEmpty &&
        droppedNodes.isEmpty &&
        modifiedNodes.isEmpty &&
        addedEdges.isEmpty &&
        droppedEdges.isEmpty &&
        modifiedEdges.isEmpty
    }
    
    public static func compare(current: GraphSchema, target: GraphSchema) -> SchemaDiff {
        // Create dictionaries for O(1) lookup
        let currentNodesByName = Dictionary(uniqueKeysWithValues: current.nodes.map { ($0.name, $0) })
        let targetNodesByName = Dictionary(uniqueKeysWithValues: target.nodes.map { ($0.name, $0) })
        
        // Use swift-algorithms for efficient set operations
        let currentNodeNames = Set(currentNodesByName.keys)
        let targetNodeNames = Set(targetNodesByName.keys)
        
        // Find added, dropped, and common nodes
        let addedNodeNames = targetNodeNames.subtracting(currentNodeNames)
        let droppedNodeNames = currentNodeNames.subtracting(targetNodeNames)
        let commonNodeNames = currentNodeNames.intersection(targetNodeNames)
        
        // Use compactMap for efficient filtering and mapping
        let addedNodes = addedNodeNames.compactMap { targetNodesByName[$0] }
        let droppedNodes = droppedNodeNames.compactMap { currentNodesByName[$0] }
        
        // Use swift-algorithms' product for comparing pairs efficiently
        let modifiedNodes = commonNodeNames.compactMap { name -> (current: NodeSchema, target: NodeSchema)? in
            guard let currentNode = currentNodesByName[name],
                  let targetNode = targetNodesByName[name],
                  !isEqual(currentNode, targetNode) else { return nil }
            return (currentNode, targetNode)
        }
        
        // Same approach for edges
        let currentEdgesByName = Dictionary(uniqueKeysWithValues: current.edges.map { ($0.name, $0) })
        let targetEdgesByName = Dictionary(uniqueKeysWithValues: target.edges.map { ($0.name, $0) })
        
        let currentEdgeNames = Set(currentEdgesByName.keys)
        let targetEdgeNames = Set(targetEdgesByName.keys)
        
        let addedEdgeNames = targetEdgeNames.subtracting(currentEdgeNames)
        let droppedEdgeNames = currentEdgeNames.subtracting(targetEdgeNames)
        let commonEdgeNames = currentEdgeNames.intersection(targetEdgeNames)
        
        let addedEdges = addedEdgeNames.compactMap { targetEdgesByName[$0] }
        let droppedEdges = droppedEdgeNames.compactMap { currentEdgesByName[$0] }
        
        let modifiedEdges = commonEdgeNames.compactMap { name -> (current: EdgeSchema, target: EdgeSchema)? in
            guard let currentEdge = currentEdgesByName[name],
                  let targetEdge = targetEdgesByName[name],
                  !isEqual(currentEdge, targetEdge) else { return nil }
            return (currentEdge, targetEdge)
        }
        
        return SchemaDiff(
            addedNodes: addedNodes,
            droppedNodes: droppedNodes,
            modifiedNodes: modifiedNodes,
            addedEdges: addedEdges,
            droppedEdges: droppedEdges,
            modifiedEdges: modifiedEdges
        )
    }
    
    private static func isEqual(_ node1: NodeSchema, _ node2: NodeSchema) -> Bool {
        guard node1.name == node2.name else { return false }
        guard node1.columns.count == node2.columns.count else { return false }
        
        // Use swift-algorithms for efficient comparison
        let columnsMatch = zip(node1.columns, node2.columns).allSatisfy { col1, col2 in
            col1.name == col2.name &&
            col1.type == col2.type &&
            Set(col1.constraints) == Set(col2.constraints)
        }
        
        return columnsMatch
    }
    
    /// Check if column types have changed (for migration validation)
    public static func hasTypeChanges(current: NodeSchema, target: NodeSchema) -> Bool {
        let currentColumnsByName = Dictionary(uniqueKeysWithValues: current.columns.map { ($0.name, $0) })
        let targetColumnsByName = Dictionary(uniqueKeysWithValues: target.columns.map { ($0.name, $0) })
        
        // Use swift-algorithms to check if any column has type changes
        return currentColumnsByName.contains { columnName, currentColumn in
            if let targetColumn = targetColumnsByName[columnName] {
                return currentColumn.type != targetColumn.type
            }
            return false
        }
    }
    
    private static func isEqual(_ edge1: EdgeSchema, _ edge2: EdgeSchema) -> Bool {
        guard edge1.name == edge2.name else { return false }
        guard edge1.from == edge2.from else { return false }
        guard edge1.to == edge2.to else { return false }
        guard edge1.columns.count == edge2.columns.count else { return false }
        
        // Use swift-algorithms for efficient comparison
        let columnsMatch = zip(edge1.columns, edge2.columns).allSatisfy { col1, col2 in
            col1.name == col2.name &&
            col1.type == col2.type &&
            Set(col1.constraints) == Set(col2.constraints)
        }
        
        return columnsMatch
    }
    
    /// Check if edge column types have changed (for migration validation)
    public static func hasTypeChanges(current: EdgeSchema, target: EdgeSchema) -> Bool {
        let currentColumnsByName = Dictionary(uniqueKeysWithValues: current.columns.map { ($0.name, $0) })
        let targetColumnsByName = Dictionary(uniqueKeysWithValues: target.columns.map { ($0.name, $0) })
        
        // Use swift-algorithms to check if any column has type changes
        return currentColumnsByName.contains { columnName, currentColumn in
            if let targetColumn = targetColumnsByName[columnName] {
                return currentColumn.type != targetColumn.type
            }
            return false
        }
    }
}

// MARK: - Advanced Diffing with swift-algorithms

public extension SchemaDiff {
    /// Generate a detailed migration plan using efficient algorithms
    func generateMigrationPlan() -> [MigrationStep] {
        var steps: [MigrationStep] = []
        
        // Use chunks to batch operations efficiently
        let nodeDropBatch = droppedNodes.chunks(ofCount: 10)
        for batch in nodeDropBatch {
            steps.append(.dropNodes(Array(batch)))
        }
        
        let edgeDropBatch = droppedEdges.chunks(ofCount: 10)
        for batch in edgeDropBatch {
            steps.append(.dropEdges(Array(batch)))
        }
        
        // Add nodes before edges (edges depend on nodes)
        let nodeAddBatch = addedNodes.chunks(ofCount: 10)
        for batch in nodeAddBatch {
            steps.append(.addNodes(Array(batch)))
        }
        
        // Modify existing nodes
        for (current, target) in modifiedNodes {
            steps.append(.modifyNode(from: current, to: target))
        }
        
        // Add edges after nodes exist
        let edgeAddBatch = addedEdges.chunks(ofCount: 10)
        for batch in edgeAddBatch {
            steps.append(.addEdges(Array(batch)))
        }
        
        // Modify existing edges
        for (current, target) in modifiedEdges {
            steps.append(.modifyEdge(from: current, to: target))
        }
        
        return steps
    }
    
    /// Find column differences using efficient set operations
    static func columnDifferences(
        current: [Column],
        target: [Column]
    ) -> (added: [Column], dropped: [Column], modified: [(current: Column, target: Column)]) {
        let currentByName = Dictionary(uniqueKeysWithValues: current.map { ($0.name, $0) })
        let targetByName = Dictionary(uniqueKeysWithValues: target.map { ($0.name, $0) })
        
        let currentNames = Set(currentByName.keys)
        let targetNames = Set(targetByName.keys)
        
        let added = targetNames.subtracting(currentNames).compactMap { targetByName[$0] }
        let dropped = currentNames.subtracting(targetNames).compactMap { currentByName[$0] }
        
        let modified = currentNames.intersection(targetNames).compactMap { name -> (current: Column, target: Column)? in
            guard let currentCol = currentByName[name],
                  let targetCol = targetByName[name],
                  currentCol.type != targetCol.type || Set(currentCol.constraints) != Set(targetCol.constraints)
            else { return nil }
            return (currentCol, targetCol)
        }
        
        return (added, dropped, modified)
    }
}

/// Migration steps that can be generated from a diff
public enum MigrationStep {
    case addNodes([NodeSchema])
    case dropNodes([NodeSchema])
    case modifyNode(from: NodeSchema, to: NodeSchema)
    case addEdges([EdgeSchema])
    case dropEdges([EdgeSchema])
    case modifyEdge(from: EdgeSchema, to: EdgeSchema)
}