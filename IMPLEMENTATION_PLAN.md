# KuzuSwiftExtension Query DSL Implementation Plan

## Overview
This document outlines the implementation plan for enhancing the Query DSL capabilities of KuzuSwiftExtension. The plan addresses missing features and improvements identified through developer requirements analysis.

## Current State Analysis

### ✅ Already Implemented Features
- **Transaction Integration**: `TransactionalGraphContext+QueryDSL.swift`
- **Type-safe Edge Properties**: `EdgePath<E,V>` with KeyPath support
- **Aggregation Functions**: COUNT, SUM, AVG, MIN, MAX, GROUP BY
- **OPTIONAL MATCH**: Full support with predicates
- **UNWIND**: List expansion support
- **WITH Clause**: Pipeline operations with ordering and limits
- **MERGE**: Create-or-match pattern support
- **EXISTS Pattern**: Subgraph existence checks
- **Path Patterns**: Variable length, shortest path, all paths
- **Error Handling**: Comprehensive error types and context

### 🚧 Features Requiring Implementation
1. **NOT EXISTS Pattern**
2. **Result Builder Improvements** (control flow support)
3. **Debug Support** (cypherString, explainPlan)
4. **Subqueries** (scalar, list, exists)
5. **CALL Clause** and algorithm wrappers

## Implementation Phases

### Phase 1: NOT EXISTS Pattern Implementation
**Priority**: High  
**Estimated Effort**: 2-3 hours  
**Dependencies**: Existing Exists and Predicate infrastructure

#### 1.1 Implementation Details

**File**: `Sources/KuzuSwiftExtension/Query/NotExists.swift`

```swift
import Foundation

/// Represents a NOT EXISTS pattern for checking non-existence of subgraphs
public struct NotExists {
    let pattern: ExistsPattern
    
    private init(pattern: ExistsPattern) {
        self.pattern = pattern
    }
    
    /// Creates a NOT EXISTS check for a node
    public static func node<T: _KuzuGraphModel>(
        _ type: T.Type,
        alias: String? = nil,
        where predicate: Predicate? = nil
    ) -> NotExists {
        let nodeAlias = alias ?? String(describing: type).lowercased()
        let pattern = ExistsPattern.node(
            type: String(describing: type),
            alias: nodeAlias,
            predicate: predicate
        )
        return NotExists(pattern: pattern)
    }
    
    /// Creates a NOT EXISTS check for an edge
    public static func edge<T: _KuzuGraphModel>(
        _ type: T.Type,
        from: String,
        to: String,
        alias: String? = nil
    ) -> NotExists {
        let edgeAlias = alias ?? String(describing: type).lowercased()
        let pattern = ExistsPattern.edge(
            type: String(describing: type),
            from: from,
            to: to,
            alias: edgeAlias
        )
        return NotExists(pattern: pattern)
    }
    
    /// Converts to Cypher fragment
    func toCypher() throws -> CypherFragment {
        let existsCypher = try pattern.toCypher()
        return CypherFragment(
            query: "NOT \(existsCypher.query)",
            parameters: existsCypher.parameters
        )
    }
}
```

**Integration with Predicate**:
```swift
// Extension in Predicate.swift
public extension Predicate {
    /// Creates a NOT EXISTS predicate
    static func notExists(_ notExists: NotExists) -> Predicate {
        Predicate(node: .notExists(notExists))
    }
}
```

#### 1.2 Usage Examples
```swift
// Find users without any posts
let query = Query {
    Match.node(User.self, alias: "u")
        .where(.notExists(
            NotExists.edge(Wrote.self, from: "u", to: "p")
        ))
    Return.node("u")
}

// Find posts without likes
let query = Query {
    Match.node(Post.self, alias: "p")
        .where(.notExists(
            NotExists.edge(Likes.self, from: "_", to: "p")
        ))
    Return.property(path(\Post.title, on: "p"))
}
```

### Phase 2: Result Builder Improvements
**Priority**: High  
**Estimated Effort**: 4-5 hours  
**Dependencies**: Swift 5.9+ Result Builder features

