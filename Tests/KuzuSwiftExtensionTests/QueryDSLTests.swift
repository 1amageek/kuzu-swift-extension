import Testing
@testable import KuzuSwiftExtension
import Foundation

// Test models for Query DSL tests - prefixed with DSL to avoid conflicts
@GraphNode
struct DSLTestUser {
    @ID var id: UUID = UUID()
    var name: String
    var age: Int
    @Timestamp var createdAt: Date = Date()
}

@GraphNode  
struct DSLTestPost {
    @ID var id: UUID = UUID()
    var title: String
    var content: String
    var likes: Int = 0
    @Timestamp var createdAt: Date = Date()
}

@GraphEdge(from: DSLTestUser.self, to: DSLTestUser.self)
struct DSLTestFollows {
    @Timestamp var since: Date = Date()
}

@GraphEdge(from: DSLTestUser.self, to: DSLTestPost.self)
struct DSLTestAuthored {
    @Timestamp var authoredAt: Date = Date()
}

@Suite("Query DSL Tests")
struct QueryDSLTests {
    
    @Test("Query DSL compiles - basic node match")
    func queryDSLCompiles() throws {
        // Test basic Match
        let query = Query(components: [
            Match.pattern(.node(type: "User", alias: "u", predicate: nil)),
            Return.items(.alias("u"))
        ])
        
        let cypher = try CypherCompiler.compile(query)
        #expect(cypher.query.contains("MATCH"))
        #expect(cypher.query.contains("(u:User)"))
        #expect(cypher.query.contains("RETURN"))
    }
    
    @Test("Query DSL with predicate")
    func queryWithPredicate() throws {
        let predicate = Predicate(node: .comparison(ComparisonExpression(
            lhs: PropertyReference(alias: "u", property: "name"),
            op: .equal,
            rhs: .value("Alice")
        )))
        
        let query = Query(components: [
            Match.node(DSLTestUser.self, alias: "u", where: predicate),
            Return.items(.alias("u"))
        ])
        
        let cypher = try CypherCompiler.compile(query)
        #expect(cypher.query.contains("MATCH"))
        #expect(cypher.query.contains("WHERE"))
        #expect(cypher.query.contains("u.name"))
    }
    
    @Test("Query DSL with edge matching")
    func queryWithEdgeMatching() throws {
        let query = Query(components: [
            Match.pattern(.node(type: "User", alias: "u", predicate: nil)),
            Match.pattern(.edge(type: "Follows", from: "u", to: "other", alias: "f", predicate: nil)),
            Return.items(.alias("u"), .alias("other"))
        ])
        
        let cypher = try CypherCompiler.compile(query)
        #expect(cypher.query.contains("MATCH"))
        #expect(cypher.query.contains("(u:User)"))
        #expect(cypher.query.contains("-[f:Follows]->"))
        #expect(cypher.query.contains("RETURN"))
    }
    
    @Test("Query DSL with aggregation")
    func queryWithAggregation() throws {
        let query = Query(components: [
            Match.pattern(.node(type: "Post", alias: "p", predicate: nil)),
            Return.items([.count(nil)])
        ])
        
        let cypher = try CypherCompiler.compile(query)
        #expect(cypher.query.contains("COUNT(*)"))
    }
    
    @Test("Query DSL with WITH clause")
    func queryWithWithClause() throws {
        let query = Query(components: [
            Match.pattern(.node(type: "User", alias: "u", predicate: nil)),
            With.aggregate(.count("u"), as: "userCount")
                .and("u")
                .limit(10),
            Return.items(.alias("u"), .aliased(expression: "userCount", alias: "count"))
        ])
        
        let cypher = try CypherCompiler.compile(query)
        #expect(cypher.query.contains("WITH"))
        #expect(cypher.query.contains("COUNT(u) AS userCount"))
        #expect(cypher.query.contains("LIMIT 10"))
    }
    
    @Test("Query DSL with OPTIONAL MATCH")
    func queryWithOptionalMatch() throws {
        let query = Query(components: [
            Match.pattern(.node(type: "User", alias: "u", predicate: nil)),
            OptionalMatch.pattern(.node(type: "Post", alias: "p", predicate: nil)),
            Return.items(.alias("u"), .alias("p"))
        ])
        
        let cypher = try CypherCompiler.compile(query)
        #expect(cypher.query.contains("OPTIONAL MATCH"))
        #expect(cypher.query.contains("(p:Post)"))
    }
    
