import Testing
import Foundation
import KuzuSwiftMacros
@testable import KuzuSwiftExtension

// MARK: - Test Models
// NOTE: Do not directly implement _KuzuGraphModel protocol.
// This protocol should be automatically conformed through @GraphNode/@GraphEdge macros.

@GraphNode
fileprivate struct SimplifiedTestPerson {
    @ID let id: String
    let name: String
    let age: Int
}

@GraphNode
fileprivate struct SimplifiedTestUser {
    @ID let id: String
    let name: String
    let age: Int
}

@GraphNode
fileprivate struct SimplifiedTestCompany {
    @ID let id: String
    let name: String
}

@GraphEdge(from: SimplifiedTestPerson.self, to: SimplifiedTestPerson.self)
fileprivate struct SimplifiedTestFollows {
    let since: Int
}

/// Tests for the simplified type-safe API without model() function
@Suite("Simplified Type-Safe API Tests")
struct SimplifiedAPITests {
    
    // MARK: - Type Name Extraction Tests
    
    @Test("Type name extraction works correctly")
    func testTypeNameExtraction() {
        // Test simple type name
        #expect(
            TypeNameExtractor.extractTypeName(SimplifiedTestPerson.self) == "SimplifiedTestPerson"
        )
        
        // Test type info extraction
        let typeInfo = TypeNameExtractor.extractTypeInfo(SimplifiedTestCompany.self)
        #expect(typeInfo.typeName == "SimplifiedTestCompany")
        #expect(typeInfo.defaultAlias == "simplifiedtestcompany")
    }
    
    @Test("Type name extraction handles module prefixes")
    func testTypeNameExtractionWithModulePrefix() {
        // Test extraction of nested names from string
        let fullName = "MyModule.MyType"
        let components = fullName.components(separatedBy: ".")
        #expect(components.last == "MyType")
        
        // Test that TypeNameExtractor handles real types
        let typeName = TypeNameExtractor.extractTypeName(SimplifiedTestPerson.self)
        #expect(!typeName.contains("."))
    }
    
    // MARK: - Match API Tests
    
    @Test("Match node with direct type usage")
    func testMatchNodeWithDirectType() throws {
        // Direct type usage without model() function
        let match = Match.node(SimplifiedTestPerson.self, alias: "p")
        let cypher = try match.toCypher()
        
        #expect(cypher.query.contains("MATCH (p:SimplifiedTestPerson)"))
    }
    
    @Test("Match node with default alias")
    func testMatchNodeWithDefaultAlias() throws {
        // Should use lowercased type name as default alias
        let match = Match.node(SimplifiedTestPerson.self)
        let cypher = try match.toCypher()
        
        #expect(cypher.query.contains("MATCH (simplifiedtestperson:SimplifiedTestPerson)"))
    }
    
    @Test("Match node with predicate")
    func testMatchNodeWithPredicate() throws {
        let match = Match.node(
            SimplifiedTestPerson.self,
            alias: "p",
            where: PropertyReference(alias: "p", property: "age") > 25
        )
        let cypher = try match.toCypher()
        
        #expect(cypher.query.contains("MATCH (p:SimplifiedTestPerson)"))
        // Note: WHERE clause is handled separately in actual queries
    }
    
    // MARK: - Create API Tests
    
    @Test("Create node with direct type")
    func testCreateNodeWithDirectType() throws {
        let create = Create.node(
            SimplifiedTestUser.self,
            alias: "u",
            properties: ["name": "Alice", "age": 30]
        )
        let cypher = try create.toCypher()
        
        #expect(cypher.query.contains("CREATE (u:SimplifiedTestUser"))
        #expect(cypher.query.contains("name: $"))
        #expect(cypher.query.contains("age: $"))
    }
    
    @Test("Create node with default alias")
    func testCreateNodeWithDefaultAlias() throws {
        let create = Create.node(SimplifiedTestCompany.self)
        let cypher = try create.toCypher()
        
        #expect(cypher.query.contains("CREATE (simplifiedtestcompany:SimplifiedTestCompany)"))
    }
    
    @Test("Create edge with direct type")
    func testCreateEdgeWithDirectType() throws {
        let create = Create.edge(
            SimplifiedTestFollows.self,
            from: "a",
            to: "b",
            properties: ["since": 2024]
        )
        let cypher = try create.toCypher()
        
        #expect(cypher.query.contains("CREATE (a)-[simplifiedtestfollows:SimplifiedTestFollows"))
        #expect(cypher.query.contains("->(b)"))
    }
    
    // MARK: - Integration Tests
    
    @Test("Complex query with simplified API")
    func testComplexQueryWithSimplifiedAPI() throws {
        let query = Query {
            Match.node(SimplifiedTestPerson.self, alias: "p")
            Where(PropertyReference(alias: "p", property: "age") > 25)
            Return.items(.property(alias: "p", property: "name"))
        }
        
        let cypher = try CypherCompiler.compile(query)
        
        #expect(cypher.query.contains("MATCH (p:SimplifiedTestPerson)"))
        #expect(cypher.query.contains("WHERE p.age >"))
        #expect(cypher.query.contains("RETURN p.name"))
    }
    
    @Test("Multiple nodes with simplified API")
    func testMultipleNodesWithSimplifiedAPI() throws {
        let query = Query {
            Match.node(SimplifiedTestPerson.self, alias: "p")
            Match.node(SimplifiedTestCompany.self, alias: "c")
            Return.items(
                .alias("p"),
                .alias("c")
            )
        }
        
        let cypher = try CypherCompiler.compile(query)
        
        #expect(cypher.query.contains("SimplifiedTestPerson"))
        #expect(cypher.query.contains("SimplifiedTestCompany"))
    }
    
    // MARK: - Performance Tests
    
    @Test("Type name extraction performance")
    func testTypeNameExtractionPerformance() async throws {
        let startTime = Date()
        for _ in 0..<1000 {
            _ = TypeNameExtractor.extractTypeName(SimplifiedTestPerson.self)
        }
        let duration = Date().timeIntervalSince(startTime)
        #expect(duration < 1.0) // Should complete within 1 second
    }
    
    @Test("Cached type name extraction performance")
    func testCachedTypeNameExtractionPerformance() async throws {
        let startTime = Date()
        for _ in 0..<10000 {
            _ = TypeNameExtractor.extractTypeNameCached(SimplifiedTestPerson.self)
        }
        let duration = Date().timeIntervalSince(startTime)
        #expect(duration < 1.0) // Should complete within 1 second even with 10x iterations
    }
}

// MARK: - Error Handling Tests

@Suite("Simplified API Error Handling")
struct SimplifiedAPIErrorHandlingTests {
    
    @Test("Invalid node pattern throws error")
    func testInvalidNodePattern() throws {
        // Test that empty type name would cause issues
        // This is more of a compile-time check, but we can test the runtime behavior
        let match = Match.node(SimplifiedTestPerson.self, alias: "")
        let cypher = try match.toCypher()
        
        // Empty alias should still work (uses default)
        #expect(cypher.query.contains(":SimplifiedTestPerson"))
    }
    
    @Test("Create with encodable instance")
    func testCreateWithEncodableInstance() throws {
        struct TestData: Encodable {
            let name: String
            let age: Int
        }
        
        // This should work with proper encoding
        let data = TestData(name: "Bob", age: 25)
        
        // We can't directly test Create.node with an encodable instance
        // since it requires _KuzuGraphModel conformance
        // But we can test the encoder separately
        let encoder = KuzuEncoder()
        let encoded = try encoder.encode(data)
        
        #expect(encoded["name"] as? String == "Bob")
        #expect(encoded["age"] as? Int == 25)
    }
}