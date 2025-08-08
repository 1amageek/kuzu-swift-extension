import Testing
import Foundation
import Kuzu
@testable import KuzuSwiftExtension

// Mock types for testing
struct PersonMock: _KuzuGraphModel {
    static var _kuzuDDL: String { "" }
    static var _kuzuColumns: [(name: String, type: String, constraints: [String])] { [] }
    var age: Int?
    var name: String?
}

struct CompanyMock: _KuzuGraphModel {
    static var _kuzuDDL: String { "" }
    static var _kuzuColumns: [(name: String, type: String, constraints: [String])] { [] }
}

struct WorksAtMock: _KuzuGraphModel {
    static var _kuzuDDL: String { "" }
    static var _kuzuColumns: [(name: String, type: String, constraints: [String])] { [] }
}

struct KnowsMock: _KuzuGraphModel {
    static var _kuzuDDL: String { "" }
    static var _kuzuColumns: [(name: String, type: String, constraints: [String])] { [] }
}

/// Tests for advanced Query DSL features
@Suite("Query DSL Advanced Tests")
struct QueryDSLAdvancedTests {
    
    // Helper function to create and setup context
    private func createContext() async throws -> GraphContext {
        // Create in-memory database for testing
        let config = GraphConfiguration(
            databasePath: ":memory:",
            options: GraphConfiguration.Options()
        )
        
        let context = try await GraphContext(configuration: config)
        
        // Set up test schema
        _ = try await context.raw("""
            CREATE NODE TABLE Person (
                id STRING PRIMARY KEY,
                name STRING,
                age INT64,
                city STRING
            )
            """)
        
        _ = try await context.raw("""
            CREATE NODE TABLE Company (
                id STRING PRIMARY KEY,
                name STRING,
                industry STRING
            )
            """)
        
        _ = try await context.raw("""
            CREATE REL TABLE WorksAt (
                FROM Person TO Company,
                position STRING,
                since INT64
            )
            """)
        
        _ = try await context.raw("""
            CREATE REL TABLE Knows (
                FROM Person TO Person,
                since INT64
            )
            """)
        
        // Insert test data
        try await setupTestData(context: context)
        
        return context
    }
    
    private func setupTestData(context: GraphContext) async throws {
        // Create persons
        let alice = UUID().uuidString
        let bob = UUID().uuidString
        let charlie = UUID().uuidString
        
        _ = try await context.raw("""
            CREATE (p:Person {id: $id, name: $name, age: $age, city: $city})
            """, bindings: ["id": alice, "name": "Alice", "age": 30, "city": "Tokyo"])
        
        _ = try await context.raw("""
            CREATE (p:Person {id: $id, name: $name, age: $age, city: $city})
            """, bindings: ["id": bob, "name": "Bob", "age": 25, "city": "Tokyo"])
        
        _ = try await context.raw("""
            CREATE (p:Person {id: $id, name: $name, age: $age, city: $city})
            """, bindings: ["id": charlie, "name": "Charlie", "age": 35, "city": "Osaka"])
        
        // Create companies
        let techCorp = UUID().uuidString
        let dataCo = UUID().uuidString
        
        _ = try await context.raw("""
            CREATE (c:Company {id: $id, name: $name, industry: $industry})
            """, bindings: ["id": techCorp, "name": "TechCorp", "industry": "Technology"])
        
        _ = try await context.raw("""
            CREATE (c:Company {id: $id, name: $name, industry: $industry})
            """, bindings: ["id": dataCo, "name": "DataCo", "industry": "Data Analytics"])
        
        // Create relationships
        _ = try await context.raw("""
            MATCH (p:Person {name: 'Alice'}), (c:Company {name: 'TechCorp'})
            CREATE (p)-[:WorksAt {position: 'Engineer', since: 2020}]->(c)
            """)
        
        _ = try await context.raw("""
            MATCH (p:Person {name: 'Bob'}), (c:Company {name: 'TechCorp'})
            CREATE (p)-[:WorksAt {position: 'Manager', since: 2019}]->(c)
            """)
        
        _ = try await context.raw("""
            MATCH (a:Person {name: 'Alice'}), (b:Person {name: 'Bob'})
            CREATE (a)-[:Knows {since: 2018}]->(b)
            """)
    }
    
    // MARK: - Tests
    
