import Foundation

/// Represents a WHERE clause in a Cypher query
public struct Where: QueryComponent {
    let predicate: Predicate
    
    public init(_ predicate: Predicate) {
        self.predicate = predicate
    }
    
    /// Creates a WHERE clause with the given predicate
    public static func condition(_ predicate: Predicate) -> Where {
        Where(predicate)
    }
    
    /// Creates a WHERE clause using a builder
    public static func condition(_ builder: () -> Predicate) -> Where {
        Where(builder())
    }
    
    public func toCypher() throws -> CypherFragment {
        let predicateCypher = try predicate.toCypher()
        return CypherFragment(
            query: "WHERE \(predicateCypher.query)",
            parameters: predicateCypher.parameters
        )
    }
}

// MARK: - Convenience property function

/// Creates a property reference for use in predicates
public func property(_ alias: String, _ propertyName: String) -> PropertyReference {
    PropertyReference(alias: alias, property: propertyName)
}

/// Creates a property reference using dot notation
public func prop(_ path: String) -> PropertyReference {
    let components = path.split(separator: ".")
    guard components.count == 2 else {
        fatalError("Property path must be in format 'alias.property'")
    }
    return PropertyReference(
        alias: String(components[0]),
        property: String(components[1])
    )
}