import Testing
import Foundation
import Kuzu
@testable import KuzuSwiftExtension

@Suite("Query DSL Integration Tests")
struct QueryDSLIntegrationTests {
    
    init() {
        // Swift Testing doesn't support async init
    }
    
    func createContext() async throws -> GraphContext {
        
        // Create in-memory database for testing
        let config = GraphConfiguration(
            databasePath: ":memory:",
            options: GraphConfiguration.Options()
        )
        
        let context = try await GraphContext(configuration: config)
        
        // Set up test schema
        _ = try await context.raw("""
            CREATE NODE TABLE User (
                id STRING PRIMARY KEY,
                name STRING,
                age INT64,
                city STRING,
                createdAt TIMESTAMP
            )
            """)
        
        _ = try await context.raw("""
            CREATE NODE TABLE Post (
                id STRING PRIMARY KEY,
                userId STRING,
                content STRING,
                likes INT64,
                createdAt TIMESTAMP
            )
            """)
        
        _ = try await context.raw("""
            CREATE REL TABLE Follows (
                FROM User TO User,
                since TIMESTAMP
            )
            """)
        
        _ = try await context.raw("""
            CREATE REL TABLE Wrote (
                FROM User TO Post,
                publishedAt TIMESTAMP
            )
            """)
        
        // Insert test data
        try await setupTestData(context: context)
        
        return context
    }
    
    private func setupTestData(context: GraphContext) async throws {
        // Create users
        let alice = UUID()
        let bob = UUID()
        let charlie = UUID()
        
        _ = try await context.raw("""
            CREATE (u:User {id: $id, name: $name, age: $age, city: $city, createdAt: timestamp('2024-01-01 00:00:00')})
            """, bindings: ["id": alice.uuidString, "name": "Alice", "age": 30, "city": "Tokyo"])
        
        _ = try await context.raw("""
            CREATE (u:User {id: $id, name: $name, age: $age, city: $city, createdAt: timestamp('2024-01-02 00:00:00')})
            """, bindings: ["id": bob.uuidString, "name": "Bob", "age": 25, "city": "Tokyo"])
        
        _ = try await context.raw("""
            CREATE (u:User {id: $id, name: $name, age: $age, city: $city, createdAt: timestamp('2024-01-03 00:00:00')})
            """, bindings: ["id": charlie.uuidString, "name": "Charlie", "age": 35, "city": "Osaka"])
        
        // Create relationships
        _ = try await context.raw("""
            MATCH (a:User {name: 'Alice'}), (b:User {name: 'Bob'})
            CREATE (a)-[:Follows {since: timestamp('2024-01-15 00:00:00')}]->(b)
            """)
        
        _ = try await context.raw("""
            MATCH (b:User {name: 'Bob'}), (c:User {name: 'Charlie'})
            CREATE (b)-[:Follows {since: timestamp('2024-01-20 00:00:00')}]->(c)
            """)
        
        // Create posts
        let post1 = UUID()
        let post2 = UUID()
        
        _ = try await context.raw("""
            CREATE (p:Post {id: $id, userId: $userId, content: $content, likes: $likes, createdAt: timestamp('2024-02-01 00:00:00')})
            """, bindings: ["id": post1.uuidString, "userId": alice.uuidString, "content": "Hello World", "likes": 10])
        
        _ = try await context.raw("""
            CREATE (p:Post {id: $id, userId: $userId, content: $content, likes: $likes, createdAt: timestamp('2024-02-02 00:00:00')})
            """, bindings: ["id": post2.uuidString, "userId": bob.uuidString, "content": "Graph databases are cool", "likes": 25])
        
        // Link users to posts
        _ = try await context.raw("""
            MATCH (u:User {name: 'Alice'}), (p:Post {content: 'Hello World'})
            CREATE (u)-[:Wrote {publishedAt: timestamp('2024-02-01 10:00:00')}]->(p)
            """)
        
        _ = try await context.raw("""
            MATCH (u:User {name: 'Bob'}), (p:Post {content: 'Graph databases are cool'})
            CREATE (u)-[:Wrote {publishedAt: timestamp('2024-02-02 15:00:00')}]->(p)
            """)
    }
    
    // MARK: - Transaction Query DSL Tests
    
    @Test("Transaction Query DSL")
    func testTransactionQueryDSL() async throws {
        let context = try await createContext()
        try await context.withTransaction { tx in
            // Query within transaction
            let cypher = try CypherCompiler.compile(Query(components: [
                Match.pattern(.node(type: "User", alias: "u", predicate: nil)),
                Return.items(.alias("u"))
            ]))
            
            let result = try tx.raw(cypher.query, bindings: cypher.parameters)
            
            var count = 0
            while result.hasNext() {
                _ = try result.getNext()
                count += 1
            }
            
            #expect(count == 3)
        }
    }
    