    @Test("Test With clause for intermediate projections")
    func testWithClause() async throws {
        let context = try await createContext()
        
        let query = Query {
            Match.pattern(.node(type: "Person", alias: "p", predicate: nil))
            With.items(
                .alias("p"),
                .aggregation(.count("p"), alias: "personCount")
            )
            Where(Predicate(node: .custom("personCount > 2", parameters: [:])))
            Return.items(.alias("personCount"))
        }
        
        let cypher = try CypherCompiler.compile(query)
        
        #expect(cypher.query.contains("WITH"))
        #expect(cypher.query.contains("COUNT(p) AS personCount"))
        #expect(cypher.query.contains("WHERE personCount > "))
    }
    
    @Test("Test Unwind clause for list expansion")
    func testUnwindClause() async throws {
        let context = try await createContext()
        
        let query = Query {
            With.items(.aliased(expression: "['Alice', 'Bob', 'Charlie']", alias: "names"))
            Unwind.parameter("names", as: "name")
            Match.pattern(.node(type: "Person", alias: "p", predicate: Predicate(node: .custom("p.name = name", parameters: [:]))))
            Return.items(.alias("p"))
        }
        
        let cypher = try CypherCompiler.compile(query)
        
        #expect(cypher.query.contains("WITH"))
        #expect(cypher.query.contains("AS names"))
        #expect(cypher.query.contains("UNWIND $names AS name"))
        #expect(cypher.query.contains("MATCH"))
    }
    
    @Test("Test Optional Match for optional patterns")
    func testOptionalMatch() async throws {
        let context = try await createContext()
        
        let query = Query {
            Match.pattern(.node(type: "Person", alias: "p", predicate: nil))
            OptionalMatch.pattern(.edge(
                type: "WorksAt",
                from: "p",
                to: "c",
                alias: "w",
                predicate: nil
            ))
            Return.items(
                .alias("p"),
                .alias("c")
            )
        }
        
        let cypher = try CypherCompiler.compile(query)
        
        #expect(cypher.query.contains("MATCH (p:Person)"))
        #expect(cypher.query.contains("OPTIONAL MATCH"))
        #expect(cypher.query.contains("(p)-[w:WorksAt]->(c)"))
    }
    
    @Test("Test Merge clause for upsert operations")
    func testMergeClause() async throws {
        let context = try await createContext()
        
        let query = Query {
            Merge.node(
                PersonMock.self,
                alias: "p",
                matchProperties: ["name": "David"]
            )
            SetClause.properties(on: "p", values: ["age": 28, "city": "Kyoto"])
            Return.items(.alias("p"))
        }
        
        let cypher = try CypherCompiler.compile(query)
        
        #expect(cypher.query.contains("MERGE"))
        #expect(cypher.query.contains("(p:Person"))
        #expect(cypher.query.contains("SET"))
        #expect(cypher.query.contains("p.age ="))
        #expect(cypher.query.contains("p.city ="))
    }
    
    @Test("Test complex aggregations with grouping")
    func testComplexAggregations() async throws {
        let context = try await createContext()
        
        let query = Query {
            Match.pattern(.node(type: "Person", alias: "p", predicate: nil))
            Return.items(
                .property(alias: "p", property: "city"),
                .aliased(expression: "count(p)", alias: "count"),
                .aliased(expression: "avg(p.age)", alias: "avgAge"),
                .aliased(expression: "min(p.age)", alias: "minAge"),
                .aliased(expression: "max(p.age)", alias: "maxAge")
            ).orderBy(.descending("count"), .ascending("p.city")).limit(10)
        }
        
        let cypher = try CypherCompiler.compile(query)
        
        #expect(cypher.query.contains("p.city"))
        #expect(cypher.query.contains("count(p) AS count"))
        #expect(cypher.query.contains("avg(p.age) AS avgAge"))
        #expect(cypher.query.contains("min(p.age) AS minAge"))
        #expect(cypher.query.contains("max(p.age) AS maxAge"))
        #expect(cypher.query.contains("ORDER BY count DESC, p.city ASC"))
        #expect(cypher.query.contains("LIMIT 10"))
    }
    
