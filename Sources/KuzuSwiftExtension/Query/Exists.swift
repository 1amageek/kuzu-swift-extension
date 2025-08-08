import Foundation

/// Represents EXISTS patterns for subqueries in predicates
public struct Exists {
    let pattern: ExistsPattern
    
    internal init(pattern: ExistsPattern) {
        self.pattern = pattern
    }
    
    /// Pattern types for EXISTS
    public enum ExistsPattern {
        case node(type: String, alias: String, predicate: Predicate?)
        case edge(type: String, from: String, to: String, alias: String, predicate: Predicate?)
        case relationship(from: (Any.Type, String), via: Any.Type, to: (Any.Type, String), edgeAlias: String)
        case path(from: String, to: String, edgeType: String?, minHops: Int?, maxHops: Int?)
        case pattern(MatchPattern)
        case subquery(Query)
        case custom(String)
    }
    
    // MARK: - Node EXISTS
    
    /// Creates an EXISTS check for a node
    public static func node<T: _KuzuGraphModel>(
        _ type: T.Type,
        alias: String? = nil,
        where predicate: Predicate? = nil
    ) -> Exists {
        let nodeAlias = alias ?? String(describing: type).lowercased()
        return Exists(pattern: .node(
            type: String(describing: type),
            alias: nodeAlias,
            predicate: predicate
        ))
    }
    
    // MARK: - Edge EXISTS
    
    /// Creates an EXISTS check for an edge
    public static func edge<E: _KuzuGraphModel>(
        _ type: E.Type,
        from: String,
        to: String,
        alias: String? = nil,
        where predicate: Predicate? = nil
    ) -> Exists {
        let edgeAlias = alias ?? String(describing: type).lowercased()
        return Exists(pattern: .edge(
            type: String(describing: type),
            from: from,
            to: to,
            alias: edgeAlias,
            predicate: predicate
        ))
    }
    
    /// Creates an EXISTS check for a relationship
    public static func relationship<From: _KuzuGraphModel, To: _KuzuGraphModel, Edge: _KuzuGraphModel>(
        from: (From.Type, String),
        via edge: Edge.Type,
        to: (To.Type, String),
        edgeAlias: String? = nil,
        where predicate: Predicate? = nil
    ) -> Exists {
        let edgeAlias = edgeAlias ?? String(describing: edge).lowercased()
        return Exists(pattern: .edge(
            type: String(describing: edge),
            from: from.1,
            to: to.1,
            alias: edgeAlias,
            predicate: predicate
        ))
    }
    
    // MARK: - Path EXISTS
    
    /// Creates an EXISTS check for a path
    public static func path(
        from: String,
        to: String,
        via edgeType: String? = nil,
        hops: ClosedRange<Int>? = nil
    ) -> Exists {
        Exists(pattern: .path(
            from: from,
            to: to,
            edgeType: edgeType,
            minHops: hops?.lowerBound,
            maxHops: hops?.upperBound
        ))
    }
    
    /// Creates an EXISTS check for a typed path
    public static func path<From: _KuzuGraphModel, To: _KuzuGraphModel, Edge: _KuzuGraphModel>(
        from: (From.Type, String),
        to: (To.Type, String),
        via edge: Edge.Type,
        hops: ClosedRange<Int>? = nil
    ) -> Exists {
        Exists(pattern: .path(
            from: from.1,
            to: to.1,
            edgeType: String(describing: edge),
            minHops: hops?.lowerBound,
            maxHops: hops?.upperBound
        ))
    }
    
    // MARK: - Pattern EXISTS
    
    /// Creates an EXISTS check from a match pattern
    public static func pattern(_ pattern: MatchPattern) -> Exists {
        Exists(pattern: .pattern(pattern))
    }
    
    // MARK: - Subquery EXISTS
    
    /// Creates an EXISTS check with a subquery
    public static func subquery(@QueryBuilder _ builder: () -> [QueryComponent]) -> Exists {
        Exists(pattern: .subquery(Query(components: builder())))
    }
    
    // MARK: - Cypher Generation
    