#### 2.1 Enhanced QueryBuilder

**File**: `Sources/KuzuSwiftExtension/Query/QueryBuilder+ControlFlow.swift`

```swift
import Foundation

@resultBuilder
public struct EnhancedQueryBuilder {
    // Existing build methods...
    
    // Add support for if-else
    public static func buildEither(first component: [QueryComponent]) -> [QueryComponent] {
        component
    }
    
    public static func buildEither(second component: [QueryComponent]) -> [QueryComponent] {
        component
    }
    
    // Add support for optional (if without else)
    public static func buildOptional(_ component: [QueryComponent]?) -> [QueryComponent] {
        component ?? []
    }
    
    // Add support for loops
    public static func buildArray(_ components: [[QueryComponent]]) -> [QueryComponent] {
        components.flatMap { $0 }
    }
    
    // Support for limited availability
    public static func buildLimitedAvailability(_ component: [QueryComponent]) -> [QueryComponent] {
        component
    }
}
```

#### 2.2 Usage Examples
```swift
// Conditional query building
let query = Query {
    Match.node(User.self, alias: "u")
    
    if includeFollowers {
        OptionalMatch.edge(Follows.self, from: "f", to: "u")
        With.items("u", .count("f", as: "followerCount"))
    }
    
    if let cityFilter = city {
        Where(path(\User.city, on: "u") == cityFilter)
    }
    
    for property in sortProperties {
        Return.orderBy(property)
    }
    
    Return.node("u")
}
```

### Phase 3: Debug Support Implementation
**Priority**: Medium  
**Estimated Effort**: 3-4 hours  
**Dependencies**: Query compilation infrastructure

#### 3.1 Query Debug Interface

**File**: `Sources/KuzuSwiftExtension/Query/QueryDebug.swift`

```swift
import Foundation

/// Debug configuration for queries
public struct QueryDebugConfiguration {
    public var printCypher: Bool = false
    public var printParameters: Bool = false
    public var printExecutionTime: Bool = false
    public var explainPlan: Bool = false
    
    public static var verbose: QueryDebugConfiguration {
        QueryDebugConfiguration(
            printCypher: true,
            printParameters: true,
            printExecutionTime: true,
            explainPlan: false
        )
    }
    
    public static var silent: QueryDebugConfiguration {
        QueryDebugConfiguration()
    }
}

/// Global debug manager
public enum QueryDebug {
    public static var configuration = QueryDebugConfiguration.silent
    
    public static func enable(verbose: Bool = false) {
        configuration = verbose ? .verbose : QueryDebugConfiguration(printCypher: true)
    }
    
    public static func disable() {
        configuration = .silent
    }
}
```

#### 3.2 Query Extension for Debug

```swift
public extension Query {
    /// Returns the compiled Cypher string
    var cypherString: String? {
        try? CypherCompiler.compile(self).query
    }
    
    /// Returns debug information
    func debugInfo() throws -> QueryDebugInfo {
        let compiled = try CypherCompiler.compile(self)
        return QueryDebugInfo(
            cypher: compiled.query,
            parameters: compiled.parameters,
            analysis: try QueryIntrospection.analyze(self)
        )
    }
}

public struct QueryDebugInfo {
    public let cypher: String
    public let parameters: [String: any Sendable]
    public let analysis: QueryAnalysis
    
    public var formattedDescription: String {
        """
        === Query Debug Info ===
        Cypher:
        \(cypher)
        
        Parameters:
        \(parameters.map { "  \($0.key): \($0.value)" }.joined(separator: "\n"))
        
        Analysis:
        - Node Types: \(analysis.nodeTypes.joined(separator: ", "))
        - Edge Types: \(analysis.edgeTypes.joined(separator: ", "))
        - Operations: \(analysis.operations.joined(separator: ", "))
        - Has Aggregation: \(analysis.hasAggregation)
        - Complexity: \(analysis.estimatedComplexity)
        """
    }
}
```

### Phase 4: Subquery Implementation
**Priority**: Medium  
**Estimated Effort**: 6-8 hours  
**Dependencies**: Query DSL foundation

