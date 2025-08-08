// Solution 3: Wrapper-Based Migration Architecture

import Foundation

// MARK: - New Consistent QueryBuilder (target architecture)

@resultBuilder
public struct QueryBuilder {
    public static func buildBlock(_ components: QueryComponent...) -> [QueryComponent] {
        Array(components)
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
    
    public static func buildFinalResult(_ component: [QueryComponent]) -> [QueryComponent] {
        component
    }
}

// MARK: - Legacy QueryBuilder (for backward compatibility)

@available(*, deprecated, message: "Use the new QueryBuilder which supports control flow. This will be removed in a future version.")
@resultBuilder
public struct LegacyQueryBuilder {
    public static func buildBlock(_ components: QueryComponent...) -> Query {
        Query(components: components)
    }
    
    public static func buildExpression(_ expression: QueryComponent) -> QueryComponent {
        expression
    }
}

// MARK: - QueryBuilding Protocol (abstraction layer)

public protocol QueryBuilding {
    func toQuery() -> Query
}

extension Query: QueryBuilding {
    public func toQuery() -> Query { self }
}

extension Array: QueryBuilding where Element == QueryComponent {
    public func toQuery() -> Query {
        Query(components: self)
    }
}

// MARK: - Universal Builder Function

/// Universal query building function that works with both old and new patterns
public func buildQuery<T: QueryBuilding>(@QueryBuilder _ builder: () -> T) -> Query {
    builder().toQuery()
}

// MARK: - GraphContext with Migration Support

public extension GraphContext {
    // New API (recommended)
    func query(@QueryBuilder _ builder: () -> [QueryComponent]) async throws -> QueryResult {
        let query = Query(components: builder())
        let cypher = try CypherCompiler.compile(query)
        return try await raw(cypher.query, bindings: cypher.parameters)
    }
    
    // Legacy API (maintained for compatibility)
    @available(*, deprecated, message: "Use the new query method which supports control flow")
    func queryLegacy(@LegacyQueryBuilder _ builder: () -> Query) async throws -> QueryResult {
        let query = builder()
        let cypher = try CypherCompiler.compile(query)
        return try await raw(cypher.query, bindings: cypher.parameters)
    }
    
    // Universal API (works with both)
    func queryUniversal<T: QueryBuilding>(@QueryBuilder _ builder: () -> T) async throws -> QueryResult {
        let query = builder().toQuery()
        let cypher = try CypherCompiler.compile(query)
        return try await raw(cypher.query, bindings: cypher.parameters)
    }
}

// MARK: - Migration Helper for Subqueries

public struct SubqueryBuilder {
    public static func scalar<T: QueryBuilding>(@QueryBuilder _ builder: () -> T) -> Subquery {
        .scalar(builder().toQuery())
    }
    
    public static func list<T: QueryBuilding>(@QueryBuilder _ builder: () -> T) -> Subquery {
        .list(builder().toQuery())
    }
    
    public static func exists<T: QueryBuilding>(@QueryBuilder _ builder: () -> T) -> Subquery {
        .exists(builder().toQuery())
    }
}

// MARK: - Updated Subquery Extension

public extension Subquery {
    // New API
    static func scalar(@QueryBuilder _ builder: () -> [QueryComponent]) -> Subquery {
        .scalar(Query(components: builder()))
    }
    
    static func list(@QueryBuilder _ builder: () -> [QueryComponent]) -> Subquery {
        .list(Query(components: builder()))
    }
    
    static func exists(@QueryBuilder _ builder: () -> [QueryComponent]) -> Subquery {
        .exists(Query(components: builder()))
    }
    
    // Legacy API (deprecated but functional)
    @available(*, deprecated, message: "Use the new scalar method which supports control flow")
    static func scalarLegacy(@LegacyQueryBuilder _ builder: () -> Query) -> Subquery {
        .scalar(builder())
    }
}

// MARK: - Migration Path Examples

/*
// Phase 1: Existing code continues to work (with deprecation warnings)
Let.scalarLegacy("count") {
    Match.node(User.self, alias: "u")
    Return.count()
}

// Phase 2: New code uses new API with control flow support
Let.scalar("count") {
    Match.node(User.self, alias: "u")
    
    if activeOnly {
        Where(PropertyReference(alias: "u", property: "active") == true)
    }
    
    Return.count()
}

// Phase 3: Universal builder for transition period
context.queryUniversal {
    Match.node(User.self, alias: "u")
    
    if complexCondition {
        Where(PropertyReference(alias: "u", property: "age") > 18)
        
        for category in categories {
            Match.edge(BelongsTo.self, from: "u", to: category)
        }
    }
    
    Return.items(.alias("u"))
}
*/