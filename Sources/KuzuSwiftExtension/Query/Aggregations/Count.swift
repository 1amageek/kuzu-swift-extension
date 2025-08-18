import Foundation

/// Count aggregation function
public struct Count<Model: GraphNodeModel>: QueryComponent {
    public typealias Result = Int64
    
    let nodeRef: NodeReference<Model>?
    let alias: String?
    
    /// Count all nodes
    public init() {
        self.nodeRef = nil
        self.alias = nil
    }
    
    /// Count specific nodes
    public init(nodeRef: NodeReference<Model>) {
        self.nodeRef = nodeRef
        self.alias = nil
    }
    
    /// Count with custom alias
    public init(nodeRef: NodeReference<Model>? = nil, as alias: String) {
        self.nodeRef = nodeRef
        self.alias = alias
    }
    
    public func toCypher() throws -> CypherFragment {
        var fragments: [String] = []
        var parameters: [String: any Sendable] = [:]
        
        // First add the MATCH clause from nodeRef if present
        if let nodeRef = nodeRef {
            let nodeFragment = try nodeRef.toCypher()
            fragments.append(nodeFragment.query)
            parameters = nodeFragment.parameters
        }
        
        // Then add the RETURN COUNT clause
        let countExpression: String
        if let nodeRef = nodeRef {
            countExpression = "COUNT(\(nodeRef.alias))"
        } else {
            countExpression = "COUNT(*)"
        }
        
        let returnClause = alias != nil ? "RETURN \(countExpression) AS \(alias!)" : "RETURN \(countExpression)"
        fragments.append(returnClause)
        
        return CypherFragment(
            query: fragments.joined(separator: " "),
            parameters: parameters
        )
    }
    
    /// Add an alias to this count
    public func `as`(_ alias: String) -> Count {
        Count(nodeRef: nodeRef, as: alias)
    }
}