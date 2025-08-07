import Foundation

/// A type-safe path for edge properties
public struct EdgePath<Edge: _KuzuGraphModel, Value> {
    public let keyPath: KeyPath<Edge, Value>
    public let alias: String
    public let propertyName: String
    
    public init(keyPath: KeyPath<Edge, Value>, alias: String) {
        self.keyPath = keyPath
        self.alias = alias
        self.propertyName = Self.extractPropertyName(from: keyPath)
    }
    
    /// Extracts the property name from a KeyPath
    private static func extractPropertyName(from keyPath: KeyPath<Edge, Value>) -> String {
        let keyPathString = String(describing: keyPath)
        // KeyPath string format is like: \TypeName.propertyName
        let components = keyPathString.components(separatedBy: ".")
        if let lastComponent = components.last {
            // Remove any trailing characters
            let cleanName = lastComponent
                .replacingOccurrences(of: ")", with: "")
                .replacingOccurrences(of: ">", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleanName
        }
        return keyPathString
    }
    
    /// Converts to PropertyReference for use in predicates
    public var propertyReference: PropertyReference {
        PropertyReference(alias: alias, property: propertyName)
    }
    
    /// Creates a Cypher property reference string
    public var cypherString: String {
        "\(alias).\(propertyName)"
    }
}

// MARK: - Helper Functions

/// Creates a type-safe edge property path
public func edge<E: _KuzuGraphModel, V>(
    _ keyPath: KeyPath<E, V>,
    on alias: String
) -> EdgePath<E, V> {
    EdgePath(keyPath: keyPath, alias: alias)
}

/// Alias for edge() - creates a type-safe edge property path
public func rel<E: _KuzuGraphModel, V>(
    _ keyPath: KeyPath<E, V>,
    on alias: String
) -> EdgePath<E, V> {
    EdgePath(keyPath: keyPath, alias: alias)
}

// MARK: - Comparison Operators for EdgePath

public func == <Edge, Value: Sendable>(lhs: EdgePath<Edge, Value>, rhs: Value) -> Predicate {
    Predicate(node: .comparison(ComparisonExpression(
        lhs: lhs.propertyReference,
        op: .equal,
        rhs: .value(rhs)
    )))
}

public func != <Edge, Value: Sendable>(lhs: EdgePath<Edge, Value>, rhs: Value) -> Predicate {
    Predicate(node: .comparison(ComparisonExpression(
        lhs: lhs.propertyReference,
        op: .notEqual,
        rhs: .value(rhs)
    )))
}

public func < <Edge, Value: Sendable>(lhs: EdgePath<Edge, Value>, rhs: Value) -> Predicate {
    Predicate(node: .comparison(ComparisonExpression(
        lhs: lhs.propertyReference,
        op: .lessThan,
        rhs: .value(rhs)
    )))
}

public func > <Edge, Value: Sendable>(lhs: EdgePath<Edge, Value>, rhs: Value) -> Predicate {
    Predicate(node: .comparison(ComparisonExpression(
        lhs: lhs.propertyReference,
        op: .greaterThan,
        rhs: .value(rhs)
    )))
}

public func <= <Edge, Value: Sendable>(lhs: EdgePath<Edge, Value>, rhs: Value) -> Predicate {
    Predicate(node: .comparison(ComparisonExpression(
        lhs: lhs.propertyReference,
        op: .lessThanOrEqual,
        rhs: .value(rhs)
    )))
}

public func >= <Edge, Value: Sendable>(lhs: EdgePath<Edge, Value>, rhs: Value) -> Predicate {
    Predicate(node: .comparison(ComparisonExpression(
        lhs: lhs.propertyReference,
        op: .greaterThanOrEqual,
        rhs: .value(rhs)
    )))
}

// MARK: - String Operations for EdgePath

public extension EdgePath where Value == String {
    /// Checks if the edge property contains a substring
    func contains(_ substring: String) -> Predicate {
        Predicate(node: .contains(propertyReference, value: substring))
    }
    
    /// Checks if the edge property starts with a prefix
    func startsWith(_ prefix: String) -> Predicate {
        Predicate(node: .startsWith(propertyReference, value: prefix))
    }
    
    /// Checks if the edge property ends with a suffix
    func endsWith(_ suffix: String) -> Predicate {
        Predicate(node: .endsWith(propertyReference, value: suffix))
    }
    
    /// Checks if the edge property matches a pattern
    func matches(_ pattern: String) -> Predicate {
        Predicate(node: .regex(propertyReference, pattern: pattern))
    }
}

// MARK: - Null Checks for EdgePath

public extension EdgePath {
    /// Checks if the edge property is null
    var isNull: Predicate {
        Predicate(node: .isNull(propertyReference))
    }
    
    /// Checks if the edge property is not null
    var isNotNull: Predicate {
        Predicate(node: .isNotNull(propertyReference))
    }
}

// MARK: - EdgePath in Return Statements

public extension Return {
    /// Returns an edge property value
    static func property<E: _KuzuGraphModel, V>(_ edgePath: EdgePath<E, V>, as alias: String? = nil) -> Return {
        let item: ReturnItem
        if let alias = alias {
            item = .aliased(expression: edgePath.cypherString, alias: alias)
        } else {
            item = .property(alias: edgePath.alias, property: edgePath.propertyName)
        }
        return Return.items(item)
    }
    
    /// Orders by an edge property
    func orderBy<E: _KuzuGraphModel, V>(_ edgePath: EdgePath<E, V>, ascending: Bool = true) -> Return {
        let orderItem = ascending ? 
            OrderByItem.ascending(edgePath.cypherString) :
            OrderByItem.descending(edgePath.cypherString)
        return self.orderBy(orderItem)
    }
}