    // MARK: - Aggregation Tests
    
    @Test("Aggregation functions")
    func testAggregationFunctions() async throws {
        _ = try await createContext()
        // Test COUNT
        let countQuery = Query(components: [
            Match.pattern(.node(type: "User", alias: "u", predicate: nil)),
            Return.items([.count(nil)])
        ])
        
        let countCypher = try CypherCompiler.compile(countQuery)
        #expect(countCypher.query.contains("COUNT(*)"))
        
        // Test AVG
        let avgQuery = Query(components: [
            Match.pattern(.node(type: "User", alias: "u", predicate: nil)),
            Return.items([
                .aliased(expression: "AVG(u.age)", alias: "avgAge")
            ])
        ])
        
        let avgCypher = try CypherCompiler.compile(avgQuery)
        #expect(avgCypher.query.contains("AVG(u.age)"))
        #expect(avgCypher.query.contains("AS avgAge"))
        
        // Test multiple aggregations
        let multiAggQuery = Query(components: [
            Match.pattern(.node(type: "User", alias: "u", predicate: nil)),
            Return.items([
                .aliased(expression: "COUNT(u)", alias: "total"),
                .aliased(expression: "MAX(u.age)", alias: "maxAge"),
                .aliased(expression: "MIN(u.age)", alias: "minAge")
            ])
        ])
        
        let multiCypher = try CypherCompiler.compile(multiAggQuery)
        #expect(multiCypher.query.contains("COUNT(u) AS total"))
        #expect(multiCypher.query.contains("MAX(u.age) AS maxAge"))
        #expect(multiCypher.query.contains("MIN(u.age) AS minAge"))
    }
    
    // MARK: - OPTIONAL MATCH Tests
    
    @Test("Optional match")
    func testOptionalMatch() async throws {
        _ = try await createContext()
        let query = Query(components: [
            Match.pattern(.node(type: "User", alias: "u", predicate: nil)),
            OptionalMatch.pattern(.node(type: "Post", alias: "p", predicate: nil))
                .where(Predicate(node: .comparison(ComparisonExpression(
                    lhs: PropertyReference(alias: "p", property: "userId"),
                    op: .equal,
                    rhs: .property(PropertyReference(alias: "u", property: "id"))
                )))),
            Return.items(.alias("u"), .alias("p"))
        ])
        
        let cypher = try CypherCompiler.compile(query)
        #expect(cypher.query.contains("OPTIONAL MATCH"))
        #expect(cypher.query.contains("(p:Post)"))
        #expect(cypher.query.contains("WHERE"))
    }
    
    // MARK: - WITH Clause Tests
    
    @Test("WITH clause")
    func testWithClause() async throws {
        _ = try await createContext()
        let query = Query(components: [
            Match.pattern(.node(type: "User", alias: "u", predicate: nil)),
            With.aggregate(.count("u"), as: "userCount")
                .and("u")
                .limit(10),
            Match.pattern(.edge(type: "Follows", from: "u", to: "other", alias: "f", predicate: nil)),
            Return.items(.alias("other"))
        ])
        
        let cypher = try CypherCompiler.compile(query)
        #expect(cypher.query.contains("WITH"))
        #expect(cypher.query.contains("COUNT(u) AS userCount"))
        #expect(cypher.query.contains("LIMIT 10"))
    }
    
    // MARK: - EXISTS Pattern Tests
    
    @Test("EXISTS pattern")
    func testExistsPattern() async throws {
        _ = try await createContext()
        // Test exists in predicate
        let predicate = Predicate.exists(
            Exists.edge(
                Wrote.self,
                from: "u",
                to: "p"
            )
        )
        let predicateCypher = try predicate.toCypher()
        #expect(predicateCypher.query.contains("EXISTS"))
    }
    
    // MARK: - Path Pattern Tests
    
    @Test("Path patterns")
    func testPathPatterns() async throws {
        _ = try await createContext()
        // Test shortest path
        let shortestPath = PathPattern.shortest(
            from: "a",
            to: "b",
            via: "Follows",
            maxHops: 5,
            as: "p"
        )
        
        let shortestCypher = shortestPath.toCypher()
        #expect(shortestCypher.contains("p = shortestPath"))
        #expect(shortestCypher.contains(":Follows*..5"))
        
        // Test variable length path
        let variablePath = PathPattern.variablePath(
            from: "user",
            to: "friend",
            via: "Follows",
            hops: 1...3,
            as: "friendship"
        )
        
        let variableCypher = variablePath.toCypher()
        #expect(variableCypher.contains("friendship ="))
        #expect(variableCypher.contains(":Follows*1..3"))
        
        // Test path functions
        let lengthFunc = PathFunctions.length("p")
        #expect(lengthFunc == "length(p)")
        
        let nodesFunc = PathFunctions.nodes("p")
        #expect(nodesFunc == "nodes(p)")
    }
    
