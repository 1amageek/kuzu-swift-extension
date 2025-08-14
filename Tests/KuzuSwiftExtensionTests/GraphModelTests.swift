import Testing
@testable import KuzuSwiftExtension
import struct Foundation.UUID
import struct Foundation.Date

// Test models for Graph Model tests (using unique names)
@GraphNode
struct ModelTestUser: Sendable {
    @ID var id: UUID = UUID()
    var name: String
    var age: Int
    @Timestamp var createdAt: Date = Date()
    
    init(name: String, age: Int) {
        self.id = UUID()
        self.name = name
        self.age = age
        self.createdAt = Date()
    }
}

@GraphNode
struct ModelTestPost: Sendable {
    @ID var id: UUID = UUID()
    var title: String
    var content: String
    @Timestamp var createdAt: Date = Date()
    
    init(title: String, content: String) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.createdAt = Date()
    }
}

@GraphEdge(from: ModelTestUser.self, to: ModelTestPost.self)
struct ModelAuthoredBy: Sendable {
    @Timestamp var authoredAt: Date = Date()
    
    init() {
        self.authoredAt = Date()
    }
}

@Suite("Graph Model Tests")
struct GraphModelTests {
    
    // MARK: - Test Setup and Teardown
    
    func createContext() async throws -> GraphContext {
        let config = GraphConfiguration(databasePath: ":memory:")
        let context = try await GraphContext(configuration: config)
        
        try await context.createSchema(for: [ModelTestUser.self, ModelTestPost.self, ModelAuthoredBy.self])
        
        return context
    }
    
    // MARK: - Basic CRUD Tests
    
    @Test("Save and fetch user")
    func saveAndFetch() async throws {
        let context = try await createContext()
        
        // Create and save
        let user = ModelTestUser(name: "Alice", age: 30)
        let savedUser = try await context.save(user)
        
        #expect(savedUser.name == "Alice")
        #expect(savedUser.age == 30)
        
        // Fetch all
        let users = try await context.fetch(ModelTestUser.self)
        #expect(users.count == 1)
        #expect(users.first?.name == "Alice")
        
        await context.close()
    }
    
    @Test("Fetch one user by ID")
    func fetchOne() async throws {
        let context = try await createContext()
        
        let user = ModelTestUser(name: "Bob", age: 25)
        let saved = try await context.save(user)
        
        // Fetch by ID
        let fetched = try await context.fetchOne(ModelTestUser.self, id: saved.id)
        #expect(fetched != nil)
        #expect(fetched?.name == "Bob")
        
        // Fetch non-existent
        let notFound = try await context.fetchOne(ModelTestUser.self, id: UUID())
        #expect(notFound == nil)
        
        await context.close()
    }
    
    @Test("Update user")
    func updateUser() async throws {
        let context = try await createContext()
        
        // Create
        var user = ModelTestUser(name: "Charlie", age: 35)
        user = try await context.save(user)
        
        // Update
        user.age = 36
        _ = try await context.save(user)
        
        // Verify
        let fetched = try await context.fetchOne(ModelTestUser.self, id: user.id)
        #expect(fetched?.age == 36)
        
        await context.close()
    }
    
    @Test("Delete user")
    func deleteUser() async throws {
        let context = try await createContext()
        
        let user = ModelTestUser(name: "Dave", age: 40)
        let saved = try await context.save(user)
        
        // Delete
        try await context.delete(saved)
        
        // Verify
        let users = try await context.fetch(ModelTestUser.self)
        #expect(users.count == 0)
        
        await context.close()
    }
    
    @Test("Delete all users")
    func deleteAll() async throws {
        let context = try await createContext()
        
        // Create multiple users
        let users = [
            ModelTestUser(name: "User1", age: 20),
            ModelTestUser(name: "User2", age: 25),
            ModelTestUser(name: "User3", age: 30)
        ]
        
        for user in users {
            _ = try await context.save(user)
        }
        
        // Verify creation
        let allUsers = try await context.fetch(ModelTestUser.self)
        #expect(allUsers.count == 3)
        
        // Delete all
        try await context.deleteAll(ModelTestUser.self)
        
        // Verify deletion
        let remainingUsers = try await context.fetch(ModelTestUser.self)
        #expect(remainingUsers.count == 0)
        
        await context.close()
    }
    
    // MARK: - Query Tests
    
    @Test("Fetch with predicate")
    func fetchWithPredicate() async throws {
        let context = try await createContext()
        
        // Create users with different ages
        let users = [
            ModelTestUser(name: "Young", age: 20),
            ModelTestUser(name: "Adult", age: 30),
            ModelTestUser(name: "Senior", age: 60)
        ]
        
        for user in users {
            _ = try await context.save(user)
        }
        
        // Query for users over 25 - using raw query since greaterThan may not exist
        let result = try await context.raw("MATCH (u:ModelTestUser) WHERE u.age > 25 RETURN u ORDER BY u.name")
        let adults = try result.decodeArray(ModelTestUser.self)
        #expect(adults.count == 2)
        
        let adultNames = adults.map { $0.name }.sorted()
        #expect(adultNames == ["Adult", "Senior"])
        
        await context.close()
    }
    
