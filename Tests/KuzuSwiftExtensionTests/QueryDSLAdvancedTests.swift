import XCTest
import Kuzu
@testable import KuzuSwiftExtension

/// Tests for advanced Query DSL features
final class QueryDSLAdvancedTests: XCTestCase {
    
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
            CREATE NODE TABLE Person (
                id STRING PRIMARY KEY,
                name STRING,
                age INT64,
                city STRING
            )
            """)
        
        try await context.raw("""
            CREATE NODE TABLE Company (
                id STRING PRIMARY KEY,
                name STRING,
                industry STRING
            )
            """)
        
        try await context.raw("""
            CREATE REL TABLE WorksAt (
                FROM Person TO Company,
                position STRING,
                since INT64
            )
            """)
        
        try await context.raw("""
            CREATE REL TABLE Knows (
                FROM Person TO Person,
                since INT64
            )
            """)
        
        // Insert test data
        try await setupTestData()
    }
    
    private func setupTestData() async throws {
        // Create persons
        let alice = UUID().uuidString
        let bob = UUID().uuidString
        let charlie = UUID().uuidString
        
        try await context.raw("""
            CREATE (p:Person {id: $id, name: $name, age: $age, city: $city})
            """, bindings: ["id": alice, "name": "Alice", "age": 30, "city": "Tokyo"])
        
        try await context.raw("""
            CREATE (p:Person {id: $id, name: $name, age: $age, city: $city})
            """, bindings: ["id": bob, "name": "Bob", "age": 25, "city": "Tokyo"])
        
        try await context.raw("""
            CREATE (p:Person {id: $id, name: $name, age: $age, city: $city})
            """, bindings: ["id": charlie, "name": "Charlie", "age": 35, "city": "Osaka"])
        
        // Create companies
        let techCorp = UUID().uuidString
        let dataCo = UUID().uuidString
        
        try await context.raw("""
            CREATE (c:Company {id: $id, name: $name, industry: $industry})
            """, bindings: ["id": techCorp, "name": "TechCorp", "industry": "Technology"])
        
        try await context.raw("""
            CREATE (c:Company {id: $id, name: $name, industry: $industry})
            """, bindings: ["id": dataCo, "name": "DataCo", "industry": "Data Analytics"])
        
        // Create relationships
        try await context.raw("""
            MATCH (p:Person {name: 'Alice'}), (c:Company {name: 'TechCorp'})
            CREATE (p)-[:WorksAt {position: 'Engineer', since: 2020}]->(c)
            """)
        
        try await context.raw("""
            MATCH (p:Person {name: 'Bob'}), (c:Company {name: 'TechCorp'})
            CREATE (p)-[:WorksAt {position: 'Manager', since: 2019}]->(c)
            """)
        
        try await context.raw("""
            MATCH (a:Person {name: 'Alice'}), (b:Person {name: 'Bob'})
            CREATE (a)-[:Knows {since: 2018}]->(b)
            """)
    }
    
    // MARK: - NOT EXISTS Tests
    
    func testNotExistsPattern() async throws {
        // Test NOT EXISTS with node pattern
        let query = Query(components: [
            Match.pattern(.node(type: "Person", alias: "p", predicate: nil)),
            Where(.notExists(
                NotExists.edge(WorksAt.self, from: "p", to: "_")
            )),
            Return.items(.property(alias: "p", property: "name"))
        ])
        
        let cypher = try CypherCompiler.compile(query)
        XCTAssertTrue(cypher.query.contains("NOT EXISTS"))
        XCTAssertTrue(cypher.query.contains("WorksAt"))
        
        // Execute and verify Charlie doesn't work at any company
        let result = try await context.raw(cypher.query, bindings: cypher.parameters)
        var names: [String] = []
        while result.hasNext() {
            if let row = try result.getNext(),
               let name = try row.getValue(0) as? String {
                names.append(name)
            }
        }
        XCTAssertEqual(names, ["Charlie"])
    }
    
    func testNotExistsWithPredicate() async throws {
        // Test NOT EXISTS with additional predicate
        let predicate = Predicate.notExists(
            NotExists.node(Person.self, alias: "other", where: 
                PropertyReference(alias: "other", property: "age") > 40
            )
        )
        
        let cypher = try predicate.toCypher()
        XCTAssertTrue(cypher.query.contains("NOT EXISTS"))
        XCTAssertTrue(cypher.query.contains("Person"))
    }
    
    // MARK: - Enhanced Query Builder Tests
    
    func testQueryBuilderWithControlFlow() throws {
        let includeAge = true
        let cityFilter: String? = "Tokyo"
        
        let query = Query {
            Match.pattern(.node(type: "Person", alias: "p", predicate: nil))
            
            if let city = cityFilter {
                Where(PropertyReference(alias: "p", property: "city") == city)
            }
            
            if includeAge {
                Return.items(
                    .property(alias: "p", property: "name"),
                    .property(alias: "p", property: "age")
                )
            } else {
                Return.items(.property(alias: "p", property: "name"))
            }
        }
        
        let cypher = try CypherCompiler.compile(query)
        
        XCTAssertTrue(cypher.query.contains("WHERE p.city ="))
        XCTAssertTrue(cypher.query.contains("p.age"))
    }
    
    // MARK: - Debug Support Tests
    
    func testQueryDebugInfo() throws {
        let query = Query(components: [
            Match.pattern(.node(type: "Person", alias: "p", predicate: nil)),
            Return.count()
        ])
        
        let debugInfo = try query.debugInfo()
        
        XCTAssertNotNil(debugInfo.cypher)
        XCTAssertTrue(debugInfo.cypher.contains("MATCH"))
        XCTAssertTrue(debugInfo.cypher.contains("Person"))
        XCTAssertTrue(debugInfo.cypher.contains("COUNT"))
        
        // Test cypherString property
        XCTAssertNotNil(query.cypherString)
        XCTAssertEqual(query.cypherString, debugInfo.cypher)
        
        // Test formatted description
        let description = debugInfo.formattedDescription
        XCTAssertTrue(description.contains("Query Debug Info"))
    }
    
    func testQueryExplain() throws {
        let query = Query(components: [
            Match.pattern(.node(type: "Person", alias: "p", predicate: nil)),
            Return.items(.alias("p"))
        ])
        
        let explainQuery = query.explain()
        let cypher = try CypherCompiler.compile(explainQuery)
        
        XCTAssertTrue(cypher.query.hasPrefix("EXPLAIN"))
    }
    
    // MARK: - Subquery Tests
    
    func testScalarSubquery() throws {
        // Test scalar subquery in LET clause
        let letClause = Let.scalar("maxAge") {
            Match.pattern(.node(type: "Person", alias: "p", predicate: nil))
            Return.aggregate(.max(PropertyReference(alias: "p", property: "age")), as: "maxAge")
        }
        
        let cypher = try letClause.toCypher()
        XCTAssertTrue(cypher.query.contains("LET maxAge ="))
        XCTAssertTrue(cypher.query.contains("MAX(p.age)"))
    }
    
    func testListSubquery() throws {
        // Test list subquery
        let subquery = Subquery.list {
            Match.pattern(.node(type: "Person", alias: "p", predicate: nil))
            Return.items(.property(alias: "p", property: "name"))
        }
        
        let cypher = try subquery.toCypher()
        XCTAssertTrue(cypher.query.hasPrefix("[("))
        XCTAssertTrue(cypher.query.hasSuffix(")]"))
        XCTAssertTrue(cypher.query.contains("Person"))
    }
    
    func testExistsSubquery() throws {
        // Test EXISTS subquery
        let subquery = Subquery.exists {
            Match.pattern(.node(type: "Person", alias: "p", predicate: nil))
            Where(PropertyReference(alias: "p", property: "age") > 30)
            Return.items(.alias("p"))
        }
        
        let cypher = try subquery.toCypher()
        XCTAssertTrue(cypher.query.contains("EXISTS {"))
        XCTAssertTrue(cypher.query.contains("WHERE"))
    }
    
    // MARK: - CALL Clause Tests
    
    func testCallProcedure() throws {
        let call = Call.procedure(
            "db.schema.nodeTableNames",
            yields: ["name"]
        )
        
        let cypher = try call.toCypher()
        XCTAssertEqual(cypher.query, "CALL db.schema.nodeTableNames() YIELD name")
    }
    
    func testCallWithParameters() throws {
        let call = Call.procedure(
            "custom.procedure",
            parameters: ["param1": "value1", "param2": 42],
            yields: ["result"]
        )
        
        let cypher = try call.toCypher()
        XCTAssertTrue(cypher.query.contains("CALL custom.procedure("))
        XCTAssertTrue(cypher.query.contains("param1: $param1"))
        XCTAssertTrue(cypher.query.contains("param2: $param2"))
        XCTAssertTrue(cypher.query.contains("YIELD result"))
        XCTAssertEqual(cypher.parameters["param1"] as? String, "value1")
        XCTAssertEqual(cypher.parameters["param2"] as? Int, 42)
    }
    
    func testCallWithWhere() throws {
        let call = Call.procedure("db.stats.table", parameters: ["tableName": "Person"])
            .where(PropertyReference(alias: "numTuples", property: "") > 0)
            .yields("numTuples", "numPages")
        
        let cypher = try call.toCypher()
        XCTAssertTrue(cypher.query.contains("WHERE"))
        XCTAssertTrue(cypher.query.contains("YIELD numTuples, numPages"))
    }
    
    // MARK: - Graph Algorithms Tests
    
    func testPageRankAlgorithm() throws {
        let pagerank = GraphAlgorithms.PageRank.compute(
            damping: 0.85,
            iterations: 20,
            tolerance: 1e-6
        )
        
        let cypher = try pagerank.toCypher()
        XCTAssertTrue(cypher.query.contains("gds.pageRank"))
        XCTAssertEqual(cypher.parameters["damping"] as? Double, 0.85)
        XCTAssertEqual(cypher.parameters["iterations"] as? Int, 20)
    }
    
    func testLouvainCommunityDetection() throws {
        let louvain = GraphAlgorithms.Louvain.detect(
            seedProperty: "initialCommunity",
            tolerance: 0.001
        )
        
        let cypher = try louvain.toCypher()
        XCTAssertTrue(cypher.query.contains("gds.louvain"))
        XCTAssertEqual(cypher.parameters["seedProperty"] as? String, "initialCommunity")
    }
    
    func testShortestPath() throws {
        let dijkstra = GraphAlgorithms.ShortestPath.dijkstra(
            source: "nodeA",
            target: "nodeB",
            weightProperty: "distance"
        )
        
        let cypher = try dijkstra.toCypher()
        XCTAssertTrue(cypher.query.contains("gds.shortestPath.dijkstra"))
        XCTAssertEqual(cypher.parameters["source"] as? String, "nodeA")
        XCTAssertEqual(cypher.parameters["target"] as? String, "nodeB")
        XCTAssertEqual(cypher.parameters["weightProperty"] as? String, "distance")
    }
    
    // MARK: - Integration Tests
    
    func testComplexQueryWithAllFeatures() async throws {
        // Complex query using multiple new features
        let query = Query(components: [
            // Match persons
            Match.pattern(.node(type: "Person", alias: "p", predicate: nil)),
            
            // Filter using NOT EXISTS
            Where(.notExists(
                NotExists.node(Person.self, alias: "blocked", where:
                    PropertyReference(alias: "blocked", property: "name") == "BlockedUser"
                )
            )),
            
            // Scalar subquery for average age
            Let.scalar("avgAge") {
                Match.pattern(.node(type: "Person", alias: "p2", predicate: nil))
                Return.aggregate(.avg(PropertyReference(alias: "p2", property: "age")), as: "avg")
            },
            
            // Filter by average
            Where(PropertyReference(alias: "p", property: "age") >= Ref("avgAge")),
            
            // Return with debug info
            Return.items(
                .property(alias: "p", property: "name"),
                .property(alias: "p", property: "age"),
                .aliased(expression: "avgAge", alias: "averageAge")
            )
        ])
        
        // Enable debug for this query
        QueryDebug.configuration = .cypherOnly
        defer { QueryDebug.disable() }
        
        let cypher = try CypherCompiler.compile(query)
        
        // Debug: Print the generated query
        print("Generated Cypher Query:")
        print(cypher.query)
        print("---")
        
        // Verify query structure
        XCTAssertTrue(cypher.query.contains("NOT EXISTS"), "Query should contain NOT EXISTS")
        XCTAssertTrue(cypher.query.contains("LET avgAge ="), "Query should contain LET avgAge =")
        XCTAssertTrue(cypher.query.contains("AVG(p2.age)"), "Query should contain AVG(p2.age)")
        XCTAssertTrue(cypher.query.contains("WHERE p.age >="), "Query should contain WHERE p.age >=")
    }
}

// Test models for advanced tests
extension QueryDSLAdvancedTests {
    struct Person: _KuzuGraphModel {
        static var _kuzuDDL: String {
            "CREATE NODE TABLE Person (id STRING PRIMARY KEY, name STRING, age INT64, city STRING)"
        }
        static var _kuzuColumns: [(name: String, type: String, constraints: [String])] {
            [
                ("id", "STRING", ["PRIMARY KEY"]),
                ("name", "STRING", []),
                ("age", "INT64", []),
                ("city", "STRING", [])
            ]
        }
    }
    
    struct Company: _KuzuGraphModel {
        static var _kuzuDDL: String {
            "CREATE NODE TABLE Company (id STRING PRIMARY KEY, name STRING, industry STRING)"
        }
        static var _kuzuColumns: [(name: String, type: String, constraints: [String])] {
            [
                ("id", "STRING", ["PRIMARY KEY"]),
                ("name", "STRING", []),
                ("industry", "STRING", [])
            ]
        }
    }
    
    struct WorksAt: _KuzuGraphModel {
        static var _kuzuDDL: String {
            "CREATE REL TABLE WorksAt (FROM Person TO Company, position STRING, since INT64)"
        }
        static var _kuzuColumns: [(name: String, type: String, constraints: [String])] {
            [
                ("position", "STRING", []),
                ("since", "INT64", [])
            ]
        }
    }
    
    struct Knows: _KuzuGraphModel {
        static var _kuzuDDL: String {
            "CREATE REL TABLE Knows (FROM Person TO Person, since INT64)"
        }
        static var _kuzuColumns: [(name: String, type: String, constraints: [String])] {
            [("since", "INT64", [])]
        }
    }
}