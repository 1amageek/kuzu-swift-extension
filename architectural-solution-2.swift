// Solution 2: Dual Builder Architecture

import Foundation

// MARK: - Simple QueryBuilder (no control flow)

@resultBuilder
public struct SimpleQueryBuilder {
    public static func buildBlock(_ components: QueryComponent...) -> Query {
        Query(components: components)
    }
    
    public static func buildExpression(_ expression: QueryComponent) -> QueryComponent {
        expression
    }
}

// MARK: - Advanced QueryBuilder (with control flow)

@resultBuilder
public struct AdvancedQueryBuilder {
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

// MARK: - Query Initialization

public extension Query {
    /// Simple queries without control flow
    init(@SimpleQueryBuilder _ builder: () -> Query) {
        self = builder()
    }
    
    /// Advanced queries with control flow
    init(@AdvancedQueryBuilder _ builder: () -> [QueryComponent]) {
        self.init(components: builder())
    }
}

// MARK: - GraphContext with Both Builders

public extension GraphContext {
    // Simple version
    func query(@SimpleQueryBuilder _ builder: () -> Query) async throws -> QueryResult {
        let query = builder()
        let cypher = try CypherCompiler.compile(query)
        return try await raw(cypher.query, bindings: cypher.parameters)
    }
    
    // Advanced version
    func query(@AdvancedQueryBuilder _ builder: () -> [QueryComponent]) async throws -> QueryResult {
        let query = Query(components: builder())
        let cypher = try CypherCompiler.compile(query)
        return try await raw(cypher.query, bindings: cypher.parameters)
    }
}

// MARK: - Subquery Methods with Both Builders

public extension Subquery {
    // Simple versions (existing API)
    static func scalar(@SimpleQueryBuilder _ builder: () -> Query) -> Subquery {
        .scalar(builder())
    }
    
    static func list(@SimpleQueryBuilder _ builder: () -> Query) -> Subquery {
        .list(builder())
    }
    
    // Advanced versions (with control flow)
    static func scalarAdvanced(@AdvancedQueryBuilder _ builder: () -> [QueryComponent]) -> Subquery {
        .scalar(Query(components: builder()))
    }
    
    static func listAdvanced(@AdvancedQueryBuilder _ builder: () -> [QueryComponent]) -> Subquery {
        .list(Query(components: builder()))
    }
}

// MARK: - Usage Examples

/*
// ✅ Simple queries (no control flow needed)
let simpleQuery = Query {
    Match.node(User.self, alias: "u")
    Return.items(.alias("u"))
}

// ✅ Advanced queries (with control flow)
let advancedQuery = Query {
    Match.node(User.self, alias: "u")
    
    if includeFilter {
        Where(PropertyReference(alias: "u", property: "age") > 18)
    }
    
    for category in categories {
        Match.edge(BelongsTo.self, from: "u", to: category)
    }
    
    Return.items(.alias("u"))
}

// ✅ Simple subqueries
Let.scalar("count", Subquery.scalar {
    Match.node(User.self, alias: "u")
    Return.count()
})

// ✅ Advanced subqueries
Let.scalar("count", Subquery.scalarAdvanced {
    Match.node(User.self, alias: "u")
    
    if activeOnly {
        Where(PropertyReference(alias: "u", property: "active") == true)
    }
    
    Return.count()
})
*/