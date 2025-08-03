import XCTest
@testable import KuzuSwiftExtension
import Kuzu

@available(macOS 14.0, *)
final class SimplifiedParameterTests: XCTestCase {
    func testSimplifiedParameterSystem() throws {
        // Test that our simplified parameter system compiles correctly
        
        // Test basic types
        let stringParam: any Sendable = "test"
        let intParam: any Sendable = 42
        let doubleParam: any Sendable = 3.14
        let boolParam: any Sendable = true
        let dateParam: any Sendable = Date()
        let uuidParam: any Sendable = UUID()
        
        // Test collections
        let arrayParam: any Sendable = [1, 2, 3]
        let dictParam: any Sendable = ["key": "value"]
        
        // Test CypherFragment
        let fragment = CypherFragment(
            query: "MATCH (n:Person) WHERE n.age > $age",
            parameters: ["age": intParam]
        )
        
        XCTAssertEqual(fragment.query, "MATCH (n:Person) WHERE n.age > $age")
        XCTAssertEqual(fragment.parameters.count, 1)
        XCTAssertNotNil(fragment.parameters["age"])
        
        // Test Query DSL components
        let predicate = prop("n.name") == "Alice"
        let cypherResult = try predicate.toCypher()
        XCTAssertTrue(cypherResult.query.contains("n.name ="))
        XCTAssertEqual(cypherResult.parameters.count, 1)
        
        // Test Create with simplified parameters
        let createNode = Create.node(TestNode.self, properties: [
            "name": "Bob",
            "age": 30,
            "active": true
        ])
        let createCypher = try createNode.toCypher()
        XCTAssertTrue(createCypher.query.contains("CREATE"))
        XCTAssertTrue(createCypher.query.contains("TestNode"))
        XCTAssertEqual(createCypher.parameters.count, 3)
        
        // Test Merge with simplified parameters
        let merge = Merge.node(TestNode.self, matchProperties: ["id": UUID()])
            .onCreate(set: ["createdAt": Date()])
            .onMatch(set: ["updatedAt": Date()])
        let mergeCypher = try merge.toCypher()
        XCTAssertTrue(mergeCypher.query.contains("MERGE"))
        XCTAssertTrue(mergeCypher.query.contains("ON CREATE SET"))
        XCTAssertTrue(mergeCypher.query.contains("ON MATCH SET"))
        
        // Test SetClause with simplified parameters
        let setClause = SetClause.properties(on: "n", values: [
            "name": "Updated Name",
            "modifiedAt": Date()
        ])
        let setCypher = try setClause.toCypher()
        XCTAssertTrue(setCypher.query.contains("SET"))
        XCTAssertEqual(setCypher.parameters.count, 2)
        
        // Test that all parameters are Sendable
        let allParams: [String: any Sendable] = [
            "string": "test",
            "int": 42,
            "double": 3.14,
            "bool": true,
            "date": Date(),
            "uuid": UUID(),
            "array": [1, 2, 3],
            "dict": ["nested": "value"]
        ]
        
        // This should compile without errors
        let _ = CypherFragment(query: "TEST", parameters: allParams)
    }
}

// Test model for compilation verification
struct TestNode: _KuzuGraphModel {
    static let _kuzuDDL: String = "CREATE NODE TABLE TestNode (id UUID PRIMARY KEY, name STRING, age INT64, active BOOLEAN, createdAt TIMESTAMP, updatedAt TIMESTAMP)"
    static let _kuzuColumns: [String] = ["id", "name", "age", "active", "createdAt", "updatedAt"]
}