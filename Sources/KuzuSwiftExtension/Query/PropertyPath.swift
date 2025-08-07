import Foundation

/// A type-safe property path that combines a KeyPath with an alias for query construction
public struct PropertyPath<Model: _KuzuGraphModel> {
    let keyPath: PartialKeyPath<Model>
    let alias: String
    let propertyName: String
    
    public init(keyPath: PartialKeyPath<Model>, alias: String) {
        self.keyPath = keyPath
        self.alias = alias
        // Extract property name from keyPath
        self.propertyName = Self.extractPropertyName(from: keyPath)
    }
    
    /// Extracts the property name from a KeyPath
    private static func extractPropertyName(from keyPath: PartialKeyPath<Model>) -> String {
        let keyPathString = String(describing: keyPath)
        // KeyPath string format is like: \TypeName.propertyName
        // We need to extract the property name after the last dot
        let components = keyPathString.components(separatedBy: ".")
        if let lastComponent = components.last {
            // Remove any trailing characters that might be added
            let cleanName = lastComponent.replacingOccurrences(of: ")", with: "")
                .replacingOccurrences(of: ">", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleanName
        }
        return keyPathString
    }
    
    /// Converts to PropertyReference for use in predicates
    var propertyReference: PropertyReference {
        PropertyReference(alias: alias, property: propertyName)
    }
    
    /// Creates a Cypher property reference string
    var cypherString: String {
        "\(alias).\(propertyName)"
    }
}

// MARK: - Comparison Operators

public func == <Model, Value: Sendable>(lhs: PropertyPath<Model>, rhs: Value) -> Predicate {
    Predicate(node: .comparison(ComparisonExpression(
        lhs: lhs.propertyReference,
        op: .equal,
        rhs: .value(rhs)
    )))
}

public func != <Model, Value: Sendable>(lhs: PropertyPath<Model>, rhs: Value) -> Predicate {
    Predicate(node: .comparison(ComparisonExpression(
        lhs: lhs.propertyReference,
        op: .notEqual,
        rhs: .value(rhs)
    )))
}

public func < <Model, Value: Sendable>(lhs: PropertyPath<Model>, rhs: Value) -> Predicate {
    Predicate(node: .comparison(ComparisonExpression(
        lhs: lhs.propertyReference,
        op: .lessThan,
        rhs: .value(rhs)
    )))
}

public func <= <Model, Value: Sendable>(lhs: PropertyPath<Model>, rhs: Value) -> Predicate {
    Predicate(node: .comparison(ComparisonExpression(
        lhs: lhs.propertyReference,
        op: .lessThanOrEqual,
        rhs: .value(rhs)
    )))
}

public func > <Model, Value: Sendable>(lhs: PropertyPath<Model>, rhs: Value) -> Predicate {
    Predicate(node: .comparison(ComparisonExpression(
        lhs: lhs.propertyReference,
        op: .greaterThan,
        rhs: .value(rhs)
    )))
}

public func >= <Model, Value: Sendable>(lhs: PropertyPath<Model>, rhs: Value) -> Predicate {
    Predicate(node: .comparison(ComparisonExpression(
        lhs: lhs.propertyReference,
        op: .greaterThanOrEqual,
        rhs: .value(rhs)
    )))
}

// MARK: - Property Path Extensions

extension PropertyPath {
    /// Creates an IN predicate
    public func `in`<T: Sendable>(_ values: [T]) -> Predicate {
        Predicate(node: .inList(propertyReference, values: values))
    }
    
    /// Creates a CONTAINS predicate
    public func contains(_ value: any Sendable) -> Predicate {
        Predicate(node: .contains(propertyReference, value: value))
    }
    
    /// Creates a STARTS WITH predicate
    public func startsWith(_ value: String) -> Predicate {
        Predicate(node: .startsWith(propertyReference, value: value))
    }
    
    /// Creates an ENDS WITH predicate
    public func endsWith(_ value: String) -> Predicate {
        Predicate(node: .endsWith(propertyReference, value: value))
    }
    
    /// Creates a regex match predicate
    public func matches(_ pattern: String) -> Predicate {
        Predicate(node: .regex(propertyReference, pattern: pattern))
    }
    
    /// Creates an IS NULL predicate
    public var isNull: Predicate {
        Predicate(node: .isNull(propertyReference))
    }
    
    /// Creates an IS NOT NULL predicate
    public var isNotNull: Predicate {
        Predicate(node: .isNotNull(propertyReference))
    }
}

// MARK: - Where Extension for Type-Safe Predicates

extension Where {
    /// Creates a type-safe property path for use in predicates
    public static func path<T: _KuzuGraphModel, V>(
        _ keyPath: KeyPath<T, V>,
        on alias: String
    ) -> PropertyPath<T> {
        PropertyPath(keyPath: keyPath, alias: alias)
    }
    
    /// Creates a WHERE clause with a type-safe predicate builder
    public static func condition<T: _KuzuGraphModel>(
        on alias: String,
        _ builder: (PropertyPath<T>) -> Predicate
    ) -> Where {
        // Create a dummy property path to pass to the builder
        // The actual properties will be accessed through specific keypaths in the builder
        let context = PropertyPath<T>(keyPath: \T.self, alias: alias)
        return Where(builder(context))
    }
}

// MARK: - Match Extension for Type-Safe Predicates

extension Match {
    /// Creates a match pattern with a type-safe predicate
    public static func nodeWithPredicate<T: _KuzuGraphModel>(
        _ type: T.Type,
        alias: String? = nil,
        where builder: ((String) -> Predicate)? = nil
    ) -> Match {
        let nodeAlias = alias ?? String(describing: type).lowercased()
        var predicate: Predicate?
        
        if let builder = builder {
            predicate = builder(nodeAlias)
        }
        
        let pattern = MatchPattern.node(
            type: String(describing: type),
            alias: nodeAlias,
            predicate: predicate
        )
        return Match.pattern(pattern)
    }
}

// MARK: - Helper for KeyPath-based property access

/// Helper function to create property paths with cleaner syntax
public func prop<T: _KuzuGraphModel, V>(
    _ keyPath: KeyPath<T, V>,
    on alias: String
) -> PropertyPath<T> {
    PropertyPath(keyPath: keyPath, alias: alias)
}

/// Alias for prop - creates a type-safe property path from a KeyPath
public func path<T: _KuzuGraphModel, V>(
    _ keyPath: KeyPath<T, V>,
    on alias: String
) -> PropertyPath<T> {
    PropertyPath(keyPath: keyPath, alias: alias)
}