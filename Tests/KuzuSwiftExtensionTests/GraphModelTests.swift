import XCTest
import KuzuSwiftExtension
@testable import KuzuSwiftExtension

// Test model
@GraphNode
struct TestUser {
    @ID var id: UUID = UUID()
    var name: String
    var age: Int
    @Timestamp var createdAt: Date = Date()
}

@GraphNode
struct TestPost {
    @ID var id: UUID = UUID()
    var title: String
    var content: String
    @Timestamp var createdAt: Date = Date()
}

@GraphEdge(from: TestUser.self, to: TestPost.self)
struct AuthoredBy {
    @Timestamp var authoredAt: Date = Date()
}

final class GraphModelTests: XCTestCase {
    var context: GraphContext!
    
    override func setUp() async throws {
        try await super.setUp()
        // Use in-memory database for tests
        let config = GraphConfiguration(databasePath: ":memory:")
        context = try await GraphContext(configuration: config)
        
        // Create schema
        try await context.createSchema(for: [TestUser.self, TestPost.self, AuthoredBy.self])
    }
    
    override func tearDown() async throws {
        await context.close()
        context = nil
        try await super.tearDown()
    }
    
    // MARK: - Basic CRUD Tests
    
    func testSaveAndFetch() async throws {
        // Create and save
        let user = TestUser(name: "Alice", age: 30)
        let savedUser = try await context.save(user)
        
        XCTAssertEqual(savedUser.name, "Alice")
        XCTAssertEqual(savedUser.age, 30)
        
        // Fetch all
        let users = try await context.fetch(TestUser.self)
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.name, "Alice")
    }
    
    func testFetchOne() async throws {
        let user = TestUser(name: "Bob", age: 25)
        let saved = try await context.save(user)
        
        // Fetch by ID
        let fetched = try await context.fetchOne(TestUser.self, id: saved.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "Bob")
        
        // Fetch non-existent
        let notFound = try await context.fetchOne(TestUser.self, id: UUID())
        XCTAssertNil(notFound)
    }
    
    func testUpdate() async throws {
        // Create
        var user = TestUser(name: "Charlie", age: 35)
        user = try await context.save(user)
        
        // Update
        user.age = 36
        let updated = try await context.save(user)
        
        // Verify
        let fetched = try await context.fetchOne(TestUser.self, id: user.id)
        XCTAssertEqual(fetched?.age, 36)
    }
    
    func testDelete() async throws {
        let user = TestUser(name: "Dave", age: 40)
        let saved = try await context.save(user)
        
        // Delete
        try await context.delete(saved)
        
        // Verify
        let users = try await context.fetch(TestUser.self)
        XCTAssertEqual(users.count, 0)
    }
    
    func testDeleteAll() async throws {
        // Create multiple users
        for i in 1...5 {
            _ = try await context.save(TestUser(name: "User\(i)", age: 20 + i))
        }
        
        // Verify creation
        let count = try await context.count(TestUser.self)
        XCTAssertEqual(count, 5)
        
        // Delete all
        try await context.deleteAll(TestUser.self)
        
        // Verify deletion
        let afterCount = try await context.count(TestUser.self)
        XCTAssertEqual(afterCount, 0)
    }
    
    // MARK: - Predicate Tests
    
    func testFetchWithPredicate() async throws {
        // Create test data
        let users = [
            TestUser(name: "Alice", age: 25),
            TestUser(name: "Bob", age: 30),
            TestUser(name: "Charlie", age: 35),
            TestUser(name: "Dave", age: 30)
        ]
        
        for user in users {
            _ = try await context.save(user)
        }
        
        // Fetch with age predicate
        let thirtyYearOlds = try await context.fetch(TestUser.self, where: "age", equals: 30)
        
        XCTAssertEqual(thirtyYearOlds.count, 2)
        XCTAssertTrue(thirtyYearOlds.allSatisfy { $0.age == 30 })
    }
    
    func testCountWithPredicate() async throws {
        // Create test data
        for i in 1...10 {
            _ = try await context.save(TestUser(name: "User\(i)", age: 20 + (i % 3)))
        }
        
        // Count with predicate (age > 21 means age = 22 in our test data)
        let count = try await context.count(TestUser.self, where: "age", equals: 22)
        
        XCTAssertEqual(count, 3)
    }
    
    // MARK: - Batch Operations
    
    func testBatchSave() async throws {
        let users = [
            TestUser(name: "User1", age: 20),
            TestUser(name: "User2", age: 21),
            TestUser(name: "User3", age: 22)
        ]
        
        let saved = try await context.save(users)
        XCTAssertEqual(saved.count, 3)
        
        let fetched = try await context.fetch(TestUser.self)
        XCTAssertEqual(fetched.count, 3)
    }
    
    func testBatchInsert() async throws {
        let users = (1...100).map { i in
            TestUser(name: "User\(i)", age: 20 + (i % 10))
        }
        
        try await context.batchInsert(users)
        
        let count = try await context.count(TestUser.self)
        XCTAssertEqual(count, 100)
    }
    
    // MARK: - Relationship Tests
    
    func testCreateRelationship() async throws {
        // Create nodes
        let user = TestUser(name: "Author", age: 30)
        let post = TestPost(title: "My Post", content: "Hello, World!")
        
        let savedUser = try await context.save(user)
        let savedPost = try await context.save(post)
        
        // Create relationship
        try await context.createRelationship(
            from: savedUser,
            to: savedPost,
            edge: AuthoredBy()
        )
        
        // Verify relationship exists
        let result = try await context.raw("""
            MATCH (u:TestUser {id: $userId})-[r:AuthoredBy]->(p:TestPost {id: $postId})
            RETURN count(r)
            """, bindings: [
                "userId": savedUser.id,
                "postId": savedPost.id
            ])
        
        let count = try result.mapFirst(to: Int64.self, at: 0) ?? 0
        XCTAssertEqual(count, 1)
    }
    
    // MARK: - Transaction Tests
    
    func testTransaction() async throws {
        try await context.transaction { ctx in
            let user1 = TestUser(name: "Transaction1", age: 25)
            let user2 = TestUser(name: "Transaction2", age: 26)
            
            _ = try await ctx.save(user1)
            _ = try await ctx.save(user2)
        }
        
        let users = try await context.fetch(TestUser.self)
        XCTAssertEqual(users.count, 2)
    }
}