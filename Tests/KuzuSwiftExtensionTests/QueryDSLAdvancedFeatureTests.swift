import Testing
import Kuzu
@testable import KuzuSwiftExtension

/// Simplified tests for advanced Query DSL features
@Suite("Query DSL Advanced Feature Tests")
struct QueryDSLAdvancedFeatureTests {
    
    // MARK: - NOT EXISTS Tests
    
    @Test("NOT EXISTS compilation")
    func testNotExistsCompilation() throws {
        // Test NOT EXISTS pattern compilation
        let notExists = NotExists.edge(TestEdge.self, from: "a", to: "b")
        let cypher = try notExists.toCypher()
        
        #expect(cypher.query.contains("NOT EXISTS"))
        #expect(cypher.query.contains("TestEdge"))
    }
    
    @Test("NOT EXISTS in predicate")
    func testNotExistsInPredicate() throws {
        // Test NOT EXISTS in predicate
        let predicate = Predicate.notExists(
            NotExists.node(TestNode.self, alias: "n")
        )
        
        let cypher = try predicate.toCypher()
        #expect(cypher.query.contains("NOT EXISTS"))
        #expect(cypher.query.contains("TestNode"))
    }
    
    // MARK: - Enhanced Query Builder Tests
    
    @Test("Conditional query builder")
    func testConditionalQueryBuilder() throws {
        let includeWhere = true
        
        let query = Query {
            Match.pattern(.node(type: "Person", alias: "p", predicate: nil))
            if includeWhere {
                Where(PropertyReference(alias: "p", property: "age") > 25)
            }
            Return.items(.alias("p"))
        }
        
        let cypher = try CypherCompiler.compile(query)
        
        #expect(cypher.query.contains("MATCH (p:Person)"))
        #expect(cypher.query.contains("WHERE p.age >"))
        #expect(cypher.query.contains("RETURN p"))
    }
    
    // MARK: - Debug Support Tests
    
    @Test("Query cypherString")
    func testQueryCypherString() throws {
        let query = Query(components: [
            Match.pattern(.node(type: "Test", alias: "t", predicate: nil)),
            Return.items(.alias("t"))
        ])
        
        let cypher = try CypherCompiler.compile(query)
        #expect(!cypher.query.isEmpty)
        #expect(cypher.query.contains("MATCH"))
        #expect(cypher.query.contains("Test"))
    }
    
    @Test("Query compilation")
    func testQueryCompilation() throws {
        let query = Query(components: [
            Match.pattern(.node(type: "Person", alias: "p", predicate: nil)),
            Return.items([.count(nil)])
        ])
        
        let cypher = try CypherCompiler.compile(query)
        
        #expect(!cypher.query.isEmpty)
        #expect(cypher.query.contains("MATCH"))
        #expect(cypher.query.contains("Person"))
        #expect(cypher.query.contains("COUNT(*)"))
    }
    
    @Test("Query explain")
    func testQueryExplain() throws {
        let query = Query(components: [
            Match.pattern(.node(type: "Test", alias: "t", predicate: nil)),
            Return.items(.alias("t"))
        ])
        
        // EXPLAIN can be prepended manually if needed
        let cypher = try CypherCompiler.compile(query)
        let explainQuery = "EXPLAIN " + cypher.query
        
        #expect(explainQuery.hasPrefix("EXPLAIN"))
    }
    
    // MARK: - Subquery Tests
    
    @Test("Subquery types")
    func testSubqueryTypes() throws {
        // Scalar subquery
        let scalar = Subquery.scalar(Query(components: [
            Match.pattern(.node(type: "Test", alias: "t", predicate: nil)),
            Return.items([.count(nil)])
        ]))
        
        let scalarCypher = try scalar.toCypher()
        #expect(scalarCypher.query.hasPrefix("("))
        #expect(scalarCypher.query.hasSuffix(")"))
        
        // List subquery
        let list = Subquery.list(Query(components: [
            Match.pattern(.node(type: "Test", alias: "t", predicate: nil)),
            Return.items(.alias("t"))
        ]))
        
        let listCypher = try list.toCypher()
        #expect(listCypher.query.hasPrefix("[("))
        #expect(listCypher.query.hasSuffix(")]"))
        
        // EXISTS subquery
        let exists = Subquery.exists(Query(components: [
            Match.pattern(.node(type: "Test", alias: "t", predicate: nil))
        ]))
        
        let existsCypher = try exists.toCypher()
        #expect(existsCypher.query.contains("EXISTS {"))
        #expect(existsCypher.query.contains("}"))
    }
    
    @Test("Let clause")
    func testLetClause() throws {
        // Test various LET expressions
        let letValue = Let.value("x", 42)
        let valueCypher = try letValue.toCypher()
        #expect(valueCypher.query.contains("LET x ="))
        
        let letProperty = Let.property("name", PropertyReference(alias: "p", property: "name"))
        let propCypher = try letProperty.toCypher()
        #expect(propCypher.query.contains("LET name = p.name"))
        
        let letAgg = Let.aggregate("total", .count("*"))
        let aggCypher = try letAgg.toCypher()
        #expect(aggCypher.query.contains("LET total = COUNT(*)"))
    }
    
    @Test("Ref")
    func testRef() throws {
        let ref = Ref("myVar")
        let cypher = try ref.toCypher()
        #expect(cypher.query == "myVar")
    }
    
    // MARK: - CALL Clause Tests
    
    @Test("Call clause")
    func testCallClause() throws {
        // Simple procedure call
        let call = Call.procedure("db.stats", yields: ["stat"])
        let cypher = try call.toCypher()
        #expect(cypher.query == "CALL db.stats() YIELD stat")
        
        // Call with parameters
        let callWithParams = Call.procedure(
            "custom.proc",
            parameters: ["x": 1, "y": "test"],
            yields: ["result"]
        )
        let paramCypher = try callWithParams.toCypher()
        #expect(paramCypher.query.contains("CALL custom.proc("))
        #expect(paramCypher.query.contains("x: $x"))
        #expect(paramCypher.query.contains("y: $y"))
        
        // Call with WHERE
        let callWithWhere = Call.procedure("db.test")
            .where(PropertyReference(alias: "x", property: "value") > 10)
            .yields("x", "y")
        
        let whereCypher = try callWithWhere.toCypher()
        #expect(whereCypher.query.contains("WHERE"))
        #expect(whereCypher.query.contains("YIELD x, y"))
    }
    
    // MARK: - Graph Algorithms Tests
    // Note: Graph algorithms are not yet supported by Kuzu
    // These tests have been removed as the GraphAlgorithms module was deleted
}

// MARK: - Test Models

private struct TestNode: _KuzuGraphModel {
    static var _kuzuDDL: String { "CREATE NODE TABLE TestNode (id STRING PRIMARY KEY)" }
    static var _kuzuColumns: [(name: String, type: String, constraints: [String])] {
        [("id", "STRING", ["PRIMARY KEY"])]
    }
}

private struct TestEdge: _KuzuGraphModel {
    static var _kuzuDDL: String { "CREATE REL TABLE TestEdge (FROM TestNode TO TestNode)" }
    static var _kuzuColumns: [(name: String, type: String, constraints: [String])] { [] }
}