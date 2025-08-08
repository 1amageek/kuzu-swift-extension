import Foundation

@resultBuilder
public struct QueryBuilder {
    // Build a block of components - accepts both variadic and array
    public static func buildBlock(_ components: QueryComponent...) -> [QueryComponent] {
        components
    }
    
    public static func buildBlock(_ components: [QueryComponent]...) -> [QueryComponent] {
        components.flatMap { $0 }
    }
    
    // Build an expression (single component)
    public static func buildExpression(_ expression: QueryComponent) -> [QueryComponent] {
        [expression]
    }
    
    public static func buildExpression(_ expression: [QueryComponent]) -> [QueryComponent] {
        expression
    }
    
    // Build optional components (if without else)
    public static func buildOptional(_ component: [QueryComponent]?) -> [QueryComponent] {
        component ?? []
    }
    
    // Build either first branch (if-else)
    public static func buildEither(first component: [QueryComponent]) -> [QueryComponent] {
        component
    }
    
    // Build either second branch (if-else)
    public static func buildEither(second component: [QueryComponent]) -> [QueryComponent] {
        component
    }
    
    // Build array (for-in loops)
    public static func buildArray(_ components: [[QueryComponent]]) -> [QueryComponent] {
        components.flatMap { $0 }
    }
    
    // Build limited availability (@available)
    public static func buildLimitedAvailability(_ component: [QueryComponent]) -> [QueryComponent] {
        component
    }
    
    // Final result transformation
    public static func buildFinalResult(_ components: [QueryComponent]) -> [QueryComponent] {
        components
    }
}