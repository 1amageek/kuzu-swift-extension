import Foundation

@resultBuilder
public struct QueryBuilder {
    public static func buildBlock(_ components: QueryComponent...) -> [QueryComponent] {
        components
    }
    
    public static func buildBlock() -> [QueryComponent] {
        []
    }
    
    public static func buildExpression<T: _KuzuGraphModel>(_ expression: Match<T>) -> QueryComponent {
        .match(expression.clause)
    }
    
    public static func buildExpression<T: _KuzuGraphModel>(_ expression: Create<T>) -> QueryComponent {
        .create(expression.clause)
    }
    
    public static func buildExpression<T: _KuzuGraphModel>(_ expression: Merge<T>) -> QueryComponent {
        .merge(expression.clause)
    }
    
    public static func buildExpression(_ expression: Set) -> QueryComponent {
        .set(expression.clause)
    }
    
    public static func buildExpression(_ expression: Delete) -> QueryComponent {
        .delete(expression.clause)
    }
    
    public static func buildExpression(_ expression: Return) -> QueryComponent {
        .return(expression.clause)
    }
    
    public static func buildExpression(_ expression: Where) -> QueryComponent {
        .where(expression.clause)
    }
    
    public static func buildExpression(_ expression: OrderBy) -> QueryComponent {
        .orderBy(expression.clause)
    }
    
    public static func buildExpression(_ expression: Limit) -> QueryComponent {
        .limit(expression.count)
    }
    
    public static func buildExpression(_ expression: Skip) -> QueryComponent {
        .skip(expression.count)
    }
    
    public static func buildOptional(_ component: QueryComponent?) -> [QueryComponent] {
        component.map { [$0] } ?? []
    }
    
    public static func buildEither(first component: [QueryComponent]) -> [QueryComponent] {
        component
    }
    
    public static func buildEither(second component: [QueryComponent]) -> [QueryComponent] {
        component
    }
    
    public static func buildArray(_ components: [[QueryComponent]]) -> [QueryComponent] {
        components.flatMap { $0 }
    }
}