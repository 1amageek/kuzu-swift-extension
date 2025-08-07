import XCTest
import KuzuSwiftExtension
import KuzuSwiftMacros
import Kuzu
@testable import KuzuSwiftExtension

// MARK: - Test Models

@GraphNode
struct User: Codable, Sendable {
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
struct Post: Codable, Sendable {
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

@GraphEdge(from: User.self, to: Post.self)
struct Authored: Codable, Sendable {
    var authoredAt: Date = Date()
    var metadata: String?
    
    init(authoredAt: Date = Date(), metadata: String? = nil) {
        self.authoredAt = authoredAt
        self.metadata = metadata
    }
}

@GraphEdge(from: User.self, to: User.self)
struct Follows: Codable, Sendable {
    var followedAt: Date = Date()
    
    init(followedAt: Date = Date()) {
        self.followedAt = followedAt
    }
}

// MARK: - Type-Safe API Tests

final class TypeSafeAPITests: XCTestCase {
    var context: GraphContext!
    
    override func setUp() async throws {
        try await super.setUp()
        let config = GraphConfiguration(databasePath: ":memory:")
        context = try await GraphContext(configuration: config)
        
        // Create schema for all models
        try await context.createSchema(for: [
            User.self,
            Post.self,
            Authored.self,
            Follows.self
        ])
    }
    
    override func tearDown() async throws {
        await context.close()
        context = nil
        try await super.tearDown()
    }
    
    // MARK: - KeyPath Predicate Tests
    
    func testPropertyPathWithKeyPath() async throws {
        // Create test users
        let alice = User(email: "alice@example.com", name: "Alice", age: 30)
        let bob = User(email: "bob@example.com", name: "Bob", age: 25)
        
        // Insert users
        try await insertUser(alice)
        try await insertUser(bob)
        
        // Test KeyPath-based predicate
        let predicate = prop(\User.name, on: "u") == "Alice"
        let cypher = try predicate.toCypher()
        
        XCTAssertEqual(cypher.query, "u.name = $\(cypher.parameters.keys.first!)")
        XCTAssertEqual(cypher.parameters.values.first as? String, "Alice")
        
        // Execute query with predicate
        let result = try await context.raw(
            "MATCH (u:User) WHERE \(cypher.query) RETURN u",
            bindings: cypher.parameters
        )
        
        XCTAssertTrue(result.hasNext())
        let row = try result.getNext()
        XCTAssertNotNil(row)
    }
    
    func testPropertyPathComparisons() async throws {
        let user = User(email: "test@example.com", name: "Test", age: 30)
        try await insertUser(user)
        
        // Test various comparison operators
        let equalPredicate = prop(\User.age, on: "u") == 30
        let notEqualPredicate = prop(\User.age, on: "u") != 25
        let greaterPredicate = prop(\User.age, on: "u") > 25
        let lessPredicate = prop(\User.age, on: "u") < 35
        
        for predicate in [equalPredicate, notEqualPredicate, greaterPredicate, lessPredicate] {
            let cypher = try predicate.toCypher()
            let result = try await context.raw(
                "MATCH (u:User) WHERE \(cypher.query) RETURN COUNT(u) as count",
                bindings: cypher.parameters
            )
            
            let count = try result.mapFirst(to: Int64.self, at: 0) ?? 0
            XCTAssertEqual(count, 1)
        }
    }
    
    // MARK: - Relationship Operation Tests
    
    func testCreateAndQueryRelationships() async throws {
        // Create user and post
        let user = User(email: "author@example.com", name: "Author", age: 35)
        let post = Post(title: "Test Post", content: "Content", authorId: user.id)
        
        try await insertUser(user)
        try await insertPost(post)
        
        // Create relationship
        let authored = Authored(metadata: "First post")
        try await context.connect(authored, from: user, to: post)
        
        // Query related posts
        let relatedPosts: [Post] = try await context.related(
            to: user,
            via: Authored.self,
            direction: .outgoing
        )
        
        XCTAssertEqual(relatedPosts.count, 1)
        XCTAssertEqual(relatedPosts.first?.title, "Test Post")
        
        // Query with edges
        let pairs = try await context.relatedWithEdges(
            to: user,
            via: Authored.self,
            direction: .outgoing
        ) as [(node: Post, edge: Authored)]
        
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs.first?.node.title, "Test Post")
        XCTAssertEqual(pairs.first?.edge.metadata, "First post")
    }
    
