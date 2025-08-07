import Foundation

/// Represents complex path patterns in graph queries
public struct PathPattern {
    let pattern: PathPatternType
    let alias: String?
    
    private init(pattern: PathPatternType, alias: String? = nil) {
        self.pattern = pattern
        self.alias = alias
    }
    
    /// Types of path patterns
    public enum PathPatternType {
        case simple(from: String, to: String, edgeType: String?, direction: Direction)
        case variableLength(from: String, to: String, edgeType: String?, minHops: Int?, maxHops: Int?, direction: Direction)
        case shortestPath(from: String, to: String, edgeType: String?, maxHops: Int?)
        case allPaths(from: String, to: String, edgeType: String?, maxHops: Int?)
        case custom(String)
    }
    
    /// Edge direction in path patterns
    public enum Direction {
        case outgoing  // -[]->
        case incoming  // <-[]-
        case both      // -[]-
    }
    
    // MARK: - Simple Paths
    
    /// Creates a simple path pattern
    public static func path(
        from: String,
        to: String,
        via edgeType: String? = nil,
        direction: Direction = .outgoing,
        as alias: String? = nil
    ) -> PathPattern {
        PathPattern(
            pattern: .simple(from: from, to: to, edgeType: edgeType, direction: direction),
            alias: alias
        )
    }
    
    /// Creates a typed path pattern
    public static func path<From: _KuzuGraphModel, To: _KuzuGraphModel, Edge: _KuzuGraphModel>(
        from: (From.Type, String),
        to: (To.Type, String),
        via edge: Edge.Type,
        direction: Direction = .outgoing,
        as alias: String? = nil
    ) -> PathPattern {
        PathPattern(
            pattern: .simple(
                from: from.1,
                to: to.1,
                edgeType: String(describing: edge),
                direction: direction
            ),
            alias: alias
        )
    }
    
    // MARK: - Variable Length Paths
    
    /// Creates a variable length path pattern
    public static func variablePath(
        from: String,
        to: String,
        via edgeType: String? = nil,
        hops: ClosedRange<Int>? = nil,
        direction: Direction = .outgoing,
        as alias: String? = nil
    ) -> PathPattern {
        PathPattern(
            pattern: .variableLength(
                from: from,
                to: to,
                edgeType: edgeType,
                minHops: hops?.lowerBound,
                maxHops: hops?.upperBound,
                direction: direction
            ),
            alias: alias
        )
    }
    
    /// Creates a variable length path with minimum hops
    public static func atLeast(
        _ minHops: Int,
        from: String,
        to: String,
        via edgeType: String? = nil,
        direction: Direction = .outgoing,
        as alias: String? = nil
    ) -> PathPattern {
        PathPattern(
            pattern: .variableLength(
                from: from,
                to: to,
                edgeType: edgeType,
                minHops: minHops,
                maxHops: nil,
                direction: direction
            ),
            alias: alias
        )
    }
    
    /// Creates a variable length path with maximum hops
    public static func atMost(
        _ maxHops: Int,
        from: String,
        to: String,
        via edgeType: String? = nil,
        direction: Direction = .outgoing,
        as alias: String? = nil
    ) -> PathPattern {
        PathPattern(
            pattern: .variableLength(
                from: from,
                to: to,
                edgeType: edgeType,
                minHops: nil,
                maxHops: maxHops,
                direction: direction
            ),
            alias: alias
        )
    }
    
    /// Creates a path with exact number of hops
    public static func exactly(
        _ hops: Int,
        from: String,
        to: String,
        via edgeType: String? = nil,
        direction: Direction = .outgoing,
        as alias: String? = nil
    ) -> PathPattern {
        PathPattern(
            pattern: .variableLength(
                from: from,
                to: to,
                edgeType: edgeType,
                minHops: hops,
                maxHops: hops,
                direction: direction
            ),
            alias: alias
        )
    }
    
    // MARK: - Shortest Path
    
    /// Creates a shortest path pattern
    public static func shortest(
        from: String,
        to: String,
        via edgeType: String? = nil,
        maxHops: Int? = nil,
        as alias: String? = nil
    ) -> PathPattern {
        PathPattern(
            pattern: .shortestPath(
                from: from,
                to: to,
                edgeType: edgeType,
                maxHops: maxHops
            ),
            alias: alias
        )
    }
    
    /// Creates a typed shortest path pattern
    public static func shortest<From: _KuzuGraphModel, To: _KuzuGraphModel, Edge: _KuzuGraphModel>(
        from: (From.Type, String),
        to: (To.Type, String),
        via edge: Edge.Type,
        maxHops: Int? = nil,
        as alias: String? = nil
    ) -> PathPattern {
        PathPattern(
            pattern: .shortestPath(
                from: from.1,
                to: to.1,
                edgeType: String(describing: edge),
                maxHops: maxHops
            ),
            alias: alias
        )
    }
    
    // MARK: - All Paths
    
    /// Creates a pattern to find all paths
    public static func allPaths(
        from: String,
        to: String,
        via edgeType: String? = nil,
        maxHops: Int? = nil,
        as alias: String? = nil
    ) -> PathPattern {
        PathPattern(
            pattern: .allPaths(
                from: from,
                to: to,
                edgeType: edgeType,
                maxHops: maxHops
            ),
            alias: alias
        )
    }
    
    // MARK: - Custom Patterns
    
