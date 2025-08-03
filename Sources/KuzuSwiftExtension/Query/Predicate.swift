import Foundation

public enum Predicate<T> {
    case equal(T)
    case notEqual(T)
    case greaterThan(T)
    case lessThan(T)
    case greaterThanOrEqual(T)
    case lessThanOrEqual(T)
    case `in`([T])
    case notIn([T])
    case between(T, T)
    case isNull
    case isNotNull
    case contains(String) // For string types
    case startsWith(String) // For string types
    case endsWith(String) // For string types
    case regex(String) // For string pattern matching
}

// Property predicate wrapper
internal struct PropertyPredicate<Root, Value> {
    let keyPath: KeyPath<Root, Value>
    let condition: (Value) -> Predicate<Value>
}

// MARK: - Operator Overloads

public func == <Root, Value: Equatable>(
    lhs: KeyPath<Root, Value>,
    rhs: Value
) -> PropertyPredicate<Root, Value> {
    PropertyPredicate(keyPath: lhs, condition: { _ in .equal(rhs) })
}

public func != <Root, Value: Equatable>(
    lhs: KeyPath<Root, Value>,
    rhs: Value
) -> PropertyPredicate<Root, Value> {
    PropertyPredicate(keyPath: lhs, condition: { _ in .notEqual(rhs) })
}

public func > <Root, Value: Comparable>(
    lhs: KeyPath<Root, Value>,
    rhs: Value
) -> PropertyPredicate<Root, Value> {
    PropertyPredicate(keyPath: lhs, condition: { _ in .greaterThan(rhs) })
}

public func < <Root, Value: Comparable>(
    lhs: KeyPath<Root, Value>,
    rhs: Value
) -> PropertyPredicate<Root, Value> {
    PropertyPredicate(keyPath: lhs, condition: { _ in .lessThan(rhs) })
}

public func >= <Root, Value: Comparable>(
    lhs: KeyPath<Root, Value>,
    rhs: Value
) -> PropertyPredicate<Root, Value> {
    PropertyPredicate(keyPath: lhs, condition: { _ in .greaterThanOrEqual(rhs) })
}

public func <= <Root, Value: Comparable>(
    lhs: KeyPath<Root, Value>,
    rhs: Value
) -> PropertyPredicate<Root, Value> {
    PropertyPredicate(keyPath: lhs, condition: { _ in .lessThanOrEqual(rhs) })
}

// MARK: - Logical Operators

public struct CompoundPredicate<Root> {
    enum LogicalOperator {
        case and
        case or
        case not
    }
    
    let predicates: [Any]
    let `operator`: LogicalOperator
}

public func && <Root, Value1, Value2>(
    lhs: PropertyPredicate<Root, Value1>,
    rhs: PropertyPredicate<Root, Value2>
) -> CompoundPredicate<Root> {
    CompoundPredicate(predicates: [lhs, rhs], operator: .and)
}

public func || <Root, Value1, Value2>(
    lhs: PropertyPredicate<Root, Value1>,
    rhs: PropertyPredicate<Root, Value2>
) -> CompoundPredicate<Root> {
    CompoundPredicate(predicates: [lhs, rhs], operator: .or)
}

public prefix func ! <Root, Value>(
    predicate: PropertyPredicate<Root, Value>
) -> CompoundPredicate<Root> {
    CompoundPredicate(predicates: [predicate], operator: .not)
}

// MARK: - Collection Extensions

public extension Collection {
    func contains<Root, Value>(_ keyPath: KeyPath<Root, Value>) -> PropertyPredicate<Root, Value>
    where Element == Value {
        PropertyPredicate(keyPath: keyPath, condition: { _ in .in(Array(self)) })
    }
}

// MARK: - String-specific predicates

public extension String {
    static func contains<Root>(_ value: String, on keyPath: KeyPath<Root, String>) -> PropertyPredicate<Root, String> {
        PropertyPredicate(keyPath: keyPath, condition: { _ in .contains(value) })
    }
    
    static func startsWith<Root>(_ value: String, on keyPath: KeyPath<Root, String>) -> PropertyPredicate<Root, String> {
        PropertyPredicate(keyPath: keyPath, condition: { _ in .startsWith(value) })
    }
    
    static func endsWith<Root>(_ value: String, on keyPath: KeyPath<Root, String>) -> PropertyPredicate<Root, String> {
        PropertyPredicate(keyPath: keyPath, condition: { _ in .endsWith(value) })
    }
    
    static func regex<Root>(_ pattern: String, on keyPath: KeyPath<Root, String>) -> PropertyPredicate<Root, String> {
        PropertyPredicate(keyPath: keyPath, condition: { _ in .regex(pattern) })
    }
}