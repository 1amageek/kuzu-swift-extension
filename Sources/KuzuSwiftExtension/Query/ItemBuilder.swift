import Foundation

/// Protocol for types that can build collections of items
public protocol ItemBuilder {
    associatedtype Item
    
    /// Build a collection from an array of items
    static func build(_ items: [Item]) -> Self
}

/// Handles variadic item construction without arbitrary limits
public struct VariadicItemBuilder<Container: ItemBuilder> {
    
    /// Builds containers from arrays without arbitrary limits
    public static func build(_ items: [Container.Item]) -> Container {
        return Container.build(items)
    }
    
    /// Provides variadic convenience methods with proper array conversion
    public static func build(_ items: Container.Item...) -> Container {
        return Container.build(items)
    }
}

/// Extension to handle common array patterns
public extension Array {
    /// Converts array to container type that conforms to ItemBuilder
    func toContainer<T>() -> T where T: ItemBuilder, T.Item == Element {
        return T.build(self)
    }
}

/// Helper functions for common item building patterns
public enum ItemBuilderHelper {
    
    /// Builds items with a maximum count (if needed for compatibility)
    public static func buildWithLimit<T>(_ items: [T], limit: Int? = nil) -> [T] {
        if let limit = limit {
            return Array(items.prefix(limit))
        }
        return items
    }
    
    /// Flattens nested arrays of items
    public static func flatten<T>(_ items: [[T]]) -> [T] {
        return items.flatMap { $0 }
    }
    
    /// Filters nil values and unwraps optionals
    public static func compactMap<T>(_ items: [T?]) -> [T] {
        return items.compactMap { $0 }
    }
}