    @Test("Count users")
    func countUsers() async throws {
        let context = try await createContext()
        
        // Initially empty
        let initialCount = try await context.count(ModelTestUser.self)
        #expect(initialCount == 0)
        
        // Add some users
        for i in 1...5 {
            let user = ModelTestUser(name: "User\(i)", age: 20 + i)
            _ = try await context.save(user)
        }
        
        // Count all
        let totalCount = try await context.count(ModelTestUser.self)
        #expect(totalCount == 5)
        
        await context.close()
    }
    
    @Test("Count with predicate")
    func countWithPredicate() async throws {
        let context = try await createContext()
        
        // Create users with different ages
        let users = [
            ModelTestUser(name: "Young1", age: 18),
            ModelTestUser(name: "Young2", age: 22),
            ModelTestUser(name: "Adult1", age: 30),
            ModelTestUser(name: "Adult2", age: 35),
            ModelTestUser(name: "Senior", age: 65)
        ]
        
        for user in users {
            _ = try await context.save(user)
        }
        
        // Count adults (25-60) - using raw query since between may not exist
        let countResult = try await context.raw("MATCH (u:ModelTestUser) WHERE u.age >= 25 AND u.age <= 60 RETURN COUNT(u) as count")
        let adultCount = try countResult.mapFirst(to: Int64.self) ?? 0
        #expect(adultCount == Int64(2))
        
        await context.close()
    }
    
    // MARK: - Batch Operations Tests
    
    @Test("Batch save users")
    func batchSave() async throws {
        let context = try await createContext()
        
        let users = [
            ModelTestUser(name: "Batch1", age: 25),
            ModelTestUser(name: "Batch2", age: 30),
            ModelTestUser(name: "Batch3", age: 35)
        ]
        
        let savedUsers = try await context.save(users)
        #expect(savedUsers.count == 3)
        
        let allUsers = try await context.fetch(ModelTestUser.self)
        #expect(allUsers.count == 3)
        
        await context.close()
    }
    
    @Test("Batch insert users")  
    func batchInsert() async throws {
        let context = try await createContext()
        
        let users = [
            ModelTestUser(name: "Insert1", age: 20),
            ModelTestUser(name: "Insert2", age: 25),
            ModelTestUser(name: "Insert3", age: 30)
        ]
        
        // Use batchInsert instead of insert (which doesn't exist)
        try await context.batchInsert(users)
        
        let allUsers = try await context.fetch(ModelTestUser.self)
        #expect(allUsers.count == 3)
        
        let names = allUsers.map { $0.name }.sorted()
        #expect(names == ["Insert1", "Insert2", "Insert3"])
        
        await context.close()
    }
    
    // MARK: - Relationship Tests
    
    @Test("Create relationship")
    func createRelationship() async throws {
        let context = try await createContext()
        
        // Create user and post
        let user = ModelTestUser(name: "Author", age: 28)
        let post = ModelTestPost(title: "My Post", content: "Content")
        
        let savedUser = try await context.save(user)
        let savedPost = try await context.save(post)
        
        // Create relationship
        let relationship = ModelAuthoredBy()
        try await context.createRelationship(from: savedUser, to: savedPost, edge: relationship)
        
        // Verify relationship exists
        let result = try await context.raw("""
            MATCH (:ModelTestUser {id: $userId})-[r:ModelAuthoredBy]->(:ModelTestPost {id: $postId})
            RETURN count(r) as count
            """, bindings: ["userId": savedUser.id, "postId": savedPost.id])
        
        #expect(result.hasNext())
        if let flatTuple = try result.getNext(),
           let count = try flatTuple.getValue(0) as? Int64 {
            #expect(count > 0, "Relationship should exist")
        } else {
            Issue.record("Failed to verify relationship")
        }
        
        await context.close()
    }
    
    // MARK: - Transaction Tests
    
    @Test("Transaction rollback on error")
    func transactionRollback() async throws {
        let context = try await createContext()
        
        // Initial count
        let initialCount = try await context.count(ModelTestUser.self)
        #expect(initialCount == 0)
        
        // Transaction that should fail
        do {
            try await context.withTransaction { txCtx in
                let user1 = ModelTestUser(name: "TxUser1", age: 25)
                _ = try txCtx.save(user1)  // No await - synchronous
                
                let user2 = ModelTestUser(name: "TxUser2", age: 30)  
                _ = try txCtx.save(user2)  // No await - synchronous
                
                // Force an error
                throw TestError.intentionalError
            }
            
            Issue.record("Transaction should have failed")
        } catch {
            // Expected error
            #expect(error is TestError)
        }
        
        // Verify rollback - count should still be 0
        let finalCount = try await context.count(ModelTestUser.self)
        #expect(finalCount == 0)
        
        await context.close()
    }
    
    @Test("Successful transaction")
    func successfulTransaction() async throws {
        let context = try await createContext()
        
        // Transaction that should succeed
        try await context.withTransaction { txCtx in
            let user1 = ModelTestUser(name: "TxUser1", age: 25)
            let user2 = ModelTestUser(name: "TxUser2", age: 30)
            
            _ = try txCtx.save(user1)  // No await - synchronous
            _ = try txCtx.save(user2)  // No await - synchronous
        }
        
        // Verify transaction succeeded
        let count = try await context.count(ModelTestUser.self)
        #expect(count == 2)
        
        await context.close()
    }
}

// MARK: - Test Error Types

enum TestError: Error {
    case intentionalError
}