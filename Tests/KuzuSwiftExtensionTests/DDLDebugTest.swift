import Testing
@testable import KuzuSwiftExtension
import struct Foundation.UUID
import struct Foundation.Date

// Test models defined at module level
@GraphNode
struct DDLTestUser: Codable, Sendable {
    @ID var id: UUID = UUID()
    @Unique var email: String
    var name: String
    @Default("active") var status: String = "active"
    var age: Int
    
    init(email: String, name: String, age: Int, status: String = "active") {
        self.id = UUID()
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
    @FullTextSearch var content: String
    var authorId: UUID
    
    init(title: String, content: String, authorId: UUID) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.authorId = authorId
    }
}

@GraphEdge(from: DDLTestUser.self, to: DDLTestPost.self)
struct DDLTestAuthored: Codable, Sendable {
    var authoredAt: Date = Date()
    var metadata: String?
    
    init(authoredAt: Date = Date(), metadata: String? = nil) {
        self.authoredAt = authoredAt
        self.metadata = metadata
    }
}

@Suite("DDL Debug Tests")
struct DDLDebugTest {
    
    @Test("Debug DDL generation")
    func debugDDL() async throws {
        print("=====================================")
        print("DDLTestUser DDL: \(DDLTestUser._kuzuDDL)")
        print("DDLTestUser Columns: \(DDLTestUser._kuzuColumns)")
        print("=====================================")
        
        print("DDLTestPost DDL: \(DDLTestPost._kuzuDDL)")
        print("DDLTestPost Columns: \(DDLTestPost._kuzuColumns)")
        print("=====================================")
        
        print("DDLTestAuthored DDL: \(DDLTestAuthored._kuzuDDL)")
        print("DDLTestAuthored Columns: \(DDLTestAuthored._kuzuColumns)")
        print("=====================================")
        
        // Try to create a context and schema
        let config = GraphConfiguration(databasePath: ":memory:")
        let context = try await GraphContext(configuration: config)
        
        print("Creating schema...")
        do {
            try await context.createSchema(for: [
                DDLTestUser.self,
                DDLTestPost.self,
                DDLTestAuthored.self
            ])
            print("Schema created successfully")
            
            // Try a simple insert
            let user = DDLTestUser(email: "test@example.com", name: "Test", age: 30)
            print("Attempting to save user...")
            _ = try await context.save(user)
            print("User saved successfully")
            
        } catch {
            print("Operation failed: \(error)")
            if let graphError = error as? GraphError {
                print("GraphError details: \(graphError)")
            }
            throw error
        }
        
        await context.close()
    }
}