    /// Generates the Cypher representation of the EXISTS pattern
    func toCypher() throws -> CypherFragment {
        switch pattern {
        case .node(let type, let alias, let predicate):
            var query = "EXISTS { MATCH (\(alias):\(type))"
            var parameters: [String: any Sendable] = [:]
            
            if let predicate = predicate {
                let predicateCypher = try predicate.toCypher()
                query += " WHERE \(predicateCypher.query)"
                parameters = predicateCypher.parameters
            }
            query += " }"
            
            return CypherFragment(query: query, parameters: parameters)
            
        case .edge(let type, let from, let to, let alias, let predicate):
            var query = "EXISTS { MATCH (\(from))-[\(alias):\(type)]->(\(to))"
            var parameters: [String: any Sendable] = [:]
            
            if let predicate = predicate {
                let predicateCypher = try predicate.toCypher()
                query += " WHERE \(predicateCypher.query)"
                parameters = predicateCypher.parameters
            }
            query += " }"
            
            return CypherFragment(query: query, parameters: parameters)
            
        case .path(let from, let to, let edgeType, let minHops, let maxHops):
            var edgePattern = ""
            if let edgeType = edgeType {
                edgePattern = ":\(edgeType)"
            }
            
            if let minHops = minHops, let maxHops = maxHops {
                edgePattern += "*\(minHops)..\(maxHops)"
            } else if let minHops = minHops {
                edgePattern += "*\(minHops).."
            } else if let maxHops = maxHops {
                edgePattern += "*..\(maxHops)"
            }
            
            let query = "EXISTS { MATCH (\(from))-[\(edgePattern)]-(\(to)) }"
            return CypherFragment(query: query)
            
        case .pattern(let matchPattern):
            let patternCypher = try matchPattern.toCypher()
            let query = "EXISTS { MATCH \(patternCypher.query) }"
            return CypherFragment(query: query, parameters: patternCypher.parameters)
            
        case .subquery(let subquery):
            let subqueryCypher = try CypherCompiler.compile(subquery)
            let query = "EXISTS { \(subqueryCypher.query) }"
            return CypherFragment(query: query, parameters: subqueryCypher.parameters)
            
        case .relationship(let from, let via, let to, let edgeAlias):
            let fromType = String(describing: from.0)
            let toType = String(describing: to.0)
            let viaType = String(describing: via)
            let query = "EXISTS { MATCH (\(from.1):\(fromType))-[\(edgeAlias):\(viaType)]->(\(to.1):\(toType)) }"
            return CypherFragment(query: query)
            
        case .custom(let customPattern):
            let query = "EXISTS { \(customPattern) }"
            return CypherFragment(query: query)
        }
    }
}

// MARK: - Predicate Integration

public extension Predicate {
    /// Creates a predicate that checks if a pattern exists
    static func exists(_ exists: Exists) -> Predicate {
        Predicate(node: .exists(exists))
    }
    
    /// Creates a predicate that checks if a pattern does not exist
    static func notExists(_ exists: Exists) -> Predicate {
        Predicate(node: .not(.exists(exists)))
    }
}


// MARK: - Convenience Methods

public extension Exists {
    /// Creates an EXISTS check for a node with inline property checks
    static func node<T: _KuzuGraphModel, V>(
        _ type: T.Type,
        alias: String? = nil,
        where keyPath: KeyPath<T, V>,
        equals value: V
    ) -> Exists where V: Sendable {
        let nodeAlias = alias ?? String(describing: type).lowercased()
        let propertyPath = PropertyPath(keyPath: keyPath, alias: nodeAlias)
        let predicate = propertyPath == value
        
        return node(type, alias: nodeAlias, where: predicate)
    }
    
    /// Creates an EXISTS check for connected nodes
    static func connected<From: _KuzuGraphModel, To: _KuzuGraphModel>(
        from: (From.Type, String),
        to: (To.Type, String),
        maxHops: Int = 3
    ) -> Exists {
        path(from: from.1, to: to.1, hops: 1...maxHops)
    }
    
    /// Creates an EXISTS check for any outgoing edge from a node
    static func hasOutgoingEdge(
        from nodeAlias: String,
        ofType edgeType: String? = nil
    ) -> Exists {
        let edgePattern = edgeType.map { ":\($0)" } ?? ""
        let pattern = MatchPattern.custom("(\(nodeAlias))-[\(edgePattern)]->()")
        return Exists(pattern: .pattern(pattern))
    }
    
    /// Creates an EXISTS check for any incoming edge to a node
    static func hasIncomingEdge(
        to nodeAlias: String,
        ofType edgeType: String? = nil
    ) -> Exists {
        let edgePattern = edgeType.map { ":\($0)" } ?? ""
        let pattern = MatchPattern.custom("()-[\(edgePattern)]->(\(nodeAlias))")
        return Exists(pattern: .pattern(pattern))
    }
}

// MARK: - Complex EXISTS Patterns

public struct ExistsBuilder {
    private var patterns: [Exists] = []
    
    public init() {}
    
    /// Adds a node existence check
    public mutating func node<T: _KuzuGraphModel>(
        _ type: T.Type,
        alias: String? = nil,
        where predicate: Predicate? = nil
    ) {
        patterns.append(Exists.node(type, alias: alias, where: predicate))
    }
    
    /// Adds an edge existence check
    public mutating func edge<E: _KuzuGraphModel>(
        _ type: E.Type,
        from: String,
        to: String,
        alias: String? = nil,
        where predicate: Predicate? = nil
    ) {
        patterns.append(Exists.edge(type, from: from, to: to, alias: alias, where: predicate))
    }
    
    /// Builds a combined EXISTS predicate with AND logic
    public func buildAnd() -> Predicate {
        guard !patterns.isEmpty else {
            return Predicate(node: .literal(true))
        }
        
        let predicates = patterns.map { Predicate.exists($0) }
        return predicates.reduce(predicates[0]) { $0 && $1 }
    }
    
    /// Builds a combined EXISTS predicate with OR logic
    public func buildOr() -> Predicate {
        guard !patterns.isEmpty else {
            return Predicate(node: .literal(false))
        }
        
        let predicates = patterns.map { Predicate.exists($0) }
        return predicates.reduce(predicates[0]) { $0 || $1 }
    }
}