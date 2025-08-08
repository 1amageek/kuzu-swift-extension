import Testing
@testable import KuzuSwiftExtension
import struct Foundation.UUID
import struct Foundation.Date

// MARK: - Test Models

@GraphNode
struct TestUser: Codable, Sendable {
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
struct TestPost: Codable, Sendable {
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

@GraphEdge(from: TestUser.self, to: TestPost.self)
struct TestAuthored: Codable, Sendable {
    var authoredAt: Date = Date()
    var metadata: String?
    
    init(authoredAt: Date = Date(), metadata: String? = nil) {
        self.authoredAt = authoredAt
        self.metadata = metadata
    }
}

@Suite("Type-Safe API Tests")
struct TypeSafeAPITests {
    
    // MARK: - Helper Methods
    
    func createContext() async throws -> GraphContext {
        let config = GraphConfiguration(databasePath: ":memory:")
        let context = try await GraphContext(configuration: config)
        
        try await context.createSchema(for: [
            TestUser.self,
            TestPost.self,
            TestAuthored.self
        ])
        
        return context
    }
    
    func insertUser(_ user: TestUser, context: GraphContext) async throws {
        let cypher = """
            CREATE (u:TestUser {
                id: $id,
                email: $email,
                name: $name,
                age: $age,
                status: $status
            })
            """
        
        _ = try await context.raw(cypher, bindings: [
            "id": user.id.uuidString,
            "email": user.email,
            "name": user.name,
            "age": user.age,
            "status": user.status
        ])
    }
    
    func insertPost(_ post: TestPost, context: GraphContext) async throws {
        let cypher = """
            CREATE (p:TestPost {
                id: $id,
                title: $title,
                content: $content,
                authorId: $authorId
            })
            """
        
        _ = try await context.raw(cypher, bindings: [
            "id": post.id.uuidString,
            "title": post.title,
            "content": post.content,
            "authorId": post.authorId.uuidString
        ])
    }
    
    // MARK: - KeyPath Predicate Tests
    
    @Test("KeyPath-based property predicates")
    func propertyPathWithKeyPath() async throws {
        let context = try await createContext()
        
        // Create test users
        let alice = TestUser(email: "alice@example.com", name: "Alice", age: 30)
        let bob = TestUser(email: "bob@example.com", name: "Bob", age: 25)
        
        try await insertUser(alice, context: context)
        try await insertUser(bob, context: context)
        
        // Test KeyPath-based predicate
        let predicate = prop(\TestUser.name, on: "u") == "Alice"
        let cypher = try predicate.toCypher()
        
        #expect(cypher.query.contains("u.name"))
        #expect(cypher.parameters.values.contains { ($0 as? String) == "Alice" })
        
        // Execute query with predicate
        let result = try await context.raw(
            "MATCH (u:TestUser) WHERE \(cypher.query) RETURN u",
            bindings: cypher.parameters
        )
        
        #expect(result.hasNext())
        
        await context.close()
    }
    
    @Test("Property path comparisons", arguments: [
        ("equal", 30, true),
        ("not_equal", 25, true), 
        ("greater", 25, true),
        ("less", 35, true)
    ])
    func propertyPathComparisons(operation: String, compareValue: Int, shouldMatch: Bool) async throws {
        let context = try await createContext()
        
        let user = TestUser(email: "test@example.com", name: "Test", age: 30)
        try await insertUser(user, context: context)
        
        // Create predicate based on operation
        let predicate: Predicate
        switch operation {
        case "equal":
            predicate = prop(\TestUser.age, on: "u") == compareValue
        case "not_equal":
            predicate = prop(\TestUser.age, on: "u") != compareValue
        case "greater":
            predicate = prop(\TestUser.age, on: "u") > compareValue
        case "less":
            predicate = prop(\TestUser.age, on: "u") < compareValue
        default:
            predicate = prop(\TestUser.age, on: "u") == compareValue
        }
        
        let cypher = try predicate.toCypher()
        let result = try await context.raw(
            "MATCH (u:TestUser) WHERE \(cypher.query) RETURN COUNT(u) as count",
            bindings: cypher.parameters
        )
        
        let count = try result.mapFirst(to: Int64.self) ?? 0
        if shouldMatch {
            #expect(count == 1, "Expected match for operation: \(operation)")
        } else {
            #expect(count == 0, "Expected no match for operation: \(operation)")
        }
        
        await context.close()
    }
    
    // MARK: - Batch Operation Tests
    