#### 4.1 Subquery Types

**File**: `Sources/KuzuSwiftExtension/Query/Subquery.swift`

```swift
import Foundation

/// Represents different types of subqueries
public enum Subquery: QueryComponent {
    case scalar(Query)
    case list(Query)
    case exists(Query)
    case call(procedure: String, parameters: [String: any Sendable])
    
    public func toCypher() throws -> CypherFragment {
        switch self {
        case .scalar(let query):
            let compiled = try CypherCompiler.compile(query)
            return CypherFragment(
                query: "(\(compiled.query))",
                parameters: compiled.parameters
            )
            
        case .list(let query):
            let compiled = try CypherCompiler.compile(query)
            return CypherFragment(
                query: "[(\(compiled.query))]",
                parameters: compiled.parameters
            )
            
        case .exists(let query):
            let compiled = try CypherCompiler.compile(query)
            return CypherFragment(
                query: "EXISTS { \(compiled.query) }",
                parameters: compiled.parameters
            )
            
        case .call(let procedure, let parameters):
            let paramString = parameters.isEmpty ? "" : 
                "(" + parameters.map { "\($0.key): $\($0.key)" }.joined(separator: ", ") + ")"
            return CypherFragment(
                query: "CALL \(procedure)\(paramString)",
                parameters: parameters
            )
        }
    }
}
```

#### 4.2 Builder Methods

```swift
public extension Subquery {
    /// Creates a scalar subquery
    static func scalar(@QueryBuilder _ builder: () -> Query) -> Subquery {
        .scalar(builder())
    }
    
    /// Creates a list subquery
    static func list(@QueryBuilder _ builder: () -> Query) -> Subquery {
        .list(builder())
    }
    
    /// Creates an exists subquery
    static func exists(@QueryBuilder _ builder: () -> Query) -> Subquery {
        .exists(builder())
    }
}
```

#### 4.3 Usage Examples
```swift
// Scalar subquery - get max follower count
let query = Query {
    Match.node(User.self, alias: "u")
    Let("maxFollowers", Subquery.scalar {
        Match.edge(Follows.self, from: "_", to: "u2")
        Return.aggregate(.count("u2"))
    })
    Where(path(\User.followerCount, on: "u") == Ref("maxFollowers"))
    Return.node("u")
}

// List subquery - collect related items
let query = Query {
    Match.node(User.self, alias: "u")
    Return.items(
        .alias("u"),
        .aliased(
            expression: Subquery.list {
                Match.edge(Wrote.self, from: "u", to: "p")
                    .and(Post.self, alias: "p")
                Return.property(path(\Post.title, on: "p"))
            }.cypherString,
            alias: "posts"
        )
    )
}
```

### Phase 5: CALL Clause and Algorithm Wrappers
**Priority**: Low  
**Estimated Effort**: 4-5 hours  
**Dependencies**: Kuzu algorithm extensions

#### 5.1 CALL Clause Support

**File**: `Sources/KuzuSwiftExtension/Query/Call.swift`

```swift
import Foundation

/// Represents a CALL clause for stored procedures and algorithms
public struct Call: QueryComponent {
    let procedure: String
    let parameters: [String: any Sendable]
    let yields: [String]?
    
    private init(procedure: String, parameters: [String: any Sendable], yields: [String]?) {
        self.procedure = procedure
        self.parameters = parameters
        self.yields = yields
    }
    
    /// Calls a stored procedure
    public static func procedure(
        _ name: String,
        parameters: [String: any Sendable] = [:],
        yields: [String]? = nil
    ) -> Call {
        Call(procedure: name, parameters: parameters, yields: yields)
    }
    
    public func toCypher() throws -> CypherFragment {
        var query = "CALL \(procedure)"
        
        if !parameters.isEmpty {
            let paramList = parameters.map { "\($0.key): $\($0.key)" }.joined(separator: ", ")
            query += "(\(paramList))"
        }
        
        if let yields = yields {
            query += " YIELD \(yields.joined(separator: ", "))"
        }
        
        return CypherFragment(query: query, parameters: parameters)
    }
}
```

