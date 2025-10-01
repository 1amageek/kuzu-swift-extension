import Testing
@testable import KuzuSwiftExtension
import struct Foundation.UUID
import struct Foundation.Date

// Test models defined at module level
@GraphNode
struct DDLTestUser: Codable, Sendable {
    @ID var email: String  // Using email as PRIMARY KEY for uniqueness
    var name: String
    @Default("active") var status: String = "active"
    var age: Int

    init(email: String, name: String, age: Int, status: String = "active") {
        self.email = email
        self.name = name
        self.age = age
        self.status = status
    }
}

@GraphNode
struct DDLTestPost: Codable, Sendable {
    @ID var id: UUID = UUID()
    var title: String
    @Attribute(.spotlight) var content: String
    var authorId: UUID

    init(title: String, content: String, authorId: UUID) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.authorId = authorId
    }
}

@GraphEdge
struct DDLTestAuthored: Codable, Sendable {
    @Since(\DDLTestUser.email) var authorEmail: String
    @Target(\DDLTestPost.id) var postID: String
    var authoredAt: Date = Date()
    var metadata: String?
}

@Suite("DDL Debug Tests")
struct DDLDebugTest {
    
    @Test("Debug DDL generation")
    func debugDDL() async throws {
        // Verify DDL is generated correctly
        #expect(!DDLTestUser._kuzuDDL.isEmpty, "User DDL should be generated")
        #expect(!DDLTestUser._kuzuColumns.isEmpty, "User columns should be defined")
        
        #expect(!DDLTestPost._kuzuDDL.isEmpty, "Post DDL should be generated")
        #expect(!DDLTestPost._kuzuColumns.isEmpty, "Post columns should be defined")
        
        #expect(!DDLTestAuthored._kuzuDDL.isEmpty, "Edge DDL should be generated")
        #expect(!DDLTestAuthored._kuzuColumns.isEmpty, "Edge columns should be defined")
        
        // Try to create a context and schema
        let config = GraphConfiguration(databasePath: ":memory:")
        let container = try GraphContainer(configuration: config)
        let context = GraphContext(container)
        
        // Schema creation should not throw
        try context.createSchema(for: [
            DDLTestUser.self,
            DDLTestPost.self,
            DDLTestAuthored.self
        ])
        
        // Try a simple insert and verify it works
        let user = DDLTestUser(email: "test@example.com", name: "Test", age: 30)
        context.insert(user)
        try context.save()

        // Fetch the saved user
        let users = try context.fetch(DDLTestUser.self)
        #expect(users.count == 1)
        let savedUser = users.first!
        #expect(savedUser.email == "test@example.com")
        #expect(savedUser.name == "Test")
        #expect(savedUser.age == 30)
        #expect(savedUser.status == "active", "Default value should be applied")

        // Verify the user was actually saved
        let count = try context.count(DDLTestUser.self)
        #expect(count == 1, "One user should be saved")
        
        // Cleanup
    }
}