    // MARK: - Query Debug Tests
    
    @Test("Query debug and analysis")
    func testQueryDebugAndAnalysis() async throws {
        _ = try await createContext()
        // Test query compilation
        let query = Query(components: [
            Match.pattern(.node(type: "User", alias: "u", predicate: nil)),
            Match.pattern(.edge(type: "Follows", from: "u", to: "other", alias: "f", predicate: nil)),
            Return.items([.aliased(expression: "COUNT(other)", alias: "followerCount")])
        ])
        
        // Simply test that the query compiles successfully
        let cypher = try CypherCompiler.compile(query)
        
        #expect(cypher.query.contains("MATCH"))
        #expect(cypher.query.contains("User"))
        #expect(cypher.query.contains("Follows"))
        #expect(cypher.query.contains("RETURN"))
        #expect(cypher.query.contains("COUNT(other)"))
        
        // Debug functionality removed - use print() or logging frameworks if needed
    }
    
    // MARK: - Integration Test
    
    @Test("Complex query integration")
    func testComplexQueryIntegration() async throws {
        _ = try await createContext()
        // Build a complex query using multiple advanced features
        let query = Query(components: [
            // Start with users in Tokyo
            Match.pattern(.node(type: "User", alias: "u", predicate: 
                Predicate(node: .comparison(ComparisonExpression(
                    lhs: PropertyReference(alias: "u", property: "city"),
                    op: .equal,
                    rhs: .value("Tokyo")
                )))
            )),
            
            // Optional match their posts
            OptionalMatch.pattern(
                .edge(type: "Wrote", from: "u", to: "p", alias: "w", predicate: nil),
                .node(type: "Post", alias: "p", predicate: nil)
            ),
            
            // Pipeline with WITH
            With.items(
                .alias("u"),
                .aggregation(.count("p"), alias: "postCount")
            ).orderBy(
                OrderByItem.descending("postCount")
            ).limit(5),
            
            // Check if they have followers
            Match.pattern(.node(type: "User", alias: "u2", predicate:
                Predicate.exists(
                    Exists.edge(Follows.self, from: "u2", to: "u")
                )
            )),
            
            // Return results
            Return.items(
                .property(alias: "u", property: "name"),
                .aliased(expression: "postCount", alias: "posts"),
                .aliased(expression: "COUNT(u2)", alias: "followerCount")
            )
        ])
        
        let cypher = try CypherCompiler.compile(query)
        
        // Verify the query contains all expected parts
        #expect(cypher.query.contains("MATCH (u:User)"))
        #expect(cypher.query.contains("OPTIONAL MATCH"))
        #expect(cypher.query.contains("WITH"))
        #expect(cypher.query.contains("EXISTS"))
        #expect(cypher.query.contains("RETURN"))
        #expect(cypher.query.contains("ORDER BY"))
        #expect(cypher.query.contains("LIMIT"))
    }
}

// Test models - These are minimal models just for testing
// They don't need full macro expansion since we're testing the Query DSL
struct User: _KuzuGraphModel {
    static var _kuzuDDL: String { 
        "CREATE NODE TABLE User (id STRING PRIMARY KEY, name STRING, age INT64, city STRING, createdAt TIMESTAMP)"
    }
    static var _kuzuColumns: [(name: String, type: String, constraints: [String])] { 
        [
            ("id", "STRING", ["PRIMARY KEY"]),
            ("name", "STRING", []),
            ("age", "INT64", []),
            ("city", "STRING", []),
            ("createdAt", "TIMESTAMP", [])
        ]
    }
}

struct Post: _KuzuGraphModel {
    static var _kuzuDDL: String { 
        "CREATE NODE TABLE Post (id STRING PRIMARY KEY, userId STRING, content STRING, likes INT64, createdAt TIMESTAMP)"
    }
    static var _kuzuColumns: [(name: String, type: String, constraints: [String])] { 
        [
            ("id", "STRING", ["PRIMARY KEY"]),
            ("userId", "STRING", []),
            ("content", "STRING", []),
            ("likes", "INT64", []),
            ("createdAt", "TIMESTAMP", [])
        ]
    }
}

struct Follows: _KuzuGraphModel {
    static var _kuzuDDL: String { 
        "CREATE REL TABLE Follows (FROM User TO User, since TIMESTAMP)"
    }
    static var _kuzuColumns: [(name: String, type: String, constraints: [String])] { 
        [("since", "TIMESTAMP", [])]
    }
}

struct Wrote: _KuzuGraphModel {
    static var _kuzuDDL: String { 
        "CREATE REL TABLE Wrote (FROM User TO Post, publishedAt TIMESTAMP)"
    }
    static var _kuzuColumns: [(name: String, type: String, constraints: [String])] { 
        [("publishedAt", "TIMESTAMP", [])]
    }
}