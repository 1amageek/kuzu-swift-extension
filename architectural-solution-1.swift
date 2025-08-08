// Solution 1: Unified Component-Based Architecture

import Foundation

// MARK: - Updated QueryBuilder with Consistent Types

@resultBuilder
public struct QueryBuilder {
    // All methods return [QueryComponent] for consistency
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
    
    public static func buildLimitedAvailability(_ component: [QueryComponent]) -> [QueryComponent] {
        component
    }
    
    // Only buildFinalResult creates the final Query
    public static func buildFinalResult(_ component: [QueryComponent]) -> [QueryComponent] {
        component
    }
}

// MARK: - Query Initialization

public extension Query {
    /// Creates a query using the updated QueryBuilder
    init(@QueryBuilder _ builder: () -> [QueryComponent]) {
        self.init(components: builder())
    }
}

// MARK: - Updated GraphContext Methods

public extension GraphContext {
    func query(@QueryBuilder _ builder: () -> [QueryComponent]) async throws -> QueryResult {
        let query = Query(components: builder())
        let cypher = try CypherCompiler.compile(query)
        return try await raw(cypher.query, bindings: cypher.parameters)
    }
    
    func queryValue<T>(@QueryBuilder _ builder: () -> [QueryComponent], at column: Int = 0) async throws -> T {
        let query = Query(components: builder())
        let cypher = try CypherCompiler.compile(query)
        let result = try await raw(cypher.query, bindings: cypher.parameters)
        return try ResultMapper.value(result, at: column)
    }
    
    // ... similar updates for all query methods
}

// MARK: - Updated Subquery Methods

public extension Subquery {
    /// Creates a scalar subquery
    static func scalar(@QueryBuilder _ builder: () -> [QueryComponent]) -> Subquery {
        .scalar(Query(components: builder()))
    }
    
    /// Creates a list subquery
    static func list(@QueryBuilder _ builder: () -> [QueryComponent]) -> Subquery {
        .list(Query(components: builder()))
    }
    
    /// Creates an exists subquery
    static func exists(@QueryBuilder _ builder: () -> [QueryComponent]) -> Subquery {
        .exists(Query(components: builder()))
    }
}

// MARK: - Updated Let Methods

public extension Let {
    public static func scalar(_ variable: String, @QueryBuilder _ builder: () -> [QueryComponent]) -> Let {
        Let(variable: variable, expression: .subquery(.scalar(Query(components: builder()))))
    }
    
    public static func list(_ variable: String, @QueryBuilder _ builder: () -> [QueryComponent]) -> Let {
        Let(variable: variable, expression: .subquery(.list(Query(components: builder()))))
    }
}

// MARK: - Usage Examples

/*
// ✅ Now works with full control flow support
let complexQuery = Query {
    Match.node(User.self, alias: "u")
    
    // Control flow now works properly
    if includeFilter {
        Where(PropertyReference(alias: "u", property: "age") > 18)
    }
    
    // Loops work
    for category in categories {
        Match.edge(BelongsTo.self, from: "u", to: category)
    }
    
    Return.items(.alias("u"))
}

// ✅ Subqueries with control flow work
Let.scalar("maxAge") {
    Match.node(Person.self, alias: "p")
    
    if includeActive {
        Where(PropertyReference(alias: "p", property: "active") == true)
    }
    
    Return.aggregate(.max(PropertyReference(alias: "p", property: "age")))
}
*/