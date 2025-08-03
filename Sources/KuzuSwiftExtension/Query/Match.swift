import Foundation

public struct Match: QueryComponent {
    let patterns: [MatchPattern]
    
    private init(patterns: [MatchPattern]) {
        self.patterns = patterns
    }
    
    public static func node<T: _KuzuGraphModel>(
        _ type: T.Type,
        alias: String? = nil,
        where predicate: Predicate? = nil
    ) -> Match {
        let pattern = MatchPattern.node(
            type: String(describing: type),
            alias: alias ?? String(describing: type).lowercased(),
            predicate: predicate
        )
        return Match(patterns: [pattern])
    }
    
    public static func pattern(_ patterns: MatchPattern...) -> Match {
        Match(patterns: patterns)
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
        }
    }
}

// Placeholder for Predicate
public struct Predicate {
    func toCypher() throws -> CypherFragment {
        // TODO: Implement predicate compilation
        CypherFragment(query: "true")
    }
}