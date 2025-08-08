import Foundation

/// Represents a NOT EXISTS pattern for checking non-existence of subgraphs
public struct NotExists {
    let pattern: Exists.ExistsPattern
    
    private init(pattern: Exists.ExistsPattern) {
        self.pattern = pattern
    }
    
    // MARK: - Node Patterns
    
    /// Creates a NOT EXISTS check for a node
    public static func node<T: _KuzuGraphModel>(
        _ type: T.Type,
        alias: String? = nil,
        where predicate: Predicate? = nil
    ) -> NotExists {
        let nodeAlias = alias ?? String(describing: type).lowercased()
        let pattern = Exists.ExistsPattern.node(
            type: String(describing: type),
            alias: nodeAlias,
            predicate: predicate
        )
        return NotExists(pattern: pattern)
    }
    
    // MARK: - Edge Patterns
    
    /// Creates a NOT EXISTS check for an edge
    public static func edge<T: _KuzuGraphModel>(
        _ type: T.Type,
        from: String,
        to: String,
        alias: String? = nil
    ) -> NotExists {
        let edgeAlias = alias ?? String(describing: type).lowercased()
        let pattern = Exists.ExistsPattern.edge(
            type: String(describing: type),
            from: from,
            to: to,
            alias: edgeAlias,
            predicate: nil
        )
        return NotExists(pattern: pattern)
    }
    
    /// Creates a NOT EXISTS check for a typed edge with nodes
    public static func relationship<From: _KuzuGraphModel, To: _KuzuGraphModel, Edge: _KuzuGraphModel>(
        from: (From.Type, String),
        via edge: Edge.Type,
        to: (To.Type, String),
        edgeAlias: String? = nil
    ) -> NotExists {
        let edgeAliasResolved = edgeAlias ?? String(describing: edge).lowercased()
        let pattern = Exists.ExistsPattern.relationship(
            from: from,
            via: edge,
            to: to,
            edgeAlias: edgeAliasResolved
        )
        return NotExists(pattern: pattern)
    }
    
    // MARK: - Path Patterns
    
    /// Creates a NOT EXISTS check for a path pattern
    public static func path(
        from: String,
        to: String,
        via edgeType: String? = nil,
        hops: ClosedRange<Int>? = nil
    ) -> NotExists {
        let pattern = Exists.ExistsPattern.path(
            from: from,
            to: to,
            edgeType: edgeType,
            minHops: hops?.lowerBound,
            maxHops: hops?.upperBound
        )
        return NotExists(pattern: pattern)
    }
    
    /// Creates a NOT EXISTS check for a typed path pattern
    public static func path<From: _KuzuGraphModel, To: _KuzuGraphModel, Edge: _KuzuGraphModel>(
        from: (From.Type, String),
        to: (To.Type, String),
        via edge: Edge.Type,
        hops: ClosedRange<Int>? = nil
    ) -> NotExists {
        let pattern = Exists.ExistsPattern.path(
            from: from.1,
            to: to.1,
            edgeType: String(describing: edge),
            minHops: hops?.lowerBound,
            maxHops: hops?.upperBound
        )
        return NotExists(pattern: pattern)
    }
    
    // MARK: - Custom Patterns
    
    /// Creates a NOT EXISTS check with a custom pattern
    public static func custom(_ pattern: String) -> NotExists {
        NotExists(pattern: Exists.ExistsPattern.custom(pattern))
    }
    
    // MARK: - Cypher Compilation
    
    /// Converts to Cypher fragment
    func toCypher() throws -> CypherFragment {
        // Create a temporary Exists to get the cypher
        let exists = Exists(pattern: pattern)
        let existsCypher = try exists.toCypher()
        return CypherFragment(
            query: "NOT \(existsCypher.query)",
            parameters: existsCypher.parameters
        )
    }
}

// MARK: - Predicate Integration

public extension Predicate {
    /// Creates a NOT EXISTS predicate
    static func notExists(_ notExists: NotExists) -> Predicate {
        do {
            let cypher = try notExists.toCypher()
            return Predicate(node: .custom(cypher.query, parameters: cypher.parameters))
        } catch {
            // Fallback to a basic false predicate if compilation fails
            return Predicate(node: .literal(false))
        }
    }
    
    /// Convenience method for checking non-existence of edges
    static func hasNoEdge<T: _KuzuGraphModel>(
        _ type: T.Type,
        from: String,
        to: String? = nil
    ) -> Predicate {
        let targetAlias = to ?? "_"
        return .notExists(
            NotExists.edge(type, from: from, to: targetAlias)
        )
    }
    
    /// Convenience method for checking non-existence of incoming edges
    static func hasNoIncomingEdge<T: _KuzuGraphModel>(
        _ type: T.Type,
        to: String,
        from: String? = nil
    ) -> Predicate {
        let sourceAlias = from ?? "_"
        return .notExists(
            NotExists.edge(type, from: sourceAlias, to: to)
        )
    }
}

// MARK: - Query Builder Support

// Note: Match and OptionalMatch use separate WHERE clauses, not built-in methods.
// Use Where.init(predicate) as a separate query component after Match/OptionalMatch.