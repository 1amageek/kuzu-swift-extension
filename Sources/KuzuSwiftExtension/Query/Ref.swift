import Foundation

/// Represents a reference to a query variable for use in predicates
public struct Ref: Sendable {
    public let alias: String
    
    public init(_ alias: String) {
        self.alias = alias
    }
    
    public func toCypher() throws -> CypherFragment {
        return CypherFragment(query: alias, parameters: [:])
    }
}

/// Represents an EXISTS subquery
public struct Exists: Sendable {
    public let pattern: String
    
    public init(_ pattern: String) {
        self.pattern = pattern
    }
    
    public func toCypher() throws -> CypherFragment {
        return CypherFragment(query: "EXISTS { \(pattern) }", parameters: [:])
    }
}