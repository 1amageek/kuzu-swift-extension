import Foundation

@resultBuilder
public struct QueryBuilder {
    public static func buildBlock(_ components: QueryComponent...) -> Query {
        Query(components: components)
    }
    
    public static func buildArray(_ components: [[QueryComponent]]) -> [QueryComponent] {
        components.flatMap { $0 }
    }
    
    public static func buildEither(first component: [QueryComponent]) -> [QueryComponent] {
        component
    }
    
    public static func buildEither(second component: [QueryComponent]) -> [QueryComponent] {
        component
    }
    
    public static func buildOptional(_ component: [QueryComponent]?) -> [QueryComponent] {
        component ?? []
    }
    
    public static func buildExpression(_ expression: QueryComponent) -> [QueryComponent] {
        [expression]
    }
    
    public static func buildFinalResult(_ component: [QueryComponent]) -> Query {
        Query(components: component)
    }
}