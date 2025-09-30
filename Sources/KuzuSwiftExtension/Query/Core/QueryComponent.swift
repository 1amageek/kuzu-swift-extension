import Foundation
import Kuzu

/// Base protocol for all query components (similar to SwiftUI's View)
public protocol QueryComponent {
    /// The type of result this component produces
    associatedtype Result
    
    /// Whether this component should be included in RETURN clause
    var isReturnable: Bool { get }
    
    /// Converts the component to a Cypher fragment
    func toCypher() throws -> CypherFragment
    
    /// Maps query result to the expected Result type
    func mapResult(_ result: QueryResult, decoder: KuzuDecoder) throws -> Result
}

/// Default implementation
public extension QueryComponent {
    var isReturnable: Bool { true }
    
    func mapResult(_ result: QueryResult, decoder: KuzuDecoder) throws -> Result {
        // Default implementation for simple types
        guard result.hasNext() else {
            // Try to return a default value for common types
            if Result.self == Void.self {
                return () as! Result
            }
            throw KuzuError.noResults
        }
        
        guard let row = try result.getNext() else {
            throw KuzuError.noResults
        }
        
        let value = try row.getValue(0)
        
        // Try to cast directly
        if let typedValue = value as? Result {
            return typedValue
        }
        
        // For Decodable types, try to decode from KuzuNode
        if let decodableType = Result.self as? any Decodable.Type,
           let kuzuNode = value as? KuzuNode {
            return try decoder.decode(decodableType, from: kuzuNode.properties) as! Result
        }
        
        // Last resort: force cast
        return value as! Result
    }
}

/// Protocol for components that can be referenced by alias
public protocol AliasedComponent: QueryComponent {
    var alias: String { get }
}

/// Protocol for components that modify other components
public protocol ModifierComponent: QueryComponent {
    associatedtype Modified: QueryComponent
    var component: Modified { get }
}

/// A query component that produces no result
public struct EmptyQuery: QueryComponent {
    public typealias Result = Void
    public var isReturnable: Bool { false }
    
    public init() {}
    
    public func toCypher() throws -> CypherFragment {
        CypherFragment(query: "")
    }
    
    public func mapResult(_ result: QueryResult, decoder: KuzuDecoder) throws -> Result {
        // EmptyQuery always returns void
        return ()
    }
}

/// Type-erased query component
public struct AnyQueryComponent: QueryComponent {
    public typealias Result = Any
    
    private let _isReturnable: Bool
    private let _toCypher: () throws -> CypherFragment
    
    public var isReturnable: Bool { _isReturnable }
    
    public init<T: QueryComponent>(_ component: T) {
        self._isReturnable = component.isReturnable
        self._toCypher = component.toCypher
    }
    
    public func toCypher() throws -> CypherFragment {
        try _toCypher()
    }
    
    public func mapResult(_ result: QueryResult, decoder: KuzuDecoder) throws -> Result {
        // For AnyQueryComponent, return the first value as Any
        guard result.hasNext() else {
            throw KuzuError.noResults
        }
        
        guard let row = try result.getNext() else {
            throw KuzuError.noResults
        }

        guard let value = try row.getValue(0) else {
            throw KuzuError.invalidOperation(message: "Result value is null")
        }

        return value
    }
}