    func testDisconnectRelationships() async throws {
        // Setup
        let user = User(email: "user@example.com", name: "User", age: 30)
        let post = Post(title: "Post", content: "Content", authorId: user.id)
        
        try await insertUser(user)
        try await insertPost(post)
        try await context.connect(Authored(), from: user, to: post)
        
        // Verify connection exists
        let beforeDisconnect: [Post] = try await context.related(
            to: user,
            via: Authored.self
        )
        XCTAssertEqual(beforeDisconnect.count, 1)
        
        // Disconnect
        try await context.disconnect(from: user, to: post, via: Authored.self)
        
        // Verify disconnection
        let afterDisconnect: [Post] = try await context.related(
            to: user,
            via: Authored.self
        )
        XCTAssertEqual(afterDisconnect.count, 0)
    }
    
    // MARK: - Result Mapping Tests
    
    func testEnhancedResultMapping() async throws {
        // Create multiple users
        let users = [
            User(email: "user1@test.com", name: "User1", age: 20),
            User(email: "user2@test.com", name: "User2", age: 30),
            User(email: "user3@test.com", name: "User3", age: 40)
        ]
        
        for user in users {
            try await insertUser(user)
        }
        
        // Test decode array
        let result = try await context.raw("MATCH (u:User) RETURN u ORDER BY u.age")
        let decodedUsers = try result.decode(User.self, column: "u")
        
        XCTAssertEqual(decodedUsers.count, 3)
        XCTAssertEqual(decodedUsers[0].age, 20)
        XCTAssertEqual(decodedUsers[2].age, 40)
        
        // Test first
        let singleResult = try await context.raw("MATCH (u:User) WHERE u.age = 30 RETURN u")
        let firstUser = try singleResult.first(User.self, column: "u")
        
        XCTAssertNotNil(firstUser)
        XCTAssertEqual(firstUser?.name, "User2")
    }
    
    func testResultTypeMappings() async throws {
        let user = User(email: "mapper@test.com", name: "Mapper", age: 25)
        try await insertUser(user)
        
        // Test different type mappings
        let result = try await context.raw(
            "MATCH (u:User) WHERE u.email = $email RETURN u.name as name, u.age as age, u.email as email",
            bindings: ["email": user.email]
        )
        
        // Map strings
        let namesResult = try await context.raw(
            "MATCH (u:User) RETURN u.name",
            bindings: [:]
        )
        let names = try namesResult.mapStrings(at: 0)
        XCTAssertEqual(names.count, 1)
        XCTAssertEqual(names.first, "Mapper")
        
        // Map integers
        let agesResult = try await context.raw(
            "MATCH (u:User) RETURN u.age",
            bindings: [:]
        )
        let ages = try agesResult.mapInts(at: 0)
        XCTAssertEqual(ages.count, 1)
        XCTAssertEqual(ages.first, 25)
    }
    
    // MARK: - Batch Operation Tests
    
    func testBatchCreate() async throws {
        let users = [
            User(email: "batch1@test.com", name: "Batch1", age: 25),
            User(email: "batch2@test.com", name: "Batch2", age: 30),
            User(email: "batch3@test.com", name: "Batch3", age: 35)
        ]
        
        try await context.createMany(users)
        
        // Verify creation
        let result = try await context.raw("MATCH (u:User) RETURN COUNT(u) as count")
        let count = try result.mapFirst(to: Int64.self, at: 0) ?? 0
        XCTAssertEqual(count, 3)
    }
    