#### 5.2 Algorithm Wrappers

**File**: `Sources/KuzuSwiftExtension/Query/Algorithms.swift`

```swift
import Foundation

/// Graph algorithm wrappers
public struct GraphAlgorithms {
    
    /// PageRank algorithm
    public struct PageRank {
        public static func call(
            graph: String,
            damping: Double = 0.85,
            iterations: Int = 20,
            tolerance: Double = 1e-6
        ) -> Call {
            Call.procedure(
                "gds.pageRank",
                parameters: [
                    "graph": graph,
                    "damping": damping,
                    "iterations": iterations,
                    "tolerance": tolerance
                ],
                yields: ["nodeId", "score"]
            )
        }
    }
    
    /// Louvain community detection
    public struct Louvain {
        public static func call(
            graph: String,
            seedProperty: String? = nil,
            tolerance: Double = 0.0001
        ) -> Call {
            var params: [String: any Sendable] = [
                "graph": graph,
                "tolerance": tolerance
            ]
            if let seed = seedProperty {
                params["seedProperty"] = seed
            }
            
            return Call.procedure(
                "gds.louvain",
                parameters: params,
                yields: ["nodeId", "communityId"]
            )
        }
    }
    
    /// Connected components
    public struct ConnectedComponents {
        public static func call(
            graph: String,
            seedProperty: String? = nil
        ) -> Call {
            var params: [String: any Sendable] = ["graph": graph]
            if let seed = seedProperty {
                params["seedProperty"] = seed
            }
            
            return Call.procedure(
                "gds.wcc",
                parameters: params,
                yields: ["nodeId", "componentId"]
            )
        }
    }
    
    /// Shortest path between two nodes
    public struct ShortestPath {
        public static func dijkstra(
            source: String,
            target: String,
            weightProperty: String? = nil
        ) -> Call {
            var params: [String: any Sendable] = [
                "source": source,
                "target": target
            ]
            if let weight = weightProperty {
                params["weightProperty"] = weight
            }
            
            return Call.procedure(
                "gds.shortestPath.dijkstra",
                parameters: params,
                yields: ["path", "cost"]
            )
        }
    }
}
```

#### 5.3 Usage Examples
```swift
// PageRank calculation
let query = Query {
    GraphAlgorithms.PageRank.call(
        graph: "social_network",
        damping: 0.85,
        iterations: 50
    )
    Return.items(
        .alias("nodeId"),
        .alias("score")
    ).orderBy(.descending("score"))
     .limit(10)
}

// Community detection
let query = Query {
    GraphAlgorithms.Louvain.call(
        graph: "social_network",
        tolerance: 0.001
    )
    With.items(
        .alias("nodeId"),
        .alias("communityId")
    )
    Match.node(User.self, alias: "u")
        .where(path(\User.id, on: "u") == Ref("nodeId"))
    Return.items(
        .property(path(\User.name, on: "u")),
        .alias("communityId")
    ).orderBy(.ascending("communityId"))
}

// Shortest path
let query = Query {
    Match.node(User.self, alias: "source")
        .where(path(\User.name, on: "source") == "Alice")
    Match.node(User.self, alias: "target")
        .where(path(\User.name, on: "target") == "Bob")
    GraphAlgorithms.ShortestPath.dijkstra(
        source: "source",
        target: "target",
        weightProperty: "distance"
    )
    Return.items(
        .alias("path"),
        .alias("cost")
    )
}
```

## Testing Strategy

### Unit Tests
Each new component should have comprehensive unit tests:

1. **NOT EXISTS Tests**
   - Pattern creation
   - Cypher compilation
   - Integration with predicates

2. **Result Builder Tests**
   - Conditional compilation
   - Loop expansion
   - Optional handling

3. **Debug Support Tests**
   - Configuration management
   - Output formatting
   - Performance impact

4. **Subquery Tests**
   - Scalar subqueries
   - List subqueries
   - Exists subqueries
   - Parameter passing

5. **CALL Clause Tests**
   - Procedure invocation
   - Parameter binding
   - Yield clause handling

