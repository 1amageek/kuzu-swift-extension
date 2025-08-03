import Foundation

// MARK: - Path Pattern DSL

public struct Path {
    let name: String
    let pattern: PathPattern
    
    public init(_ name: String = "p", @PathBuilder _ builder: () -> PathPattern) {
        self.name = name
        self.pattern = builder()
    }
}

@resultBuilder
public struct PathBuilder {
    public static func buildBlock(_ pattern: PathPattern) -> PathPattern {
        pattern
    }
}

public struct PathPattern {
    let start: NodePattern
    let segments: [PathSegment]
    
    public init(start: NodePattern, segments: [PathSegment] = []) {
        self.start = start
        self.segments = segments
    }
}

public struct NodePattern {
    let variable: String
    let type: any _KuzuGraphModel.Type
    let predicates: [WhereCondition]
    
    public init<T: _KuzuGraphModel>(
        _ type: T.Type,
        as variable: String? = nil,
        where predicates: [WhereCondition] = []
    ) {
        self.variable = variable ?? type._kuzuTableName.lowercased()
        self.type = type
        self.predicates = predicates
    }
}

public struct PathSegment {
    let edge: EdgePattern
    let node: NodePattern
    let direction: EdgeDirection
}

public enum EdgeDirection {
    case outgoing  // ->
    case incoming  // <-
    case both      // -
}

public struct EdgePattern {
    let variable: String?
    let type: (any _KuzuGraphModel.Type)?
    let hops: ClosedRange<Int>?
    
    public init(
        _ type: (any _KuzuGraphModel.Type)? = nil,
        as variable: String? = nil,
        hops: ClosedRange<Int>? = nil
    ) {
        self.type = type
        self.variable = variable
        self.hops = hops
    }
}

// MARK: - Path DSL Extensions

public extension NodePattern {
    func to<T: _KuzuGraphModel>(
        _ nodeType: T.Type,
        via edgeType: (any _KuzuGraphModel.Type)? = nil,
        hops: ClosedRange<Int>? = nil,
        as variable: String? = nil
    ) -> PathPattern {
        let edge = EdgePattern(edgeType, hops: hops)
        let node = NodePattern(nodeType, as: variable)
        let segment = PathSegment(edge: edge, node: node, direction: .outgoing)
        
        return PathPattern(start: self, segments: [segment])
    }
    
    func from<T: _KuzuGraphModel>(
        _ nodeType: T.Type,
        via edgeType: (any _KuzuGraphModel.Type)? = nil,
        hops: ClosedRange<Int>? = nil,
        as variable: String? = nil
    ) -> PathPattern {
        let edge = EdgePattern(edgeType, hops: hops)
        let node = NodePattern(nodeType, as: variable)
        let segment = PathSegment(edge: edge, node: node, direction: .incoming)
        
        return PathPattern(start: self, segments: [segment])
    }
    
    func both<T: _KuzuGraphModel>(
        _ nodeType: T.Type,
        via edgeType: (any _KuzuGraphModel.Type)? = nil,
        hops: ClosedRange<Int>? = nil,
        as variable: String? = nil
    ) -> PathPattern {
        let edge = EdgePattern(edgeType, hops: hops)
        let node = NodePattern(nodeType, as: variable)
        let segment = PathSegment(edge: edge, node: node, direction: .both)
        
        return PathPattern(start: self, segments: [segment])
    }
}

public extension PathPattern {
    func to<T: _KuzuGraphModel>(
        _ nodeType: T.Type,
        via edgeType: (any _KuzuGraphModel.Type)? = nil,
        hops: ClosedRange<Int>? = nil,
        as variable: String? = nil
    ) -> PathPattern {
        let edge = EdgePattern(edgeType, hops: hops)
        let node = NodePattern(nodeType, as: variable)
        let segment = PathSegment(edge: edge, node: node, direction: .outgoing)
        
        var newSegments = segments
        newSegments.append(segment)
        
        return PathPattern(start: start, segments: newSegments)
    }
    
    func from<T: _KuzuGraphModel>(
        _ nodeType: T.Type,
        via edgeType: (any _KuzuGraphModel.Type)? = nil,
        hops: ClosedRange<Int>? = nil,
        as variable: String? = nil
    ) -> PathPattern {
        let edge = EdgePattern(edgeType, hops: hops)
        let node = NodePattern(nodeType, as: variable)
        let segment = PathSegment(edge: edge, node: node, direction: .incoming)
        
        var newSegments = segments
        newSegments.append(segment)
        
        return PathPattern(start: start, segments: newSegments)
    }
}

// MARK: - Shortest Path

public struct ShortestPath {
    let from: NodePattern
    let to: NodePattern
    let via: EdgePattern?
    let weighted: String? // Property name for weight
    
    public init(
        from: NodePattern,
        to: NodePattern,
        via: EdgePattern? = nil,
        weighted: String? = nil
    ) {
        self.from = from
        self.to = to
        self.via = via
        self.weighted = weighted
    }
}

// MARK: - Path Query Components

public extension QueryComponent {
    static func path(_ path: Path) -> QueryComponent {
        // This would be compiled to MATCH path pattern
        .match(MatchClause(
            variable: path.name,
            type: path.pattern.start.type,
            predicates: path.pattern.start.predicates
        ))
    }
    
    static func shortestPath(_ shortestPath: ShortestPath) -> QueryComponent {
        // This would be compiled to shortestPath() function call
        .match(MatchClause(
            variable: "sp",
            type: shortestPath.from.type,
            predicates: shortestPath.from.predicates
        ))
    }
}