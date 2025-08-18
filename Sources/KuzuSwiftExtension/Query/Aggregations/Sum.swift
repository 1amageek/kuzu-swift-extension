import Foundation

/// Sum aggregation function
public struct Sum<Model: GraphNodeModel, Value: Numeric>: QueryComponent {
    public typealias Result = Value
    
    let nodeRef: NodeReference<Model>
    let keyPath: KeyPath<Model, Value>
    let alias: String?
    
    /// Calculate sum of a property
    public init(_ nodeRef: NodeReference<Model>, keyPath: KeyPath<Model, Value>) {
        self.nodeRef = nodeRef
        self.keyPath = keyPath
        self.alias = nil
    }
    
    /// Calculate sum with custom alias
    public init(_ nodeRef: NodeReference<Model>, keyPath: KeyPath<Model, Value>, as alias: String) {
        self.nodeRef = nodeRef
        self.keyPath = keyPath
        self.alias = alias
    }
    
    public func toCypher() throws -> CypherFragment {
        let propertyName = KeyPathUtilities.propertyName(from: keyPath, on: Model.self)
        let sumExpression = "SUM(\(nodeRef.alias).\(propertyName))"
        
        if let alias = alias {
            return CypherFragment(query: "\(sumExpression) AS \(alias)")
        } else {
            return CypherFragment(query: sumExpression)
        }
    }
    
    /// Add an alias to this sum
    public func `as`(_ alias: String) -> Sum {
        Sum(nodeRef, keyPath: keyPath, as: alias)
    }
}