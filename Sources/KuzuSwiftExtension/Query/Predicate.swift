import Foundation

/// Represents a WHERE clause predicate in a Cypher query
public struct Predicate {
    let node: PredicateNode
    
    internal init(node: PredicateNode) {
        self.node = node
    }
    
    /// Creates a predicate from a node
    public static func node(_ node: PredicateNode) -> Predicate {
        Predicate(node: node)
    }
    
    /// Combines two predicates with AND
    public static func && (lhs: Predicate, rhs: Predicate) -> Predicate {
        Predicate(node: .and(lhs.node, rhs.node))
    }
    
    /// Combines two predicates with OR
    public static func || (lhs: Predicate, rhs: Predicate) -> Predicate {
        Predicate(node: .or(lhs.node, rhs.node))
    }
    
    /// Negates a predicate
    public static prefix func ! (predicate: Predicate) -> Predicate {
        Predicate(node: .not(predicate.node))
    }
    
    /// Converts the predicate to a Cypher fragment
    public func toCypher() throws -> CypherFragment {
        return try node.toCypher()
    }
}

/// Represents different types of predicate nodes
public indirect enum PredicateNode {
    case comparison(ComparisonExpression)
    case and(PredicateNode, PredicateNode)
    case or(PredicateNode, PredicateNode)
    case not(PredicateNode)
    case isNull(PropertyReference)
    case isNotNull(PropertyReference)
    case inList(PropertyReference, values: any Sendable)
    case contains(PropertyReference, value: any Sendable)
    case startsWith(PropertyReference, value: String)
    case endsWith(PropertyReference, value: String)
    case regex(PropertyReference, pattern: String)
    case exists(Exists)
    case literal(Bool)
    case custom(String, parameters: [String: any Sendable])
    
    public func toCypher() throws -> CypherFragment {
        switch self {
        case .comparison(let comp):
            return try comp.toCypher()
            
        case .and(let lhs, let rhs):
            let lhsCypher = try lhs.toCypher()
            let rhsCypher = try rhs.toCypher()
            return CypherFragment(
                query: "(\(lhsCypher.query) AND \(rhsCypher.query))",
                parameters: lhsCypher.parameters.merging(rhsCypher.parameters) { _, new in new }
            )
            
        case .or(let lhs, let rhs):
            let lhsCypher = try lhs.toCypher()
            let rhsCypher = try rhs.toCypher()
            return CypherFragment(
                query: "(\(lhsCypher.query) OR \(rhsCypher.query))",
                parameters: lhsCypher.parameters.merging(rhsCypher.parameters) { _, new in new }
            )
            
        case .not(let expr):
            let cypher = try expr.toCypher()
            return CypherFragment(
                query: "NOT (\(cypher.query))",
                parameters: cypher.parameters
            )
            
        case .isNull(let prop):
            return CypherFragment(query: "\(prop.cypher) IS NULL")
            
        case .isNotNull(let prop):
            return CypherFragment(query: "\(prop.cypher) IS NOT NULL")
            
        case .inList(let prop, let values):
            let paramName = OptimizedParameterGenerator.lightweight()
            return CypherFragment(
                query: "\(prop.cypher) IN $\(paramName)",
                parameters: [paramName: values]
            )
            
        case .contains(let prop, let value):
            let paramName = OptimizedParameterGenerator.lightweight()
            return CypherFragment(
                query: "\(prop.cypher) CONTAINS $\(paramName)",
                parameters: [paramName: value]
            )
            
        case .startsWith(let prop, let value):
            let paramName = OptimizedParameterGenerator.lightweight()
            return CypherFragment(
                query: "\(prop.cypher) STARTS WITH $\(paramName)",
                parameters: [paramName: value]
            )
            
        case .endsWith(let prop, let value):
            let paramName = OptimizedParameterGenerator.lightweight()
            return CypherFragment(
                query: "\(prop.cypher) ENDS WITH $\(paramName)",
                parameters: [paramName: value]
            )
            
        case .regex(let prop, let pattern):
            let paramName = OptimizedParameterGenerator.lightweight()
            return CypherFragment(
                query: "\(prop.cypher) =~ $\(paramName)",
                parameters: [paramName: pattern]
            )
            
        case .exists(let exists):
            return try exists.toCypher()
            
        case .literal(let value):
            return CypherFragment(query: value ? "true" : "false")
            
        case .custom(let query, let parameters):
            return CypherFragment(query: query, parameters: parameters)
        }
    }
}

/// Represents a comparison expression
public struct ComparisonExpression {
    public let lhs: PropertyReference
    public let op: ComparisonOperator
    public let rhs: ComparisonValue
    
    public init(lhs: PropertyReference, op: ComparisonOperator, rhs: ComparisonValue) {
        self.lhs = lhs
        self.op = op
        self.rhs = rhs
    }
    
    public func toCypher() throws -> CypherFragment {
        switch rhs {
        case .property(let prop):
            return CypherFragment(query: "\(lhs.cypher) \(op.rawValue) \(prop.cypher)")
            
        case .value(let value):
            let paramName = OptimizedParameterGenerator.lightweight()
            return CypherFragment(
                query: "\(lhs.cypher) \(op.rawValue) $\(paramName)",
                parameters: [paramName: value]
            )
            
        case .ref(let ref):
            let refCypher = try ref.toCypher()
            return CypherFragment(
                query: "\(lhs.cypher) \(op.rawValue) \(refCypher.query)",
                parameters: refCypher.parameters
            )
        }
    }
}

