import Foundation

/// Represents an OPTIONAL MATCH clause in a Cypher query
public struct OptionalMatch: QueryComponent {
    let patterns: [MatchPattern]
    let predicate: Predicate?
    
    private init(patterns: [MatchPattern], predicate: Predicate? = nil) {
        self.patterns = patterns
        self.predicate = predicate
    }
    
    // MARK: - Node Matching
    
    /// Creates an OPTIONAL MATCH for a node
    public static func node<T: _KuzuGraphModel>(
        _ type: T.Type,
        alias: String? = nil
    ) -> OptionalMatch {
        let nodeAlias = alias ?? String(describing: type).lowercased()
        let pattern = MatchPattern.node(
            type: String(describing: type),
            alias: nodeAlias,
            predicate: nil
        )
        return OptionalMatch.pattern(pattern)
    }
    
    /// Creates an OPTIONAL MATCH for a node with inline predicate
    public static func node<T: _KuzuGraphModel>(
        _ type: T.Type,
        alias: String? = nil,
        where predicate: Predicate
    ) -> OptionalMatch {
        let nodeAlias = alias ?? String(describing: type).lowercased()
        let pattern = MatchPattern.node(
            type: String(describing: type),
            alias: nodeAlias,
            predicate: predicate
        )
        return OptionalMatch.pattern(pattern)
    }
    
    // MARK: - Edge Matching
    
    /// Creates an OPTIONAL MATCH for an edge
    public static func edge<T: _KuzuGraphModel>(
        _ type: T.Type,
        alias: String? = nil
    ) -> OptionalEdgeBuilder<T> {
        OptionalEdgeBuilder(type: type, alias: alias)
    }
    
    /// Creates an OPTIONAL MATCH from patterns
    public static func pattern(_ patterns: MatchPattern...) -> OptionalMatch {
        // Using an internal factory method to handle the variadic parameters
        return createWithPatterns(patterns)
    }
    
    // Internal factory method to create with array of patterns
    private static func createWithPatterns(_ patterns: [MatchPattern], predicate: Predicate? = nil) -> OptionalMatch {
        OptionalMatch(patterns: patterns, predicate: predicate)
    }
    
    // MARK: - Modifiers
    
    /// Adds a WHERE clause to the OPTIONAL MATCH
    public func `where`(_ predicate: Predicate) -> OptionalMatch {
        OptionalMatch.createWithPatterns(self.patterns, predicate: predicate)
    }
    
    /// Adds another pattern to the OPTIONAL MATCH
    public func and(_ pattern: MatchPattern) -> OptionalMatch {
        var newPatterns = self.patterns
        newPatterns.append(pattern)
        return OptionalMatch.createWithPatterns(newPatterns, predicate: self.predicate)
    }
    
    /// Adds another OPTIONAL MATCH pattern
    public func and<T: _KuzuGraphModel>(_ type: T.Type, alias: String? = nil) -> OptionalMatch {
        let nodeAlias = alias ?? String(describing: type).lowercased()
        let pattern = MatchPattern.node(
            type: String(describing: type),
            alias: nodeAlias,
            predicate: nil
        )
        return self.and(pattern)
    }
    
    // MARK: - Cypher Compilation
    
    public func toCypher() throws -> CypherFragment {
        var fragments: [CypherFragment] = []
        
        for pattern in patterns {
            fragments.append(try pattern.toCypher())
        }
        
        let patternQuery = fragments
            .map { $0.query }
            .joined(separator: ", ")
        
        var parameters: [String: any Sendable] = [:]
        for fragment in fragments {
            parameters.merge(fragment.parameters) { _, new in new }
        }
        
        var query = "OPTIONAL MATCH \(patternQuery)"
        
        if let predicate = predicate {
            let predicateCypher = try predicate.toCypher()
            query += " WHERE \(predicateCypher.query)"
            parameters.merge(predicateCypher.parameters) { _, new in new }
        }
        
        return CypherFragment(query: query, parameters: parameters)
    }
}

// MARK: - Edge Builder for OPTIONAL MATCH

/// Builder for creating optional edge match patterns with fluent API
public struct OptionalEdgeBuilder<T: _KuzuGraphModel> {
    let type: T.Type
    let alias: String?
    
    init(type: T.Type, alias: String?) {
        self.type = type
        self.alias = alias
    }
    
    public func from(_ source: String) -> OptionalEdgeBuilderWithFrom<T> {
        OptionalEdgeBuilderWithFrom(type: type, alias: alias, from: source)
    }
}

public struct OptionalEdgeBuilderWithFrom<T: _KuzuGraphModel> {
    let type: T.Type
    let alias: String?
    let from: String
    
    public func to(_ target: String) -> OptionalMatch {
        let pattern = MatchPattern.edge(
            type: String(describing: type),
            from: from,
            to: target,
            alias: alias ?? String(describing: type).lowercased(),
            predicate: nil
        )
        return OptionalMatch.pattern(pattern)
    }
    
    public func to<TargetType: _KuzuGraphModel>(_ targetType: TargetType.Type, alias targetAlias: String) -> OptionalMatch {
        let edgePattern = MatchPattern.edge(
            type: String(describing: type),
            from: from,
            to: targetAlias,
            alias: alias ?? String(describing: type).lowercased(),
            predicate: nil
        )
        let nodePattern = MatchPattern.node(
            type: String(describing: targetType),
            alias: targetAlias,
            predicate: nil
        )
        return OptionalMatch.pattern(edgePattern, nodePattern)
    }
}

// MARK: - Convenience Extensions

public extension OptionalMatch {
    /// Creates an OPTIONAL MATCH for a relationship pattern
    static func relationship<From: _KuzuGraphModel, To: _KuzuGraphModel, Edge: _KuzuGraphModel>(
        from: (From.Type, String),
        via edge: Edge.Type,
        to: (To.Type, String),
        edgeAlias: String? = nil
    ) -> OptionalMatch {
        let fromPattern = MatchPattern.node(
            type: String(describing: from.0),
            alias: from.1,
            predicate: nil
        )
        let edgePattern = MatchPattern.edge(
            type: String(describing: edge),
            from: from.1,
            to: to.1,
            alias: edgeAlias ?? String(describing: edge).lowercased(),
            predicate: nil
        )
        let toPattern = MatchPattern.node(
            type: String(describing: to.0),
            alias: to.1,
            predicate: nil
        )
        return OptionalMatch.createWithPatterns([fromPattern, edgePattern, toPattern])
    }
    
    /// Creates an OPTIONAL MATCH for a path
    static func path<From: _KuzuGraphModel, To: _KuzuGraphModel, Edge: _KuzuGraphModel>(
        from: (From.Type, String),
        to: (To.Type, String),
        via edge: Edge.Type,
        hops: ClosedRange<Int>? = nil,
        pathAlias: String
    ) -> OptionalMatch {
        let pattern = MatchPattern.path(
            from: from.1,
            to: to.1,
            edgeType: String(describing: edge),
            minHops: hops?.lowerBound,
            maxHops: hops?.upperBound,
            alias: pathAlias
        )
        return OptionalMatch.pattern(pattern)
    }
}