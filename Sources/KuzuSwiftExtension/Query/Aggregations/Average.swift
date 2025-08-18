import Foundation

/// Average aggregation function
public struct Average<Model: GraphNodeModel, Value: Numeric>: QueryComponent {
    public typealias Result = Double
    
    let nodeRef: NodeReference<Model>
    let keyPath: KeyPath<Model, Value>
    let alias: String?
    
    /// Create an average aggregation
    public init(nodeRef: NodeReference<Model>, keyPath: KeyPath<Model, Value>) {
        self.nodeRef = nodeRef
        self.keyPath = keyPath
        self.alias = nil
    }
    
    /// Create an average aggregation with custom alias
    public init(nodeRef: NodeReference<Model>, keyPath: KeyPath<Model, Value>, as alias: String) {
        self.nodeRef = nodeRef
        self.keyPath = keyPath
        self.alias = alias
    }
    
    public func toCypher() throws -> CypherFragment {
        // First get the MATCH clause from nodeRef
        let nodeFragment = try nodeRef.toCypher()
        
        // Extract property name
        let propertyName = String(describing: keyPath).components(separatedBy: ".").last ?? ""
        let avgExpression = "AVG(\(nodeRef.alias).\(propertyName))"
        
        let returnClause = alias != nil ? "RETURN \(avgExpression) AS \(alias!)" : "RETURN \(avgExpression)"
        
        return CypherFragment(
            query: "\(nodeFragment.query) \(returnClause)",
            parameters: nodeFragment.parameters
        )
    }
    
    /// Add an alias to this average
    public func `as`(_ alias: String) -> Average {
        Average(nodeRef: nodeRef, keyPath: keyPath, as: alias)
    }
}

/// Minimum aggregation function
public struct Min<Model: GraphNodeModel, Value: Comparable>: QueryComponent {
    public typealias Result = Value
    
    let nodeRef: NodeReference<Model>
    let keyPath: KeyPath<Model, Value>
    let alias: String?
    
    /// Create a min aggregation
    public init(nodeRef: NodeReference<Model>, keyPath: KeyPath<Model, Value>) {
        self.nodeRef = nodeRef
        self.keyPath = keyPath
        self.alias = nil
    }
    
    /// Create a min aggregation with custom alias
    public init(nodeRef: NodeReference<Model>, keyPath: KeyPath<Model, Value>, as alias: String) {
        self.nodeRef = nodeRef
        self.keyPath = keyPath
        self.alias = alias
    }
    
    public func toCypher() throws -> CypherFragment {
        let propertyName = String(describing: keyPath).components(separatedBy: ".").last ?? ""
        let minExpression = "MIN(\(nodeRef.alias).\(propertyName))"
        
        if let alias = alias {
            return CypherFragment(query: "\(minExpression) AS \(alias)")
        } else {
            return CypherFragment(query: minExpression)
        }
    }
    
    /// Add an alias to this min
    public func `as`(_ alias: String) -> Min {
        Min(nodeRef: nodeRef, keyPath: keyPath, as: alias)
    }
}

/// Maximum aggregation function
public struct Max<Model: GraphNodeModel, Value: Comparable>: QueryComponent {
    public typealias Result = Value
    
    let nodeRef: NodeReference<Model>
    let keyPath: KeyPath<Model, Value>
    let alias: String?
    
    /// Create a max aggregation
    public init(nodeRef: NodeReference<Model>, keyPath: KeyPath<Model, Value>) {
        self.nodeRef = nodeRef
        self.keyPath = keyPath
        self.alias = nil
    }
    
    /// Create a max aggregation with custom alias
    public init(nodeRef: NodeReference<Model>, keyPath: KeyPath<Model, Value>, as alias: String) {
        self.nodeRef = nodeRef
        self.keyPath = keyPath
        self.alias = alias
    }
    
    public func toCypher() throws -> CypherFragment {
        let propertyName = String(describing: keyPath).components(separatedBy: ".").last ?? ""
        let maxExpression = "MAX(\(nodeRef.alias).\(propertyName))"
        
        if let alias = alias {
            return CypherFragment(query: "\(maxExpression) AS \(alias)")
        } else {
            return CypherFragment(query: maxExpression)
        }
    }
    
    /// Add an alias to this max
    public func `as`(_ alias: String) -> Max {
        Max(nodeRef: nodeRef, keyPath: keyPath, as: alias)
    }
}