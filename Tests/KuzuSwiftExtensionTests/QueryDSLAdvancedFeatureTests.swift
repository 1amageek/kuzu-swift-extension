import XCTest
import Kuzu
@testable import KuzuSwiftExtension

/// Simplified tests for advanced Query DSL features
final class QueryDSLAdvancedFeatureTests: XCTestCase {
    
    // MARK: - NOT EXISTS Tests
    
    func testNotExistsCompilation() throws {
        // Test NOT EXISTS pattern compilation
        let notExists = NotExists.edge(TestEdge.self, from: "a", to: "b")
        let cypher = try notExists.toCypher()
        
        XCTAssertTrue(cypher.query.contains("NOT EXISTS"))
        XCTAssertTrue(cypher.query.contains("TestEdge"))
    }
    
    func testNotExistsInPredicate() throws {
        // Test NOT EXISTS in predicate
        let predicate = Predicate.notExists(
            NotExists.node(TestNode.self, alias: "n")
        )
        
        let cypher = try predicate.toCypher()
        XCTAssertTrue(cypher.query.contains("NOT EXISTS"))
        XCTAssertTrue(cypher.query.contains("TestNode"))
    }
    
    // MARK: - Enhanced Query Builder Tests
    
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
        
        XCTAssertTrue(cypher.query.contains("MATCH (p:Person)"))
        XCTAssertTrue(cypher.query.contains("WHERE p.age >"))
        XCTAssertTrue(cypher.query.contains("RETURN p"))
    }
    
    // MARK: - Debug Support Tests
    
    func testQueryCypherString() throws {
        let query = Query(components: [
            Match.pattern(.node(type: "Test", alias: "t", predicate: nil)),
            Return.items(.alias("t"))
        ])
        
        XCTAssertNotNil(query.cypherString)
        XCTAssertTrue(query.cypherString?.contains("MATCH") ?? false)
        XCTAssertTrue(query.cypherString?.contains("Test") ?? false)
    }
    
    func testQueryDebugInfo() throws {
        let query = Query(components: [
            Match.pattern(.node(type: "Person", alias: "p", predicate: nil)),
            Return.count()
        ])
        
        let debugInfo = try query.debugInfo()
        
        XCTAssertNotNil(debugInfo.cypher)
        XCTAssertTrue(debugInfo.formattedDescription.contains("Query Debug Info"))
        XCTAssertTrue(debugInfo.compactDescription.contains("MATCH"))
    }
    
    func testQueryExplain() throws {
        let query = Query(components: [
            Match.pattern(.node(type: "Test", alias: "t", predicate: nil)),
            Return.items(.alias("t"))
        ])
        
        let explainQuery = query.explain()
        let cypher = try CypherCompiler.compile(explainQuery)
        
        XCTAssertTrue(cypher.query.hasPrefix("EXPLAIN"))
    }
    
    // MARK: - Subquery Tests
    
    func testSubqueryTypes() throws {
        // Scalar subquery
        let scalar = Subquery.scalar(Query(components: [
            Match.pattern(.node(type: "Test", alias: "t", predicate: nil)),
            Return.count()
        ]))
        
        let scalarCypher = try scalar.toCypher()
        XCTAssertTrue(scalarCypher.query.hasPrefix("("))
        XCTAssertTrue(scalarCypher.query.hasSuffix(")"))
        
        // List subquery
        let list = Subquery.list(Query(components: [
            Match.pattern(.node(type: "Test", alias: "t", predicate: nil)),
            Return.items(.alias("t"))
        ]))
        
        let listCypher = try list.toCypher()
        XCTAssertTrue(listCypher.query.hasPrefix("[("))
        XCTAssertTrue(listCypher.query.hasSuffix(")]"))
        
        // EXISTS subquery
        let exists = Subquery.exists(Query(components: [
            Match.pattern(.node(type: "Test", alias: "t", predicate: nil))
        ]))
        
        let existsCypher = try exists.toCypher()
        XCTAssertTrue(existsCypher.query.contains("EXISTS {"))
        XCTAssertTrue(existsCypher.query.contains("}"))
    }
    
    func testLetClause() throws {
        // Test various LET expressions
        let letValue = Let.value("x", 42)
        let valueCypher = try letValue.toCypher()
        XCTAssertTrue(valueCypher.query.contains("LET x ="))
        
        let letProperty = Let.property("name", PropertyReference(alias: "p", property: "name"))
        let propCypher = try letProperty.toCypher()
        XCTAssertTrue(propCypher.query.contains("LET name = p.name"))
        
        let letAgg = Let.aggregate("total", .count("*"))
        let aggCypher = try letAgg.toCypher()
        XCTAssertTrue(aggCypher.query.contains("LET total = COUNT(*)"))
    }
    
    func testRef() throws {
        let ref = Ref("myVar")
        let cypher = try ref.toCypher()
        XCTAssertEqual(cypher.query, "myVar")
    }
    
    // MARK: - CALL Clause Tests
    
    func testCallClause() throws {
        // Simple procedure call
        let call = Call.procedure("db.stats", yields: ["stat"])
        let cypher = try call.toCypher()
        XCTAssertEqual(cypher.query, "CALL db.stats() YIELD stat")
        
        // Call with parameters
        let callWithParams = Call.procedure(
            "custom.proc",
            parameters: ["x": 1, "y": "test"],
            yields: ["result"]
        )
        let paramCypher = try callWithParams.toCypher()
        XCTAssertTrue(paramCypher.query.contains("CALL custom.proc("))
        XCTAssertTrue(paramCypher.query.contains("x: $x"))
        XCTAssertTrue(paramCypher.query.contains("y: $y"))
        
        // Call with WHERE
        let callWithWhere = Call.procedure("db.test")
            .where(PropertyReference(alias: "x", property: "value") > 10)
            .yields("x", "y")
        
        let whereCypher = try callWithWhere.toCypher()
        XCTAssertTrue(whereCypher.query.contains("WHERE"))
        XCTAssertTrue(whereCypher.query.contains("YIELD x, y"))
    }
    
    // MARK: - Graph Algorithms Tests
    
    func testGraphAlgorithms() throws {
        // PageRank
        let pagerank = GraphAlgorithms.PageRank.compute(
            damping: 0.9,
            iterations: 30
        )
        let prCypher = try pagerank.toCypher()
        XCTAssertTrue(prCypher.query.contains("gds.pageRank"))
        XCTAssertEqual(prCypher.parameters["damping"] as? Double, 0.9)
        
        // Louvain
        let louvain = GraphAlgorithms.Louvain.simple()
        let louvainCypher = try louvain.toCypher()
        XCTAssertTrue(louvainCypher.query.contains("gds.louvain"))
        
        // Shortest Path
        let shortest = GraphAlgorithms.ShortestPath.dijkstra(
            source: "a",
            target: "b"
        )
        let shortestCypher = try shortest.toCypher()
        XCTAssertTrue(shortestCypher.query.contains("dijkstra"))
        
        // Connected Components
        let wcc = GraphAlgorithms.ConnectedComponents.weakly()
        let wccCypher = try wcc.toCypher()
        XCTAssertTrue(wccCypher.query.contains("gds.wcc"))
        
        // Centrality
        let centrality = GraphAlgorithms.Centrality.betweenness()
        let centralityCypher = try centrality.toCypher()
        XCTAssertTrue(centralityCypher.query.contains("gds.betweenness"))
        
        // Similarity
        let similarity = GraphAlgorithms.Similarity.jaccard(topK: 5)
        let similarityCypher = try similarity.toCypher()
        XCTAssertTrue(similarityCypher.query.contains("jaccard"))
    }
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