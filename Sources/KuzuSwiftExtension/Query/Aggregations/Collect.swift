import Foundation

/// Collect aggregation function
public struct Collect<Model: GraphNodeModel>: QueryComponent {
    public typealias Result = [Model]
    
    let nodeRef: NodeReference<Model>
    let alias: String?
    
    /// Create a collect aggregation
    public init(nodeRef: NodeReference<Model>) {
        self.nodeRef = nodeRef
        self.alias = nil
    }
    
    /// Create a collect aggregation with custom alias
    public init(nodeRef: NodeReference<Model>, as alias: String) {
        self.nodeRef = nodeRef
        self.alias = alias
    }
    
    public func toCypher() throws -> CypherFragment {
        let collectExpression = "COLLECT(\(nodeRef.alias))"
        
        if let alias = alias {
            return CypherFragment(query: "\(collectExpression) AS \(alias)")
        } else {
            return CypherFragment(query: collectExpression)
        }
    }
    
    /// Add an alias to this collect
    public func `as`(_ alias: String) -> Collect {
        Collect(nodeRef: nodeRef, as: alias)
    }
}