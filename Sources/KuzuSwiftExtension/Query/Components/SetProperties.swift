import Foundation

/// Standalone SET component for query DSL
public struct SetProperties: QueryComponent {
    public typealias Result = Void
    public var isReturnable: Bool { false }
    
    private let fragment: CypherFragment
    
    private init(fragment: CypherFragment) {
        self.fragment = fragment
    }
    
    /// Set properties on a node
    public static func node<Model: GraphNodeModel>(_ nodeRef: NodeReference<Model>, properties: [String: any Sendable]) -> SetProperties {
        var parameters: [String: any Sendable] = [:]
        var propStrings: [String] = []
        
        // Handle timestamp properties specially
        let columns = Model._kuzuColumns
        
        for (key, value) in properties {
            let paramName = OptimizedParameterGenerator.semantic(alias: nodeRef.alias, property: key)
            parameters[paramName] = value

            // Check if this is a timestamp property
            let columnInfo = columns.first { $0.columnName == key }
            let columnType = columnInfo?.type ?? ""

            if columnType == "TIMESTAMP" {
                propStrings.append("\(nodeRef.alias).\(key) = timestamp($\(paramName))")
            } else {
                propStrings.append("\(nodeRef.alias).\(key) = $\(paramName)")
            }
        }
        
        let query = "SET \(propStrings.joined(separator: ", "))"
        return SetProperties(fragment: CypherFragment(query: query, parameters: parameters))
    }
    
    /// Set a single property on a node using KeyPath
    public static func node<Model: GraphNodeModel, Value: Sendable>(
        _ nodeRef: NodeReference<Model>,
        _ keyPath: KeyPath<Model, Value>,
        to value: Value
    ) -> SetProperties {
        let columnName = KeyPathUtilities.columnName(from: keyPath)
        return node(nodeRef, properties: [columnName: value])
    }
    
    /// Set properties on an edge
    public static func edge<Model: GraphEdgeModel>(_ edgeRef: EdgeReference<Model>, properties: [String: any Sendable]) -> SetProperties {
        var parameters: [String: any Sendable] = [:]
        var propStrings: [String] = []
        
        // Handle timestamp properties specially
        let columns = Model._kuzuColumns
        
        for (key, value) in properties {
            let paramName = OptimizedParameterGenerator.semantic(alias: edgeRef.alias, property: key)
            parameters[paramName] = value

            // Check if this is a timestamp property
            let columnInfo = columns.first { $0.columnName == key }
            let columnType = columnInfo?.type ?? ""

            if columnType == "TIMESTAMP" {
                propStrings.append("\(edgeRef.alias).\(key) = timestamp($\(paramName))")
            } else {
                propStrings.append("\(edgeRef.alias).\(key) = $\(paramName)")
            }
        }
        
        let query = "SET \(propStrings.joined(separator: ", "))"
        return SetProperties(fragment: CypherFragment(query: query, parameters: parameters))
    }
    
    /// Set labels on a node (for multi-label support)
    public static func labels<Model: GraphNodeModel>(_ nodeRef: NodeReference<Model>, _ labels: String...) -> SetProperties {
        let labelString = labels.map { ":\($0)" }.joined()
        let query = "SET \(nodeRef.alias)\(labelString)"
        return SetProperties(fragment: CypherFragment(query: query))
    }
    
    /// Remove property by setting to NULL
    public static func removeProperty<Model: GraphNodeModel>(_ nodeRef: NodeReference<Model>, _ property: String) -> SetProperties {
        let query = "SET \(nodeRef.alias).\(property) = NULL"
        return SetProperties(fragment: CypherFragment(query: query))
    }
    
    /// Remove property using KeyPath
    public static func removeProperty<Model: GraphNodeModel, Value>(
        _ nodeRef: NodeReference<Model>,
        _ keyPath: KeyPath<Model, Value>
    ) -> SetProperties {
        let propertyName = String(describing: keyPath).components(separatedBy: ".").last ?? ""
        return removeProperty(nodeRef, propertyName)
    }
    
    public func toCypher() throws -> CypherFragment {
        fragment
    }
}