/// Comparison operators
public enum ComparisonOperator: String {
    case equal = "="
    case notEqual = "<>"
    case lessThan = "<"
    case lessThanOrEqual = "<="
    case greaterThan = ">"
    case greaterThanOrEqual = ">="
}

/// Right-hand side of a comparison
public enum ComparisonValue {
    case property(PropertyReference)
    case value(any Sendable)
    case ref(Ref)  // Add support for variable references
}

/// Reference to a property
public struct PropertyReference {
    let alias: String
    let property: String
    
    var cypher: String {
        "\(alias).\(property)"
    }
    
    public init(alias: String, property: String) {
        self.alias = alias
        self.property = property
    }
    
    /// Returns the Cypher representation of this property reference
    public func toCypher() -> String {
        return cypher
    }
}

// MARK: - Convenience Functions

/// Creates an equality predicate
public func == (lhs: PropertyReference, rhs: any Sendable) -> Predicate {
    if let ref = rhs as? Ref {
        return Predicate(node: .comparison(ComparisonExpression(
            lhs: lhs,
            op: .equal,
            rhs: .ref(ref)
        )))
    }
    return Predicate(node: .comparison(ComparisonExpression(
        lhs: lhs,
        op: .equal,
        rhs: .value(rhs)
    )))
}

/// Creates an inequality predicate
public func != (lhs: PropertyReference, rhs: any Sendable) -> Predicate {
    if let ref = rhs as? Ref {
        return Predicate(node: .comparison(ComparisonExpression(
            lhs: lhs,
            op: .notEqual,
            rhs: .ref(ref)
        )))
    }
    return Predicate(node: .comparison(ComparisonExpression(
        lhs: lhs,
        op: .notEqual,
        rhs: .value(rhs)
    )))
}

/// Creates a less than predicate
public func < (lhs: PropertyReference, rhs: any Sendable) -> Predicate {
    if let ref = rhs as? Ref {
        return Predicate(node: .comparison(ComparisonExpression(
            lhs: lhs,
            op: .lessThan,
            rhs: .ref(ref)
        )))
    }
    return Predicate(node: .comparison(ComparisonExpression(
        lhs: lhs,
        op: .lessThan,
        rhs: .value(rhs)
    )))
}

/// Creates a less than or equal predicate
public func <= (lhs: PropertyReference, rhs: any Sendable) -> Predicate {
    if let ref = rhs as? Ref {
        return Predicate(node: .comparison(ComparisonExpression(
            lhs: lhs,
            op: .lessThanOrEqual,
            rhs: .ref(ref)
        )))
    }
    return Predicate(node: .comparison(ComparisonExpression(
        lhs: lhs,
        op: .lessThanOrEqual,
        rhs: .value(rhs)
    )))
}

/// Creates a greater than predicate
public func > (lhs: PropertyReference, rhs: any Sendable) -> Predicate {
    if let ref = rhs as? Ref {
        return Predicate(node: .comparison(ComparisonExpression(
            lhs: lhs,
            op: .greaterThan,
            rhs: .ref(ref)
        )))
    }
    return Predicate(node: .comparison(ComparisonExpression(
        lhs: lhs,
        op: .greaterThan,
        rhs: .value(rhs)
    )))
}

/// Creates a greater than or equal predicate
public func >= (lhs: PropertyReference, rhs: any Sendable) -> Predicate {
    if let ref = rhs as? Ref {
        return Predicate(node: .comparison(ComparisonExpression(
            lhs: lhs,
            op: .greaterThanOrEqual,
            rhs: .ref(ref)
        )))
    }
    return Predicate(node: .comparison(ComparisonExpression(
        lhs: lhs,
        op: .greaterThanOrEqual,
        rhs: .value(rhs)
    )))
}

// MARK: - Property Reference Extensions

extension PropertyReference {
    /// Creates an IN predicate
    public func `in`<T: Sendable>(_ values: [T]) -> Predicate {
        return Predicate(node: .inList(self, values: values))
    }
    
    /// Creates a CONTAINS predicate
    public func contains(_ value: any Sendable) -> Predicate {
        Predicate(node: .contains(self, value: value))
    }
    
    /// Creates a STARTS WITH predicate
    public func startsWith(_ value: String) -> Predicate {
        Predicate(node: .startsWith(self, value: value))
    }
    
    /// Creates an ENDS WITH predicate
    public func endsWith(_ value: String) -> Predicate {
        Predicate(node: .endsWith(self, value: value))
    }
    
    /// Creates a regex match predicate
    public func matches(_ pattern: String) -> Predicate {
        Predicate(node: .regex(self, pattern: pattern))
    }
    
    /// Creates an IS NULL predicate
    public var isNull: Predicate {
        Predicate(node: .isNull(self))
    }
    
    /// Creates an IS NOT NULL predicate
    public var isNotNull: Predicate {
        Predicate(node: .isNotNull(self))
    }
}