    @Test("Test debug info generation")
    func testDebugInfo() async throws {
        let context = try await createContext()
        
        let query = Query {
            Match.pattern(.node(type: "Person", alias: "p", predicate: nil))
            Where(PropertyReference(alias: "p", property: "age") > 25)
            Return.items(.alias("p"))
        }
        
        let debugInfo = try query.debugInfo()
        
        #expect(debugInfo.cypher.isEmpty == false)
        #expect(debugInfo.cypher.contains("MATCH"))
        #expect(debugInfo.cypher.contains("Person"))
        #expect(debugInfo.cypher.count > 0)
        #expect(!debugInfo.parameters.isEmpty)
        
        let description = debugInfo.formattedDescription
        #expect(description.contains("Query Debug Info"))
        #expect(description.contains("Query Analysis"))
        #expect(description.contains("Parameters"))
    }
    
    @Test("Test transaction integration")
    func testTransactionIntegration() async throws {
        let context = try await createContext()
        
        let query = Query {
            Create.node(
                PersonMock.self,
                alias: "p",
                properties: ["name": "Transaction Test", "age": 40]
            )
            Return.items(.alias("p"))
        }
        
        let cypher = try CypherCompiler.compile(query)
        
        #expect(cypher.query.contains("CREATE"))
        #expect(cypher.query.contains("Person"))
        #expect(cypher.parameters.count == 2)
    }
    
    @Test("Test path patterns for relationship traversal")
    func testPathPatterns() async throws {
        let context = try await createContext()
        
        let query = Query {
            Match.pattern(.path(
                from: "a",
                to: "b",
                via: "Knows",
                hops: 1...3,
                alias: "path"
            ))
            Return.items(.alias("path"))
        }
        
        let cypher = try CypherCompiler.compile(query)
        
        #expect(cypher.query.contains("MATCH path = (a)"))
        #expect(cypher.query.contains("-[:Knows*1..3]->"))
        #expect(cypher.query.contains("(b)"))
    }
    
    @Test("Test edge property access with type safety")
    func testEdgePropertyAccess() async throws {
        let context = try await createContext()
        
        let query = Query {
            Match.pattern(.edge(
                type: "WorksAt",
                from: "p",
                to: "c",
                alias: "w",
                predicate: nil
            ))
            Where(PropertyReference(alias: "w", property: "since") > 2019)
            Return.items(
                .alias("p"),
                .property(alias: "w", property: "position"),
                .property(alias: "w", property: "since")
            )
        }
        
        let cypher = try CypherCompiler.compile(query)
        
        #expect(cypher.query.contains("(p)-[w:WorksAt]->(c)"))
        #expect(cypher.query.contains("WHERE w.since >"))
        #expect(cypher.query.contains("w.position"))
        #expect(cypher.query.contains("w.since"))
    }
    
    @Test("Test Let clause for variable assignment")
    func testLetClause() async throws {
        let context = try await createContext()
        
        let query = Query {
            Match.pattern(.node(type: "Person", alias: "p", predicate: nil))
            Let.aggregate("avgAge", .avg(PropertyPath<PersonMock>(keyPath: \PersonMock.age, alias: "p")))
            Where(PropertyReference(alias: "p", property: "age") > Ref("avgAge"))
            Return.items(.alias("p"))
        }
        
        let cypher = try CypherCompiler.compile(query)
        
        #expect(cypher.query.contains("LET avgAge ="))
        #expect(cypher.query.contains("AVG(p.age)"))
        #expect(cypher.query.contains("WHERE p.age > avgAge"))
    }
    
    @Test("Test Call subquery blocks")
    func testCallSubquery() async throws {
        let context = try await createContext()
        
        let query = Query {
            Match.pattern(.node(type: "Person", alias: "p", predicate: nil))
            Subquery.callBlock(yields: ["relCount"]) {
                Match.pattern(.edge(
                    type: "Knows",
                    from: "p",
                    to: "other",
                    alias: "k",
                    predicate: nil
                ))
                Return.items(.aliased(expression: "count(k)", alias: "relCount"))
            }
            Where(Predicate(node: .custom("relCount > 0", parameters: [:])))
            Return.items(.alias("p"), .alias("relCount"))
        }
        
        let cypher = try CypherCompiler.compile(query)
        
        #expect(cypher.query.contains("CALL {"))
        #expect(cypher.query.contains("} YIELD relCount"))
        #expect(cypher.query.contains("WHERE relCount >"))
    }
}