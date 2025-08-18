import Foundation

/// Standalone DELETE component for query DSL
public struct Delete: QueryComponent {
    public typealias Result = Void
    public var isReturnable: Bool { false }
    
    private let fragment: CypherFragment
    private let detach: Bool
    
    private init(fragment: CypherFragment, detach: Bool = false) {
        self.fragment = fragment
        self.detach = detach
    }
    
    /// Delete a node
    public static func node<Model: GraphNodeModel>(_ nodeRef: NodeReference<Model>, detach: Bool = false) -> Delete {
        let deleteClause = detach ? "DETACH DELETE" : "DELETE"
        let query = "\(deleteClause) \(nodeRef.alias)"
        return Delete(fragment: CypherFragment(query: query), detach: detach)
    }
    
    /// Delete multiple nodes
    public static func nodes<Model: GraphNodeModel>(_ nodeRefs: NodeReference<Model>..., detach: Bool = false) -> Delete {
        let deleteClause = detach ? "DETACH DELETE" : "DELETE"
        let aliases = nodeRefs.map { $0.alias }.joined(separator: ", ")
        let query = "\(deleteClause) \(aliases)"
        return Delete(fragment: CypherFragment(query: query), detach: detach)
    }
    
    /// Delete an edge
    public static func edge<Model: GraphEdgeModel>(_ edgeRef: EdgeReference<Model>) -> Delete {
        let query = "DELETE \(edgeRef.alias)"
        return Delete(fragment: CypherFragment(query: query))
    }
    
    /// Delete multiple edges
    public static func edges<Model: GraphEdgeModel>(_ edgeRefs: EdgeReference<Model>...) -> Delete {
        let aliases = edgeRefs.map { $0.alias }.joined(separator: ", ")
        let query = "DELETE \(aliases)"
        return Delete(fragment: CypherFragment(query: query))
    }
    
    /// Delete everything matched (use with caution)
    public static func all(detach: Bool = true) -> Delete {
        let deleteClause = detach ? "DETACH DELETE" : "DELETE"
        let query = "\(deleteClause) *"
        return Delete(fragment: CypherFragment(query: query), detach: detach)
    }
    
    public func toCypher() throws -> CypherFragment {
        fragment
    }
}