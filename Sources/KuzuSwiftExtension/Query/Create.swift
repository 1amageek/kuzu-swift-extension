import Foundation

public struct Create: QueryComponent {
    let node: NodePattern?
    let edge: EdgePattern?
    
    private init(node: NodePattern? = nil, edge: EdgePattern? = nil) {
        self.node = node
        self.edge = edge
    }
    
    public static func node<T: _KuzuGraphModel>(
        _ type: T.Type,
        alias: String? = nil,
        properties: [String: any Sendable] = [:]
    ) -> Create {
        let pattern = NodePattern(
            type: String(describing: type),
            alias: alias ?? String(describing: type).lowercased(),
            properties: properties
        )
        return Create(node: pattern)
    }
    
    public static func node<T: _KuzuGraphModel & Encodable>(
        _ instance: T,
        alias: String? = nil
    ) throws -> Create {
        let encoder = KuzuEncoder()
        let properties = try encoder.encode(instance)
        let pattern = NodePattern(
            type: String(describing: T.self),
            alias: alias ?? String(describing: T.self).lowercased(),
            properties: properties
        )
        return Create(node: pattern)
    }
    
    public static func edge<T: _KuzuGraphModel>(
        _ type: T.Type,
        from: String,
        to: String,
        alias: String? = nil,
        properties: [String: any Sendable] = [:]
    ) -> Create {
        let pattern = EdgePattern(
            type: String(describing: type),
            from: from,
            to: to,
            alias: alias ?? String(describing: type).lowercased(),
            properties: properties
        )
        return Create(edge: pattern)
    }
    
    public func toCypher() throws -> CypherFragment {
        if let node = node {
            return try node.toCypher(prefix: "CREATE")
        } else if let edge = edge {
            return try edge.toCypher(prefix: "CREATE")
        } else {
            throw QueryError.compilationFailed(query: "CREATE", reason: "No node or edge pattern specified")
        }
    }
    
}

struct NodePattern {
    let type: String
    let alias: String
    let properties: [String: any Sendable]
    
    func toCypher(prefix: String) throws -> CypherFragment {
        var params: [String: any Sendable] = [:]
        var propStrings: [String] = []
        
        for (key, value) in properties {
            let paramName = ParameterNameGenerator.generateSemantic(alias: alias, property: key)
            params[paramName] = value
            propStrings.append("\(key): $\(paramName)")
        }
        
        let propsClause = propStrings.isEmpty ? "" : " {\(propStrings.joined(separator: ", "))}"
        let query = "\(prefix) (\(alias):\(type)\(propsClause))"
        
        return CypherFragment(query: query, parameters: params)
    }
}

struct EdgePattern {
    let type: String
    let from: String
    let to: String
    let alias: String
    let properties: [String: any Sendable]
    
    func toCypher(prefix: String) throws -> CypherFragment {
        var params: [String: any Sendable] = [:]
        var propStrings: [String] = []
        
        for (key, value) in properties {
            let paramName = ParameterNameGenerator.generateSemantic(alias: alias, property: key)
            params[paramName] = value
            propStrings.append("\(key): $\(paramName)")
        }
        
        let propsClause = propStrings.isEmpty ? "" : " {\(propStrings.joined(separator: ", "))}"
        let query = "\(prefix) (\(from))-[\(alias):\(type)\(propsClause)]->(\(to))"
        
        return CypherFragment(query: query, parameters: params)
    }
}