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
        
        #expect(query.cypherString != nil)
        #expect(query.cypherString?.contains("MATCH") ?? false)
        #expect(query.cypherString?.contains("Test") ?? false)
    }
    
    @Test("Query debug info")
    func testQueryDebugInfo() throws {
        let query = Query(components: [
            Match.pattern(.node(type: "Person", alias: "p", predicate: nil)),
            Return.count()
        ])
        
        let debugInfo = try query.debugInfo()
        
        #expect(!debugInfo.cypher.isEmpty)
        #expect(debugInfo.formattedDescription.contains("Query Debug Info"))
        #expect(debugInfo.compactDescription.contains("MATCH"))
    }
    
    @Test("Query explain")
    func testQueryExplain() throws {
        let query = Query(components: [
            Match.pattern(.node(type: "Test", alias: "t", predicate: nil)),
            Return.items(.alias("t"))
        ])
        
        let explainQuery = query.explain()
        let cypher = try CypherCompiler.compile(explainQuery)
        
        #expect(cypher.query.hasPrefix("EXPLAIN"))
    }
    
    // MARK: - Subquery Tests
    
    @Test("Subquery types")
    func testSubqueryTypes() throws {
        // Scalar subquery
        let scalar = Subquery.scalar(Query(components: [
            Match.pattern(.node(type: "Test", alias: "t", predicate: nil)),
            Return.count()
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
    
    @Test("Graph algorithms")
    func testGraphAlgorithms() throws {
        // PageRank
        let pagerank = GraphAlgorithms.PageRank.compute(
            damping: 0.9,
            iterations: 30
        )
        let prCypher = try pagerank.toCypher()
        #expect(prCypher.query.contains("gds.pageRank"))
        #expect(prCypher.parameters["damping"] as? Double == 0.9)
        
        // Louvain
        let louvain = GraphAlgorithms.Louvain.simple()
        let louvainCypher = try louvain.toCypher()
        #expect(louvainCypher.query.contains("gds.louvain"))
        
        // Shortest Path
        let shortest = GraphAlgorithms.ShortestPath.dijkstra(
            source: "a",
            target: "b"
        )
        let shortestCypher = try shortest.toCypher()
        #expect(shortestCypher.query.contains("dijkstra"))
        
        // Connected Components
        let wcc = GraphAlgorithms.ConnectedComponents.weakly()
        let wccCypher = try wcc.toCypher()
        #expect(wccCypher.query.contains("gds.wcc"))
        
        // Centrality
        let centrality = GraphAlgorithms.Centrality.betweenness()
        let centralityCypher = try centrality.toCypher()
        #expect(centralityCypher.query.contains("gds.betweenness"))
        
        // Similarity
        let similarity = GraphAlgorithms.Similarity.jaccard(topK: 5)
        let similarityCypher = try similarity.toCypher()
        #expect(similarityCypher.query.contains("jaccard"))
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