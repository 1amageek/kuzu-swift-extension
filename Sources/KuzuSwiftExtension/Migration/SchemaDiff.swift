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
        // Compare nodes
        let currentNodeNames = Set(current.nodes.map { $0.name })
        let targetNodeNames = Set(target.nodes.map { $0.name })
        
        let addedNodeNames = targetNodeNames.subtracting(currentNodeNames)
        let droppedNodeNames = currentNodeNames.subtracting(targetNodeNames)
        let commonNodeNames = currentNodeNames.intersection(targetNodeNames)
        
        // Use partitioned(by:) from Swift Algorithms for efficient separation
        let (addedNodes, _) = target.nodes.partitioned(by: { !addedNodeNames.contains($0.name) })
        let (droppedNodes, _) = current.nodes.partitioned(by: { !droppedNodeNames.contains($0.name) })
        
        var modifiedNodes: [(current: NodeSchema, target: NodeSchema)] = []
        for name in commonNodeNames {
            if let currentNode = current.nodes.first(where: { $0.name == name }),
               let targetNode = target.nodes.first(where: { $0.name == name }) {
                if !isEqual(currentNode, targetNode) {
                    modifiedNodes.append((currentNode, targetNode))
                }
            }
        }
        
        // Compare edges
        let currentEdgeNames = Set(current.edges.map { $0.name })
        let targetEdgeNames = Set(target.edges.map { $0.name })
        
        let addedEdgeNames = targetEdgeNames.subtracting(currentEdgeNames)
        let droppedEdgeNames = currentEdgeNames.subtracting(targetEdgeNames)
        let commonEdgeNames = currentEdgeNames.intersection(targetEdgeNames)
        
        // Use partitioned(by:) for edges as well
        let (addedEdges, _) = target.edges.partitioned(by: { !addedEdgeNames.contains($0.name) })
        let (droppedEdges, _) = current.edges.partitioned(by: { !droppedEdgeNames.contains($0.name) })
        
        var modifiedEdges: [(current: EdgeSchema, target: EdgeSchema)] = []
        for name in commonEdgeNames {
            if let currentEdge = current.edges.first(where: { $0.name == name }),
               let targetEdge = target.edges.first(where: { $0.name == name }) {
                if !isEqual(currentEdge, targetEdge) {
                    modifiedEdges.append((currentEdge, targetEdge))
                }
            }
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
        
        for (col1, col2) in zip(node1.columns, node2.columns) {
            if col1.name != col2.name ||
               col1.type != col2.type ||
               Set(col1.constraints) != Set(col2.constraints) {
                return false
            }
        }
        
        return true
    }
    
    private static func isEqual(_ edge1: EdgeSchema, _ edge2: EdgeSchema) -> Bool {
        guard edge1.name == edge2.name else { return false }
        guard edge1.from == edge2.from else { return false }
        guard edge1.to == edge2.to else { return false }
        guard edge1.columns.count == edge2.columns.count else { return false }
        
        for (col1, col2) in zip(edge1.columns, edge2.columns) {
            if col1.name != col2.name ||
               col1.type != col2.type ||
               Set(col1.constraints) != Set(col2.constraints) {
                return false
            }
        }
        
        return true
    }
}