    @Test("Query DSL compilation - complex query")
    func complexQueryCompilation() throws {
        let predicate = Predicate(node: .comparison(ComparisonExpression(
            lhs: PropertyReference(alias: "u", property: "age"),
            op: .greaterThan,
            rhs: .value(25)
        )))
        
        let query = Query(components: [
            Match.node(DSLTestUser.self, alias: "u", where: predicate),
            Match.edge(DSLTestFollows.self)
                .from("u")
                .to("friend"),
            Return.items(
                .alias("u"),
                .alias("friend"),
                .property(alias: "u", property: "name"),
                .property(alias: "friend", property: "name")
            )
        ])
        
        let cypher = try CypherCompiler.compile(query)
        #expect(cypher.query.contains("MATCH"))
        #expect(cypher.query.contains("WHERE"))
        #expect(cypher.query.contains("u.age > "))
        #expect(cypher.query.contains("DSLTestFollows"))
        #expect(cypher.query.contains("RETURN"))
    }
    
    @Test("Query DSL with multiple aggregations")
    func multipleAggregations() throws {
        let query = Query(components: [
            Match.pattern(.node(type: "User", alias: "u", predicate: nil)),
            Return.items([
                .aliased(expression: "COUNT(u)", alias: "total"),
                .aliased(expression: "MAX(u.age)", alias: "maxAge"),
                .aliased(expression: "MIN(u.age)", alias: "minAge"),
                .aliased(expression: "AVG(u.age)", alias: "avgAge")
            ])
        ])
        
        let cypher = try CypherCompiler.compile(query)
        #expect(cypher.query.contains("COUNT(u) AS total"))
        #expect(cypher.query.contains("MAX(u.age) AS maxAge"))
        #expect(cypher.query.contains("MIN(u.age) AS minAge"))
        #expect(cypher.query.contains("AVG(u.age) AS avgAge"))
    }
    
    @Test("Query DSL with EXISTS pattern")
    func queryWithExists() throws {
        let exists = Exists.edge(
            DSLTestFollows.self,
            from: "u",
            to: "other"
        )
        
        let predicate = Predicate.exists(exists)
        
        let query = Query(components: [
            Match.pattern(.node(type: "User", alias: "u", predicate: predicate)),
            Return.items(.alias("u"))
        ])
        
        let cypher = try CypherCompiler.compile(query)
        #expect(cypher.query.contains("EXISTS"))
    }
    
    @Test("Query DSL with path pattern")
    func queryWithPathPattern() throws {
        let query = Query(components: [
            Match.pattern(.path(
                from: "start",
                to: "end",
                edgeType: "KNOWS",
                minHops: 1,
                maxHops: 3,
                alias: "p"
            )),
            Return.items(.alias("p"))
        ])
        
        let cypher = try CypherCompiler.compile(query)
        #expect(cypher.query.contains("p = (start)"))
        #expect(cypher.query.contains("-[:KNOWS*1..3]->"))
        #expect(cypher.query.contains("(end)"))
    }
    
    @Test("Query DSL with Create")
    func queryWithCreate() throws {
        let query = Query(components: [
            Create.node(DSLTestUser.self, alias: "u", properties: [
                "name": "Alice",
                "age": 30
            ]),
            Return.items(.alias("u"))
        ])
        
        let cypher = try CypherCompiler.compile(query)
        #expect(cypher.query.contains("CREATE"))
        #expect(cypher.query.contains("(u:DSLTestUser"))
        #expect(cypher.query.contains("name:"))
        #expect(cypher.query.contains("age:"))
    }
    
    @Test("PropertyPath helper functions")
    func helperFunctions() {
        // Test PropertyPath creation
        let pathResult = PropertyPath<DSLTestUser>(keyPath: \DSLTestUser.age, alias: "u")
        #expect(pathResult.propertyName == "age")
        #expect(pathResult.alias == "u")
        
        let propResult = PropertyPath<DSLTestUser>(keyPath: \DSLTestUser.name, alias: "u")
        #expect(propResult.propertyName == "name")
        #expect(propResult.alias == "u")
    }
}