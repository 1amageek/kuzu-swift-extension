import Foundation

/// Represents a MERGE clause in a Cypher query (upsert operation)
public struct Merge: QueryComponent {
    let pattern: MergePattern
    let onCreate: [PropertyAssignment]
    let onMatch: [PropertyAssignment]
    
    private init(
        pattern: MergePattern,
        onCreate: [PropertyAssignment] = [],
        onMatch: [PropertyAssignment] = []
    ) {
        self.pattern = pattern
        self.onCreate = onCreate
        self.onMatch = onMatch
    }
    
    /// Creates a MERGE clause for a node
    public static func node<T: _KuzuGraphModel>(
        _ type: T.Type,
        alias: String? = nil,
        matchProperties: [String: any Sendable] = [:]
    ) -> Merge {
        let nodeAlias = alias ?? String(describing: type).lowercased()
        let pattern = MergePattern.node(
            type: String(describing: type),
            alias: nodeAlias,
            properties: matchProperties
        )
        return Merge(pattern: pattern)
    }
    
    /// Creates a MERGE clause for an edge
    public static func edge<T: _KuzuGraphModel>(
        _ type: T.Type,
        from: String,
        to: String,
        alias: String? = nil,
        matchProperties: [String: any Sendable] = [:]
    ) -> Merge {
        let edgeAlias = alias ?? String(describing: type).lowercased()
        let pattern = MergePattern.edge(
            type: String(describing: type),
            from: from,
            to: to,
            alias: edgeAlias,
            properties: matchProperties
        )
        return Merge(pattern: pattern)
    }
    
    /// Adds ON CREATE SET clause
    public func onCreate(_ assignments: PropertyAssignment...) -> Merge {
        Merge(
            pattern: pattern,
            onCreate: onCreate + assignments,
            onMatch: onMatch
        )
    }
    
    /// Adds ON CREATE SET clause with property values
    public func onCreate(set properties: [String: any Sendable]) -> Merge {
        let alias = pattern.alias
        let assignments = properties.map { key, value in
            PropertyReference(alias: alias, property: key).set(to: value)
        }
        return Merge(
            pattern: pattern,
            onCreate: onCreate + assignments,
            onMatch: onMatch
        )
    }
    
    /// Adds ON MATCH SET clause
    public func onMatch(_ assignments: PropertyAssignment...) -> Merge {
        Merge(
            pattern: pattern,
            onCreate: onCreate,
            onMatch: onMatch + assignments
        )
    }
    
    /// Adds ON MATCH SET clause with property values
    public func onMatch(set properties: [String: any Sendable]) -> Merge {
        let alias = pattern.alias
        let assignments = properties.map { key, value in
            PropertyReference(alias: alias, property: key).set(to: value)
        }
        return Merge(
            pattern: pattern,
            onCreate: onCreate,
            onMatch: onMatch + assignments
        )
    }
    
    public func toCypher() throws -> CypherFragment {
        var parameters: [String: any Sendable] = [:]
        var query = "MERGE "
        
        // Add the pattern
        let patternCypher = try pattern.toCypher()
        query += patternCypher.query
        for (key, value) in patternCypher.parameters {
            parameters[key] = value
        }
        
        // Add ON CREATE SET if present
        if !onCreate.isEmpty {
            var setClauses: [String] = []
            for assignment in onCreate {
                let fragment = try assignment.toCypher()
                setClauses.append(fragment.query)
                for (key, value) in fragment.parameters {
                    parameters[key] = value
                }
            }
            query += " ON CREATE SET " + setClauses.joined(separator: ", ")
        }
        
        // Add ON MATCH SET if present
        if !onMatch.isEmpty {
            var setClauses: [String] = []
            for assignment in onMatch {
                let fragment = try assignment.toCypher()
                setClauses.append(fragment.query)
                for (key, value) in fragment.parameters {
                    parameters[key] = value
                }
            }
            query += " ON MATCH SET " + setClauses.joined(separator: ", ")
        }
        
        return CypherFragment(query: query, parameters: parameters)
    }
}

/// Pattern for MERGE operations
public enum MergePattern {
    case node(type: String, alias: String, properties: [String: any Sendable])
    case edge(type: String, from: String, to: String, alias: String, properties: [String: any Sendable])
    
    var alias: String {
        switch self {
        case .node(_, let alias, _):
            return alias
        case .edge(_, _, _, let alias, _):
            return alias
        }
    }
    
    func toCypher() throws -> CypherFragment {
        switch self {
        case .node(let type, let alias, let properties):
            if properties.isEmpty {
                return CypherFragment(query: "(\(alias):\(type))")
            } else {
                var params: [String: any Sendable] = [:]
                var propStrings: [String] = []
                
                for (key, value) in properties {
                    let paramName = ParameterNameGenerator.generateSemantic(alias: alias, property: key)
                    params[paramName] = value
                    propStrings.append("\(key): $\(paramName)")
                }
                
                let propsClause = " {\(propStrings.joined(separator: ", "))}"
                return CypherFragment(
                    query: "(\(alias):\(type)\(propsClause))",
                    parameters: params
                )
            }
            
        case .edge(let type, let from, let to, let alias, let properties):
            if properties.isEmpty {
                return CypherFragment(query: "(\(from))-[\(alias):\(type)]->(\(to))")
            } else {
                var params: [String: any Sendable] = [:]
                var propStrings: [String] = []
                
                for (key, value) in properties {
                    let paramName = ParameterNameGenerator.generateSemantic(alias: alias, property: key)
                    params[paramName] = value
                    propStrings.append("\(key): $\(paramName)")
                }
                
                let propsClause = " {\(propStrings.joined(separator: ", "))}"
                return CypherFragment(
                    query: "(\(from))-[\(alias):\(type)\(propsClause)]->(\(to))",
                    parameters: params
                )
            }
        }
    }
}

// MARK: - Convenience Builder

/// Builder for complex MERGE operations
public struct MergeBuilder {
    /// Creates a MERGE for ensuring a unique node exists
    public static func ensureNode<T: _KuzuGraphModel>(
        _ type: T.Type,
        matching: [String: any Sendable],
        onCreate: [String: any Sendable] = [:],
        onMatch: [String: any Sendable] = [:]
    ) -> Merge {
        var merge = Merge.node(type, matchProperties: matching)
        
        if !onCreate.isEmpty {
            merge = merge.onCreate(set: onCreate)
        }
        
        if !onMatch.isEmpty {
            merge = merge.onMatch(set: onMatch)
        }
        
        return merge
    }
    
    /// Creates a MERGE for ensuring a unique edge exists
    public static func ensureEdge<T: _KuzuGraphModel>(
        _ type: T.Type,
        from: String,
        to: String,
        matching: [String: any Sendable] = [:],
        onCreate: [String: any Sendable] = [:],
        onMatch: [String: any Sendable] = [:]
    ) -> Merge {
        var merge = Merge.edge(type, from: from, to: to, matchProperties: matching)
        
        if !onCreate.isEmpty {
            merge = merge.onCreate(set: onCreate)
        }
        
        if !onMatch.isEmpty {
            merge = merge.onMatch(set: onMatch)
        }
        
        return merge
    }
}