import Foundation

/// Standalone CREATE component for query DSL
public struct Create: QueryComponent {
    public typealias Result = Void
    public var isReturnable: Bool { false }
    
    private let fragment: CypherFragment
    
    private init(fragment: CypherFragment) {
        self.fragment = fragment
    }
    
    /// Create a node of the specified type
    public static func node<Model: GraphNodeModel>(_ type: Model.Type, properties: [String: any Sendable] = [:]) -> Create {
        let alias = AliasGenerator.generate(for: Model.self)
        let typeName = String(describing: Model.self)
        var parameters: [String: any Sendable] = [:]
        var propStrings: [String] = []
        
        // Handle timestamp properties specially
        let columns = Model._kuzuColumns
        
        for (key, value) in properties {
            let paramName = OptimizedParameterGenerator.semantic(alias: alias, property: key)
            parameters[paramName] = value
            
            // Check if this is a timestamp property
            let columnInfo = columns.first { $0.columnName == key }
            let columnType = columnInfo?.type ?? ""
            
            if columnType == "TIMESTAMP" {
                propStrings.append("\(key): timestamp($\(paramName))")
            } else {
                propStrings.append("\(key): $\(paramName)")
            }
        }
        
        let propsClause = propStrings.isEmpty ? "" : " {\(propStrings.joined(separator: ", "))}"
        let query = "CREATE (\(alias):\(typeName)\(propsClause))"
        
        return Create(fragment: CypherFragment(query: query, parameters: parameters))
    }
    
    /// Create a node from an instance
    public static func node<Model: GraphNodeModel & Encodable>(_ instance: Model) throws -> Create {
        let encoder = KuzuEncoder()
        let properties = try encoder.encode(instance)
        return node(Model.self, properties: properties)
    }
    
    /// Create an edge between two nodes
    public static func edge<Edge: GraphEdgeModel, From: GraphNodeModel, To: GraphNodeModel>(
        _ type: Edge.Type,
        from: NodeReference<From>,
        to: NodeReference<To>,
        properties: [String: any Sendable] = [:]
    ) -> Create {
        let alias = AliasGenerator.generate(for: Edge.self)
        let typeName = String(describing: Edge.self)
        var parameters: [String: any Sendable] = [:]
        var propStrings: [String] = []
        
        // Handle timestamp properties specially
        let columns = Edge._kuzuColumns
        
        for (key, value) in properties {
            let paramName = OptimizedParameterGenerator.semantic(alias: alias, property: key)
            parameters[paramName] = value
            
            // Check if this is a timestamp property
            let columnInfo = columns.first { $0.columnName == key }
            let columnType = columnInfo?.type ?? ""
            
            if columnType == "TIMESTAMP" {
                propStrings.append("\(key): timestamp($\(paramName))")
            } else {
                propStrings.append("\(key): $\(paramName)")
            }
        }
        
        let propsClause = propStrings.isEmpty ? "" : " {\(propStrings.joined(separator: ", "))}"
        let query = "CREATE (\(from.alias))-[\(alias):\(typeName)\(propsClause)]->(\(to.alias))"
        
        return Create(fragment: CypherFragment(query: query, parameters: parameters))
    }
    
    /// Create an edge from an instance
    public static func edge<Edge: GraphEdgeModel & Encodable, From: GraphNodeModel, To: GraphNodeModel>(
        _ instance: Edge,
        from: NodeReference<From>,
        to: NodeReference<To>
    ) throws -> Create {
        let encoder = KuzuEncoder()
        let properties = try encoder.encode(instance)
        return edge(Edge.self, from: from, to: to, properties: properties)
    }
    
    public func toCypher() throws -> CypherFragment {
        fragment
    }
}