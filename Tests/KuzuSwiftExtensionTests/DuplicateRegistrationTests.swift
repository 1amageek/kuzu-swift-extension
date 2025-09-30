import Testing
import Foundation
@testable import KuzuSwiftExtension
import Kuzu

@Suite("Duplicate Registration Tests")
struct DuplicateRegistrationTests {
    
    // Test models
    @GraphNode
    struct TestUser: Codable, Sendable {
        @ID var id: UUID = UUID()
        var name: String
    }
    
    @GraphNode
    struct TestPost: Codable, Sendable {
        @ID var id: UUID = UUID()
        var title: String
    }
    
    @GraphEdge(from: TestUser.self, to: TestPost.self)
    struct TestAuthor: Codable, Sendable {
        var createdAt: Date
    }
    
    @Test("Duplicate model registration should not crash")
    func testDuplicateModelRegistration() async throws {
        // Use the shared instance since init is private
        let database = await GraphDatabase.shared
        
        // Register models multiple times - this should not cause duplicates
        await database.register(models: [TestUser.self, TestPost.self, TestAuthor.self])
        await database.register(models: [TestUser.self, TestPost.self])  // Duplicate registration
        await database.register(models: [TestUser.self, TestAuthor.self]) // Another duplicate
        
        // Create in-memory database for testing
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // This should not crash with "Dictionary literal contains duplicate keys"
        let context = try await GraphDatabase.createTestContext(
            models: [TestUser.self, TestPost.self, TestAuthor.self,
                    TestUser.self, TestPost.self]  // Intentional duplicates
        )
        
        // Verify the schema was created correctly
        _ = try await context.raw("MATCH (u:TestUser) RETURN count(u)", bindings: [:])
        _ = try await context.raw("MATCH (p:TestPost) RETURN count(p)", bindings: [:])
        
        // Verify we can create data
        let userId = UUID()
        let postId = UUID()
        
        _ = try await context.raw(
            "CREATE (u:TestUser {id: $id, name: $name})",
            bindings: ["id": userId.uuidString, "name": "Test User"]
        )
        
        _ = try await context.raw(
            "CREATE (p:TestPost {id: $id, title: $title})",
            bindings: ["id": postId.uuidString, "title": "Test Post"]
        )
        
        // Use timestamp() function to convert properly
        let createdAtStr = ISO8601DateFormatter().string(from: Date())
        _ = try await context.raw(
            """
            MATCH (u:TestUser {id: $userId}), (p:TestPost {id: $postId})
            CREATE (u)-[:TestAuthor {createdAt: timestamp($createdAt)}]->(p)
            """,
            bindings: [
                "userId": userId.uuidString,
                "postId": postId.uuidString,
                "createdAt": createdAtStr
            ]
        )
        
        // Verify the relationship was created
        let result = try await context.raw(
            "MATCH (u:TestUser)-[:TestAuthor]->(p:TestPost) RETURN count(*) as cnt",
            bindings: [:]
        )
        #expect(try result.mapFirstRequired(to: Int64.self, at: 0) == 1)
    }
    
    @Test("GraphSchema.discover should handle duplicates gracefully")
    func testGraphSchemaDiscoverWithDuplicates() {
        // Create a list with duplicate models
        let models: [any _KuzuGraphModel.Type] = [
            TestUser.self,
            TestPost.self,
            TestAuthor.self,
            TestUser.self,  // Duplicate
            TestPost.self,  // Duplicate
            TestAuthor.self // Duplicate
        ]
        
        // This should not crash and should produce a schema with unique tables
        let schema = GraphSchema.discover(from: models)
        
        // Verify we have exactly one of each table
        #expect(schema.nodes.count == 2)  // TestUser, TestPost
        #expect(schema.edges.count == 1)  // TestAuthor
        
        // Verify the names are correct
        let nodeNames = Set(schema.nodes.map { $0.name })
        #expect(nodeNames.contains("TestUser"))
        #expect(nodeNames.contains("TestPost"))
        
        let edgeNames = Set(schema.edges.map { $0.name })
        #expect(edgeNames.contains("TestAuthor"))
    }
    
    @Test("SchemaDiff should handle schemas with unique keys")
    func testSchemaDiffWithUniqueKeys() {
        // Create schemas that would previously cause crashes
        let models: [any _KuzuGraphModel.Type] = [TestUser.self, TestPost.self, TestAuthor.self]
        let schema1 = GraphSchema.discover(from: models)
        let schema2 = GraphSchema.discover(from: models)
        
        // This should not crash even if there were duplicates
        let diff = SchemaDiff.compare(current: schema1, target: schema2)
        
        // Should have no differences since schemas are identical
        #expect(diff.isEmpty)
    }
}