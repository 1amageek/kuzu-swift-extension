import XCTest
import Kuzu
@testable import KuzuSwiftExtension

final class QueryDSLIntegrationTests: XCTestCase {
    
    var context: GraphContext!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create in-memory database for testing
        let config = GraphConfiguration(
            databasePath: ":memory:",
            options: GraphConfiguration.Options()
        )
        
        context = try await GraphContext(configuration: config)
        
        // Set up test schema
        try await context.raw("""
            CREATE NODE TABLE User (
                id STRING PRIMARY KEY,
                name STRING,
                age INT64,
                city STRING,
                createdAt TIMESTAMP
            )
            """)
        
        try await context.raw("""
            CREATE NODE TABLE Post (
                id STRING PRIMARY KEY,
                userId STRING,
                content STRING,
                likes INT64,
                createdAt TIMESTAMP
            )
            """)
        
        try await context.raw("""
            CREATE REL TABLE Follows (
                FROM User TO User,
                since TIMESTAMP
            )
            """)
        
        try await context.raw("""
            CREATE REL TABLE Wrote (
                FROM User TO Post,
                publishedAt TIMESTAMP
            )
            """)
        
        // Insert test data
        try await setupTestData()
    }
    
    private func setupTestData() async throws {
        // Create users
        let alice = UUID()
        let bob = UUID()
        let charlie = UUID()
        
        try await context.raw("""
            CREATE (u:User {id: $id, name: $name, age: $age, city: $city, createdAt: timestamp('2024-01-01 00:00:00')})
            """, bindings: ["id": alice.uuidString, "name": "Alice", "age": 30, "city": "Tokyo"])
        
        try await context.raw("""
            CREATE (u:User {id: $id, name: $name, age: $age, city: $city, createdAt: timestamp('2024-01-02 00:00:00')})
            """, bindings: ["id": bob.uuidString, "name": "Bob", "age": 25, "city": "Tokyo"])
        
        try await context.raw("""
            CREATE (u:User {id: $id, name: $name, age: $age, city: $city, createdAt: timestamp('2024-01-03 00:00:00')})
            """, bindings: ["id": charlie.uuidString, "name": "Charlie", "age": 35, "city": "Osaka"])
        
        // Create relationships
        try await context.raw("""
            MATCH (a:User {name: 'Alice'}), (b:User {name: 'Bob'})
            CREATE (a)-[:Follows {since: timestamp('2024-01-15 00:00:00')}]->(b)
            """)
        
        try await context.raw("""
            MATCH (b:User {name: 'Bob'}), (c:User {name: 'Charlie'})
            CREATE (b)-[:Follows {since: timestamp('2024-01-20 00:00:00')}]->(c)
            """)
        
        // Create posts
        let post1 = UUID()
        let post2 = UUID()
        
        try await context.raw("""
            CREATE (p:Post {id: $id, userId: $userId, content: $content, likes: $likes, createdAt: timestamp('2024-02-01 00:00:00')})
            """, bindings: ["id": post1.uuidString, "userId": alice.uuidString, "content": "Hello World", "likes": 10])
        
        try await context.raw("""
            CREATE (p:Post {id: $id, userId: $userId, content: $content, likes: $likes, createdAt: timestamp('2024-02-02 00:00:00')})
            """, bindings: ["id": post2.uuidString, "userId": bob.uuidString, "content": "Graph databases are cool", "likes": 25])
        
        // Link users to posts
        try await context.raw("""
            MATCH (u:User {name: 'Alice'}), (p:Post {content: 'Hello World'})
            CREATE (u)-[:Wrote {publishedAt: timestamp('2024-02-01 10:00:00')}]->(p)
            """)
        
        try await context.raw("""
            MATCH (u:User {name: 'Bob'}), (p:Post {content: 'Graph databases are cool'})
            CREATE (u)-[:Wrote {publishedAt: timestamp('2024-02-02 15:00:00')}]->(p)
            """)
    }
    
    // MARK: - Transaction Query DSL Tests
    
    func testTransactionQueryDSL() async throws {
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
            
            XCTAssertEqual(count, 3)
        }
    }
    
    // MARK: - Aggregation Tests
    
    func testAggregationFunctions() async throws {
        // Test COUNT
        let countQuery = Query(components: [
            Match.pattern(.node(type: "User", alias: "u", predicate: nil)),
            Return.count()
        ])
        
        let countCypher = try CypherCompiler.compile(countQuery)
        XCTAssertTrue(countCypher.query.contains("COUNT(*)"))
        
        // Test AVG
        let avgQuery = Query(components: [
            Match.pattern(.node(type: "User", alias: "u", predicate: nil)),
            Return.aggregate(.avg(PropertyReference(alias: "u", property: "age")), as: "avgAge")
        ])
        
        let avgCypher = try CypherCompiler.compile(avgQuery)
        XCTAssertTrue(avgCypher.query.contains("AVG(u.age)"))
        XCTAssertTrue(avgCypher.query.contains("AS avgAge"))
        
        // Test multiple aggregations
        let multiAggQuery = Query(components: [
            Match.pattern(.node(type: "User", alias: "u", predicate: nil)),
            Return.aggregates(
                (.count("u"), "total"),
                (.max(PropertyReference(alias: "u", property: "age")), "maxAge"),
                (.min(PropertyReference(alias: "u", property: "age")), "minAge")
            )
        ])
        
        let multiCypher = try CypherCompiler.compile(multiAggQuery)
        XCTAssertTrue(multiCypher.query.contains("COUNT(u) AS total"))
        XCTAssertTrue(multiCypher.query.contains("MAX(u.age) AS maxAge"))
        XCTAssertTrue(multiCypher.query.contains("MIN(u.age) AS minAge"))
    }
    
    // MARK: - OPTIONAL MATCH Tests
    
    func testOptionalMatch() async throws {
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
        XCTAssertTrue(cypher.query.contains("OPTIONAL MATCH"))
        XCTAssertTrue(cypher.query.contains("(p:Post)"))
        XCTAssertTrue(cypher.query.contains("WHERE"))
    }
    
    // MARK: - WITH Clause Tests
    
    func testWithClause() async throws {
        let query = Query(components: [
            Match.pattern(.node(type: "User", alias: "u", predicate: nil)),
            With.aggregate(.count("u"), as: "userCount")
                .and("u")
                .limit(10),
            Match.pattern(.edge(type: "Follows", from: "u", to: "other", alias: "f", predicate: nil)),
            Return.items(.alias("other"))
        ])
        
        let cypher = try CypherCompiler.compile(query)
        XCTAssertTrue(cypher.query.contains("WITH"))
        XCTAssertTrue(cypher.query.contains("COUNT(u) AS userCount"))
        XCTAssertTrue(cypher.query.contains("LIMIT 10"))
    }
    
    // MARK: - EXISTS Pattern Tests
    
    func testExistsPattern() async throws {
        // Test exists in predicate
        let predicate = Predicate.exists(
            Exists.edge(
                Wrote.self,
                from: "u",
                to: "p"
            )
        )
        let predicateCypher = try predicate.toCypher()
        XCTAssertTrue(predicateCypher.query.contains("EXISTS"))
    }
    
    // MARK: - Path Pattern Tests
    
    func testPathPatterns() async throws {
        // Test shortest path
        let shortestPath = PathPattern.shortest(
            from: "a",
            to: "b",
            via: "Follows",
            maxHops: 5,
            as: "p"
        )
        
        let shortestCypher = shortestPath.toCypher()
        XCTAssertTrue(shortestCypher.contains("p = shortestPath"))
        XCTAssertTrue(shortestCypher.contains(":Follows*..5"))
        
        // Test variable length path
        let variablePath = PathPattern.variablePath(
            from: "user",
            to: "friend",
            via: "Follows",
            hops: 1...3,
            as: "friendship"
        )
        
        let variableCypher = variablePath.toCypher()
        XCTAssertTrue(variableCypher.contains("friendship ="))
        XCTAssertTrue(variableCypher.contains(":Follows*1..3"))
        
        // Test path functions
        let lengthFunc = PathFunctions.length("p")
        XCTAssertEqual(lengthFunc, "length(p)")
        
        let nodesFunc = PathFunctions.nodes("p")
        XCTAssertEqual(nodesFunc, "nodes(p)")
    }
    
    // MARK: - Query Debug Tests
    
    func testQueryDebugAndAnalysis() async throws {
        // Test query analysis
        let query = Query(components: [
            Match.pattern(.node(type: "User", alias: "u", predicate: nil)),
            Match.pattern(.edge(type: "Follows", from: "u", to: "other", alias: "f", predicate: nil)),
            Return.aggregate(.count("other"), as: "followerCount")
        ])
        
        let analysis = try QueryIntrospection.analyze(query)
        
        XCTAssertTrue(analysis.nodeTypes.contains("User"))
        XCTAssertTrue(analysis.edgeTypes.contains("Follows"))
        XCTAssertTrue(analysis.operations.contains("MATCH"))
        XCTAssertTrue(analysis.operations.contains("RETURN"))
        XCTAssertTrue(analysis.hasAggregation)
        XCTAssertGreaterThan(analysis.estimatedComplexity, 0)
        
        // Test debug configuration
        QueryDebug.configuration = .verbose
        XCTAssertTrue(QueryDebug.configuration.printCypher)
        XCTAssertTrue(QueryDebug.configuration.printParameters)
        
        QueryDebug.disable()
        XCTAssertFalse(QueryDebug.configuration.printCypher)
    }
    
    // MARK: - Integration Test
    
    func testComplexQueryIntegration() async throws {
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
        XCTAssertTrue(cypher.query.contains("MATCH (u:User)"))
        XCTAssertTrue(cypher.query.contains("OPTIONAL MATCH"))
        XCTAssertTrue(cypher.query.contains("WITH"))
        XCTAssertTrue(cypher.query.contains("EXISTS"))
        XCTAssertTrue(cypher.query.contains("RETURN"))
        XCTAssertTrue(cypher.query.contains("ORDER BY"))
        XCTAssertTrue(cypher.query.contains("LIMIT"))
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