import Foundation

/// Builder for creating edge match patterns with fluent API
public struct EdgeBuilder<T: _KuzuGraphModel> {
    let type: T.Type
    let alias: String?
    
    init(type: T.Type, alias: String?) {
        self.type = type
        self.alias = alias
    }
    
    public func from(_ source: String) -> EdgeBuilderWithFrom<T> {
        EdgeBuilderWithFrom(type: type, alias: alias, from: source)
    }
}

public struct EdgeBuilderWithFrom<T: _KuzuGraphModel> {
    let type: T.Type
    let alias: String?
    let from: String
    
    public func to(_ target: String) -> Match {
        let pattern = MatchPattern.edge(
            type: String(describing: type),
            from: from,
            to: target,
            alias: alias ?? String(describing: type).lowercased(),
            predicate: nil
        )
        return Match(patterns: [pattern])
    }
    
    public func to<TargetType: _KuzuGraphModel>(_ targetType: TargetType.Type, alias targetAlias: String) -> Match {
        let pattern = MatchPattern.edge(
            type: String(describing: type),
            from: from,
            to: targetAlias,
            alias: alias ?? String(describing: type).lowercased(),
            predicate: nil
        )
        return Match(patterns: [pattern])
    }
}

public struct Match: QueryComponent {
    let patterns: [MatchPattern]
    
    internal init(patterns: [MatchPattern]) {
        self.patterns = patterns
    }
    
    // MARK: - Type-safe API
    
    /// Creates a match pattern for a node of the specified type
    public static func node<T: _KuzuGraphModel>(
        _ type: T.Type,
        alias: String? = nil,
        where predicate: Predicate? = nil
    ) -> Match {
        let typeInfo = TypeNameExtractor.extractTypeInfo(type)
        let pattern = MatchPattern.node(
            type: typeInfo.typeName,
            alias: alias ?? typeInfo.defaultAlias,
            predicate: predicate
        )
        return Match(patterns: [pattern])
    }
    
    public static func pattern(_ patterns: MatchPattern...) -> Match {
        Match(patterns: patterns)
    }
    
    public static func edge<T: _KuzuGraphModel>(
        _ type: T.Type,
        alias: String? = nil
    ) -> EdgeBuilder<T> {
        EdgeBuilder(type: type, alias: alias)
    }
    
    public func toCypher() throws -> CypherFragment {
        var fragments: [CypherFragment] = []
        
        for pattern in patterns {
            fragments.append(try pattern.toCypher())
        }
        
        let merged = fragments.reduce(CypherFragment(query: "MATCH", parameters: [:])) { result, fragment in
            if result.query == "MATCH" {
                return CypherFragment(
                    query: "MATCH " + fragment.query,
                    parameters: fragment.parameters
                )
            } else {
                return result.merged(with: CypherFragment(query: ", " + fragment.query, parameters: fragment.parameters))
            }
        }
        
        return merged
    }
}

public enum MatchPattern {
    case node(type: String, alias: String, predicate: Predicate?)
    case edge(type: String, from: String, to: String, alias: String, predicate: Predicate?)
    case path(from: String, to: String, edgeType: String?, minHops: Int?, maxHops: Int?, alias: String)
    case custom(String)
    
    public static func node<T: _KuzuGraphModel>(
        _ type: T.Type,
        alias: String? = nil
    ) -> MatchPattern {
        .node(
            type: String(describing: type),
            alias: alias ?? String(describing: type).lowercased(),
            predicate: nil
        )
    }
    
    public static func edge<T: _KuzuGraphModel>(
        _ type: T.Type,
        from: String,
        to: String,
        alias: String? = nil
    ) -> MatchPattern {
        .edge(
            type: String(describing: type),
            from: from,
            to: to,
            alias: alias ?? String(describing: type).lowercased(),
            predicate: nil
        )
    }
    
    public static func path(
        from: String,
        to: String,
        via edgeType: String? = nil,
        hops: ClosedRange<Int>? = nil,
        alias: String
    ) -> MatchPattern {
        .path(
            from: from,
            to: to,
            edgeType: edgeType,
            minHops: hops?.lowerBound,
            maxHops: hops?.upperBound,
            alias: alias
        )
    }
    
    func toCypher() throws -> CypherFragment {
        switch self {
        case .node(let type, let alias, let predicate):
            let nodePattern = "(\(alias):\(type))"
            if let predicate = predicate {
                let predicateFragment = try predicate.toCypher()
                return CypherFragment(
                    query: nodePattern + " WHERE " + predicateFragment.query,
                    parameters: predicateFragment.parameters
                )
            }
            return CypherFragment(query: nodePattern)
            
        case .edge(let type, let from, let to, let alias, let predicate):
            let edgePattern = "(\(from))-[\(alias):\(type)]->(\(to))"
            if let predicate = predicate {
                let predicateFragment = try predicate.toCypher()
                return CypherFragment(
                    query: edgePattern + " WHERE " + predicateFragment.query,
                    parameters: predicateFragment.parameters
                )
            }
            return CypherFragment(query: edgePattern)
            
        case .path(let from, let to, let edgeType, let minHops, let maxHops, let alias):
            var hopsClause = ""
            if let min = minHops, let max = maxHops {
                hopsClause = "*\(min)..\(max)"
            } else if let min = minHops {
                hopsClause = "*\(min).."
            } else if let max = maxHops {
                hopsClause = "*..\(max)"
            }
            
            let edgeClause = edgeType.map { ":\($0)" } ?? ""
            let pathPattern = "\(alias) = (\(from))-[\(edgeClause)\(hopsClause)]->(\(to))"
            return CypherFragment(query: pathPattern)
            
        case .custom(let pattern):
            return CypherFragment(query: pattern)
        }
    }
}