    /// Creates a custom path pattern
    public static func custom(_ pattern: String, as alias: String? = nil) -> PathPattern {
        PathPattern(pattern: .custom(pattern), alias: alias)
    }
    
    // MARK: - Cypher Generation
    
    /// Generates the Cypher representation of the path pattern
    public func toCypher() -> String {
        let pathString: String
        
        switch pattern {
        case .simple(let from, let to, let edgeType, let direction):
            let edge = formatEdge(type: edgeType, direction: direction)
            pathString = "(\(from))\(edge)(\(to))"
            
        case .variableLength(let from, let to, let edgeType, let minHops, let maxHops, let direction):
            let hopsPattern: String
            if let minHops = minHops, let maxHops = maxHops {
                hopsPattern = "*\(minHops)..\(maxHops)"
            } else if let minHops = minHops {
                hopsPattern = "*\(minHops).."
            } else if let maxHops = maxHops {
                hopsPattern = "*..\(maxHops)"
            } else {
                hopsPattern = "*"
            }
            
            let edge = formatEdge(type: edgeType, hops: hopsPattern, direction: direction)
            pathString = "(\(from))\(edge)(\(to))"
            
        case .shortestPath(let from, let to, let edgeType, let maxHops):
            let hops = maxHops.map { "*..\($0)" } ?? "*"
            let edge = formatEdge(type: edgeType, hops: hops, direction: .outgoing)
            let innerPath = "(\(from))\(edge)(\(to))"
            pathString = "shortestPath(\(innerPath))"
            
        case .allPaths(let from, let to, let edgeType, let maxHops):
            let hops = maxHops.map { "*..\($0)" } ?? "*"
            let edge = formatEdge(type: edgeType, hops: hops, direction: .outgoing)
            pathString = "(\(from))\(edge)(\(to))"
            
        case .custom(let pattern):
            pathString = pattern
        }
        
        if let alias = alias {
            return "\(alias) = \(pathString)"
        } else {
            return pathString
        }
    }
    
    /// Formats an edge pattern with type and direction
    private func formatEdge(
        type: String?,
        hops: String? = nil,
        direction: Direction
    ) -> String {
        let typePattern = type.map { ":\($0)" } ?? ""
        let hopsPattern = hops ?? ""
        let fullPattern = "\(typePattern)\(hopsPattern)"
        
        switch direction {
        case .outgoing:
            return "-[\(fullPattern)]->"
        case .incoming:
            return "<-[\(fullPattern)]-"
        case .both:
            return "-[\(fullPattern)]-"
        }
    }
}

// MARK: - Match Integration

public extension Match {
    /// Creates a MATCH clause with a path pattern
    static func path(_ pattern: PathPattern) -> Match {
        let matchPattern = MatchPattern.custom(pattern.toCypher())
        return Match.pattern(matchPattern)
    }
}

// MARK: - OptionalMatch Integration

public extension OptionalMatch {
    /// Creates an OPTIONAL MATCH clause with a path pattern
    static func path(_ pattern: PathPattern) -> OptionalMatch {
        let matchPattern = MatchPattern.custom(pattern.toCypher())
        return OptionalMatch.pattern(matchPattern)
    }
}

// MARK: - Path Functions

public struct PathFunctions {
    /// Returns the length of a path
    public static func length(_ pathAlias: String) -> String {
        "length(\(pathAlias))"
    }
    
    /// Returns the nodes in a path
    public static func nodes(_ pathAlias: String) -> String {
        "nodes(\(pathAlias))"
    }
    
    /// Returns the relationships in a path
    public static func relationships(_ pathAlias: String) -> String {
        "relationships(\(pathAlias))"
    }
    
    /// Returns the start node of a path
    public static func startNode(_ pathAlias: String) -> String {
        "startNode(\(pathAlias))"
    }
    
    /// Returns the end node of a path
    public static func endNode(_ pathAlias: String) -> String {
        "endNode(\(pathAlias))"
    }
}

// MARK: - Return Extensions for Paths

public extension Return {
    /// Returns path information
    static func path(_ alias: String) -> Return {
        Return.items(.alias(alias))
    }
    
    /// Returns the length of a path
    static func pathLength(_ pathAlias: String, as alias: String = "length") -> Return {
        Return.items(.aliased(
            expression: PathFunctions.length(pathAlias),
            alias: alias
        ))
    }
    
    /// Returns the nodes in a path
    static func pathNodes(_ pathAlias: String, as alias: String = "nodes") -> Return {
        Return.items(.aliased(
            expression: PathFunctions.nodes(pathAlias),
            alias: alias
        ))
    }
    
    /// Returns the relationships in a path
    static func pathRelationships(_ pathAlias: String, as alias: String = "relationships") -> Return {
        Return.items(.aliased(
            expression: PathFunctions.relationships(pathAlias),
            alias: alias
        ))
    }
}

// MARK: - Predicate Extensions for Paths

public extension Predicate {
    /// Creates a predicate checking path length
    static func pathLength(_ pathAlias: String, _ op: ComparisonOperator, _ value: Int) -> Predicate {
        let lengthExpr = PathFunctions.length(pathAlias)
        let prop = PropertyReference(alias: "", property: lengthExpr)
        return Predicate(node: .comparison(ComparisonExpression(
            lhs: prop,
            op: op,
            rhs: .value(value)
        )))
    }
}