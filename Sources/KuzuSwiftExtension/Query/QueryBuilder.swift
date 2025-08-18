import Foundation
import Kuzu

/// Query builder that automatically creates TupleQuery for multiple components (similar to SwiftUI's ViewBuilder)
@resultBuilder
public struct QueryBuilder {
    
    /// Builds an expression within the builder
    public static func buildExpression<Content>(_ content: Content) -> Content where Content: QueryComponent {
        content
    }
    
    /// Builds an empty query from a block containing no statements
    public static func buildBlock() -> EmptyQuery {
        EmptyQuery()
    }
    
    /// Passes a single component through unmodified
    public static func buildBlock<Content>(_ content: Content) -> Content where Content: QueryComponent {
        content
    }
    
    /// Builds multiple components into a TupleQuery using parameter packs
    public static func buildBlock<each Content>(_ content: repeat each Content) -> TupleQuery<repeat each Content> where repeat each Content: QueryComponent {
        TupleQuery(repeat each content)
    }
    
    // MARK: - Control Flow
    
    /// Optional (if without else)
    public static func buildOptional<Component>(_ component: Component?) -> Component? where Component: QueryComponent {
        component
    }
    
    /// Either first branch (if-else)
    public static func buildEither<TrueContent, FalseContent>(first component: TrueContent) -> ConditionalContent<TrueContent, FalseContent> where TrueContent: QueryComponent, FalseContent: QueryComponent {
        ConditionalContent(content: .first(component))
    }
    
    /// Either second branch (if-else)  
    public static func buildEither<TrueContent, FalseContent>(second component: FalseContent) -> ConditionalContent<TrueContent, FalseContent> where TrueContent: QueryComponent, FalseContent: QueryComponent {
        ConditionalContent(content: .second(component))
    }
    
    /// Array (for-in loops)
    public static func buildArray<Component>(_ components: [Component]) -> ForEachQuery<Component> where Component: QueryComponent {
        ForEachQuery(components)
    }
    
    /// Limited availability (@available)
    public static func buildLimitedAvailability<Component>(_ component: Component) -> Component where Component: QueryComponent {
        component
    }
    
    /// Final result (explicit return statement)
    public static func buildFinalResult<Component>(_ component: Component) -> Component where Component: QueryComponent {
        component
    }
}

// MARK: - ConditionalContent (like SwiftUI)

public struct ConditionalContent<TrueContent, FalseContent>: QueryComponent where TrueContent: QueryComponent, FalseContent: QueryComponent {
    enum Content {
        case first(TrueContent)
        case second(FalseContent)
    }
    
    let content: Content
    
    public typealias Result = TrueContent.Result // Both branches should return same type ideally
    
    public func toCypher() throws -> CypherFragment {
        switch content {
        case .first(let component):
            return try component.toCypher()
        case .second(let component):
            return try component.toCypher()
        }
    }
    
    public func mapResult(_ result: QueryResult, decoder: KuzuDecoder) throws -> Result {
        switch content {
        case .first(let component):
            return try component.mapResult(result, decoder: decoder)
        case .second(let component):
            // This is a simplification - in practice you might need type erasure
            return try component.mapResult(result, decoder: decoder) as! Result
        }
    }
}

// MARK: - ForEachQuery (like SwiftUI's ForEach)

public struct ForEachQuery<Component: QueryComponent>: QueryComponent {
    public typealias Result = [Component.Result]
    
    let components: [Component]
    
    init(_ components: [Component]) {
        self.components = components
    }
    
    public func toCypher() throws -> CypherFragment {
        var query = ""
        var parameters: [String: any Sendable] = [:]
        
        for component in components {
            let cypher = try component.toCypher()
            if !query.isEmpty && !cypher.query.isEmpty {
                query += "\n"
            }
            query += cypher.query
            parameters.merge(cypher.parameters) { _, new in new }
        }
        
        return CypherFragment(query: query, parameters: parameters)
    }
    
    public func mapResult(_ result: QueryResult, decoder: KuzuDecoder) throws -> Result {
        // For array of components, we need to handle multiple results
        var results: [Component.Result] = []
        for component in components {
            let componentResult = try component.mapResult(result, decoder: decoder)
            results.append(componentResult)
        }
        return results
    }
}