### Integration Tests
End-to-end tests combining multiple features:

```swift
func testComplexQueryWithAllFeatures() async throws {
    let query = Query {
        // Main query with subquery
        Match.node(User.self, alias: "u")
        
        // NOT EXISTS check
        Where(.notExists(
            NotExists.edge(Blocked.self, from: "u", to: "_")
        ))
        
        // Conditional logic
        if includeRecommendations {
            GraphAlgorithms.PageRank.call(
                graph: "social_network"
            )
        }
        
        // Subquery for aggregation
        Let("avgPosts", Subquery.scalar {
            Match.node(User.self, alias: "u2")
            Match.edge(Wrote.self, from: "u2", to: "p")
            Return.aggregate(.avg(PropertyReference(alias: "p", property: "likes")))
        })
        
        // Final return
        Return.items(
            .alias("u"),
            .alias("avgPosts")
        )
    }
    
    // Debug output
    if QueryDebug.configuration.printCypher {
        print(query.cypherString ?? "")
    }
}
```

## Migration Path

### Backward Compatibility
All new features are additive and maintain backward compatibility:
- Existing queries continue to work unchanged
- New APIs are opt-in through new methods/types
- No breaking changes to existing interfaces

### Deprecation Strategy
No deprecations required as all changes are additive.

## Performance Considerations

1. **Query Compilation Cache**
   - Consider caching compiled queries for repeated use
   - Implement PreparedStatement support for parameterized queries

2. **Debug Mode Impact**
   - Debug features should have zero cost when disabled
   - Use conditional compilation where possible

3. **Subquery Optimization**
   - Encourage use of WITH clauses over subqueries where appropriate
   - Document performance implications

## Documentation Requirements

### API Documentation
- Comprehensive DocC comments for all public APIs
- Usage examples in documentation
- Performance notes where relevant

### Migration Guide
- Examples showing how to adopt new features
- Best practices for query optimization
- Common patterns and anti-patterns

### Tutorial Content
1. "Advanced Query Patterns with NOT EXISTS"
2. "Building Dynamic Queries with Control Flow"
3. "Debugging Complex Graph Queries"
4. "Using Subqueries Effectively"
5. "Graph Algorithms in KuzuSwiftExtension"

## Timeline

### Week 1-2: Core Features
- ✅ NOT EXISTS implementation
- ✅ Result Builder improvements
- ✅ Basic debug support

### Week 3-4: Advanced Features
- ⏳ Subquery implementation
- ⏳ CALL clause support
- ⏳ Algorithm wrappers

### Week 5: Polish & Documentation
- 📝 API documentation
- 🧪 Integration tests
- 📚 Tutorial content

## Success Metrics

1. **Code Coverage**: >90% for new features
2. **Performance**: <5% overhead for debug features when disabled
3. **API Usability**: Intuitive APIs requiring minimal documentation lookup
4. **Compilation Time**: <10% increase in build time

## Risk Mitigation

### Technical Risks
1. **Swift Compiler Limitations**: Some Result Builder features may not work as expected
   - Mitigation: Provide alternative APIs using method chaining

2. **Kuzu Version Compatibility**: Algorithm APIs may vary across versions
   - Mitigation: Version detection and conditional compilation

3. **Performance Regression**: Complex queries may compile slowly
   - Mitigation: Query compilation cache and optimization passes

### Schedule Risks
1. **Dependency on Kuzu Updates**: Some features may require Kuzu SDK updates
   - Mitigation: Implement features that work with current version first

2. **Testing Complexity**: Integration tests may reveal unexpected interactions
   - Mitigation: Incremental testing and early integration

## Conclusion

This implementation plan provides a structured approach to enhancing the KuzuSwiftExtension Query DSL. The phased approach ensures that high-priority features are delivered first while maintaining backward compatibility and code quality throughout the process.

The plan balances developer experience improvements with performance considerations, ensuring that the library remains both powerful and efficient. With comprehensive testing and documentation, these enhancements will make KuzuSwiftExtension a more complete and user-friendly solution for graph database operations in Swift.