    @Test("Batch create users")
    func batchCreate() async throws {
        let context = try await createContext()
        
        let users = [
            TestUser(email: "batch1@test.com", name: "Batch1", age: 25),
            TestUser(email: "batch2@test.com", name: "Batch2", age: 30),
            TestUser(email: "batch3@test.com", name: "Batch3", age: 35)
        ]
        
        // Use batchInsert instead of createMany
        try await context.batchInsert(users)
        
        // Verify creation
        let result = try await context.raw("MATCH (u:TestUser) RETURN COUNT(u) as count")
        let count = try result.mapFirst(to: Int64.self) ?? 0
        #expect(count == 3)
        
        await context.close()
    }
    
    @Test("Batch update users")
    func batchUpdate() async throws {
        let context = try await createContext()
        
        // Create users
        let users = [
            TestUser(email: "update1@test.com", name: "Update1", age: 20),
            TestUser(email: "update2@test.com", name: "Update2", age: 30),
            TestUser(email: "update3@test.com", name: "Update3", age: 40)
        ]
        
        for user in users {
            try await insertUser(user, context: context)
        }
        
        // Use raw update query instead of updateMany (which may not exist)
        let updateCypher = """
            MATCH (u:TestUser) 
            WHERE u.age > 25 
            SET u.status = 'senior'
            """
        _ = try await context.raw(updateCypher)
        
        // Verify update
        let result = try await context.raw("MATCH (u:TestUser) WHERE u.status = 'senior' RETURN COUNT(u) as count")
        let count = try result.mapFirst(to: Int64.self) ?? 0
        #expect(count == 2)
        
        await context.close()
    }
    
    @Test("Batch delete users")
    func batchDelete() async throws {
        let context = try await createContext()
        
        // Create users
        let users = [
            TestUser(email: "delete1@test.com", name: "Delete1", age: 20),
            TestUser(email: "delete2@test.com", name: "Delete2", age: 25),
            TestUser(email: "delete3@test.com", name: "Delete3", age: 30)
        ]
        
        for user in users {
            try await insertUser(user, context: context)
        }
        
        // Use raw delete query instead of deleteMany (which may not exist)
        let deleteCypher = """
            MATCH (u:TestUser)
            WHERE u.age < 28
            DELETE u
            """
        _ = try await context.raw(deleteCypher)
        
        // Verify deletion
        let result = try await context.raw("MATCH (u:TestUser) RETURN COUNT(u) as count")
        let count = try result.mapFirst(to: Int64.self) ?? 0
        #expect(count == 1)
        
        // Verify remaining user
        let remainingResult = try await context.raw("MATCH (u:TestUser) RETURN u.name as name")
        guard let row = try remainingResult.mapFirst() else {
            throw GraphError.invalidOperation(message: "No rows returned")
        }
        let name = row["name"] as? String
        #expect(name == "Delete3")
        
        await context.close()
    }
    
    // MARK: - Enhanced Result Mapping Tests
    
    @Test("Enhanced result mapping")
    func enhancedResultMapping() async throws {
        let context = try await createContext()
        
        // Create multiple users
        let users = [
            TestUser(email: "user1@test.com", name: "User1", age: 20),
            TestUser(email: "user2@test.com", name: "User2", age: 30),
            TestUser(email: "user3@test.com", name: "User3", age: 40)
        ]
        
        for user in users {
            try await insertUser(user, context: context)
        }
        
        // Test decode array
        let result = try await context.raw("MATCH (u:TestUser) RETURN u ORDER BY u.age")
        let decodedUsers = try result.decodeArray(TestUser.self)
        
        #expect(decodedUsers.count == 3)
        if decodedUsers.count >= 3 {
            #expect(decodedUsers[0].age == 20)
            #expect(decodedUsers[2].age == 40)
        }
        
        await context.close()
    }
    
    @Test("Result type mappings")
    func resultTypeMappings() async throws {
        let context = try await createContext()
        
        let user = TestUser(email: "mapper@test.com", name: "Mapper", age: 25)
        try await insertUser(user, context: context)
        
        // Map strings
        let namesResult = try await context.raw("MATCH (u:TestUser) RETURN u.name AS name")
        let nameRows = try namesResult.mapRows()
        let names = nameRows.compactMap { row -> String? in
            if let nameOpt = row["name"], let name = nameOpt as? String {
                return name
            }
            return nil
        }
        #expect(names.count == 1)
        #expect(names.first == "Mapper")
        
        // Map integers  
        let agesResult = try await context.raw("MATCH (u:TestUser) RETURN u.age AS age")
        let ageRows = try agesResult.mapRows()
        let ages = ageRows.compactMap { row -> Int? in
            if let ageOpt = row["age"] {
                if let age = ageOpt as? Int {
                    return age
                } else if let age64 = ageOpt as? Int64 {
                    return Int(age64)
                }
            }
            return nil
        }
        #expect(ages.count == 1)
        #expect(ages.first == 25)
        
        await context.close()
    }
}