    func testBatchUpdate() async throws {
        // Create users
        let users = [
            User(email: "update1@test.com", name: "Update1", age: 20),
            User(email: "update2@test.com", name: "Update2", age: 30),
            User(email: "update3@test.com", name: "Update3", age: 40)
        ]
        
        for user in users {
            try await insertUser(user)
        }
        
        // Update users with age > 25
        let predicate = property("n", "age") > 25
        try await context.updateMany(
            User.self,
            matching: predicate,
            set: ["status": "senior"]
        )
        
        // Verify update
        let result = try await context.raw("MATCH (u:User) WHERE u.status = 'senior' RETURN COUNT(u) as count")
        let count = try result.mapFirst(to: Int64.self, at: 0) ?? 0
        XCTAssertEqual(count, 2)
    }
    
    func testBatchDelete() async throws {
        // Create users
        let users = [
            User(email: "delete1@test.com", name: "Delete1", age: 20),
            User(email: "delete2@test.com", name: "Delete2", age: 25),
            User(email: "delete3@test.com", name: "Delete3", age: 30)
        ]
        
        for user in users {
            try await insertUser(user)
        }
        
        // Delete users with age < 28
        let predicate = property("n", "age") < 28
        try await context.deleteMany(User.self, where: predicate)
        
        // Verify deletion
        let result = try await context.raw("MATCH (u:User) RETURN COUNT(u) as count")
        let count = try result.mapFirst(to: Int64.self, at: 0) ?? 0
        XCTAssertEqual(count, 1)
        
        // Verify remaining user
        let remainingResult = try await context.raw("MATCH (u:User) RETURN u.name as name")
        let name = try remainingResult.mapFirst(to: String.self, at: 0)
        XCTAssertEqual(name, "Delete3")
    }
    
    // MARK: - Path Query Tests
    
    func testShortestPath() async throws {
        // Create users
        let user1 = User(email: "path1@test.com", name: "Path1", age: 25)
        let user2 = User(email: "path2@test.com", name: "Path2", age: 30)
        let user3 = User(email: "path3@test.com", name: "Path3", age: 35)
        
        try await insertUser(user1)
        try await insertUser(user2)
        try await insertUser(user3)
        
        // Create follow relationships: user1 -> user2 -> user3
        try await context.connect(Follows(), from: user1, to: user2)
        try await context.connect(Follows(), from: user2, to: user3)
        
        // Test shortest path
        let path = try await context.shortestPath(from: user1, to: user3, maxHops: 3)
        XCTAssertNotNil(path)
        XCTAssertFalse(path!.isEmpty)
    }
    
    func testConnectionCheck() async throws {
        // Create users
        let user1 = User(email: "conn1@test.com", name: "Conn1", age: 25)
        let user2 = User(email: "conn2@test.com", name: "Conn2", age: 30)
        let user3 = User(email: "conn3@test.com", name: "Conn3", age: 35)
        
        try await insertUser(user1)
        try await insertUser(user2)
        try await insertUser(user3)
        
        // Create connections
        try await context.connect(Follows(), from: user1, to: user2)
        try await context.connect(Follows(), from: user2, to: user3)
        
        // Test direct connection
        let directConnection = try await context.areConnected(
            user1,
            user2,
            via: Follows.self,
            maxHops: 1
        )
        XCTAssertTrue(directConnection)
        
        // Test indirect connection
        let indirectConnection = try await context.areConnected(
            user1,
            user3,
            via: Follows.self,
            maxHops: 2
        )
        XCTAssertTrue(indirectConnection)
        
        // Test no connection with limited hops
        let noConnection = try await context.areConnected(
            user1,
            user3,
            via: Follows.self,
            maxHops: 1
        )
        XCTAssertFalse(noConnection)
    }
    
    // MARK: - Helper Methods
    
    private func insertUser(_ user: User) async throws {
        let cypher = """
            CREATE (u:User {
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
    
    private func insertPost(_ post: Post) async throws {
        let cypher = """
            CREATE (p:Post {
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
}