import Testing
import Foundation
@testable import KuzuSwiftExtension
@testable import KuzuSwiftMacros
import Kuzu

@Suite("Query DSL Node Return Tests")
struct QueryDSLNodeTests {
    
    // Test models
    @GraphNode
    struct TestUser: Codable {
        @ID var id: UUID = UUID()
        var name: String
        var age: Int
        var email: String?
        @Timestamp var createdAt: Date = Date()
    }
    
    @GraphEdge(from: TestUser.self, to: TestUser.self)
    struct TestFollows: Codable {
        @Timestamp var since: Date = Date()
    }
    
    @Test("Return node object and decode to model")
    func testReturnNodeObject() async throws {
        let config = GraphConfiguration(
            databasePath: ":memory:",
            options: GraphConfiguration.Options(enableLogging: true)
        )
        
        let context = try await GraphContext(configuration: config)
        
        // Create schema
        try await context.createSchema(for: [TestUser.self, TestFollows.self])
        
        // Insert test data
        let users = [
            TestUser(name: "Alice", age: 30, email: "alice@example.com"),
            TestUser(name: "Bob", age: 25, email: "bob@example.com"),
            TestUser(name: "Charlie", age: 35, email: nil)
        ]
        
        for user in users {
            try await context.save(user)
        }
        
        // Test 1: Return node using DSL (RETURN u)
        let allUsers = try await context.queryArray(TestUser.self) {
            Match.node(TestUser.self, alias: "u")
            Return.node("u")
        }
        
        #expect(allUsers.count == 3)
        #expect(allUsers.contains(where: { $0.name == "Alice" }))
        #expect(allUsers.contains(where: { $0.name == "Bob" }))
        #expect(allUsers.contains(where: { $0.name == "Charlie" }))
        
        // Test 2: Return single node with filter
        let alice = try await context.query(TestUser.self) {
            Match.node(TestUser.self, alias: "u")
            Where(path(\TestUser.name, on: "u") == "Alice")
            Return.node("u")
        }
        
        #expect(alice.name == "Alice")
        #expect(alice.age == 30)
        #expect(alice.email == "alice@example.com")
        
        // Test 3: Return node with ordering
        let orderedUsers = try await context.queryArray(TestUser.self) {
            Match.node(TestUser.self, alias: "u")
            Return.node("u")
                .orderBy(.ascending("u.age"))
        }
        
        #expect(orderedUsers[0].name == "Bob")  // age 25
        #expect(orderedUsers[1].name == "Alice")  // age 30
        #expect(orderedUsers[2].name == "Charlie")  // age 35
        
        // Test 4: Return with limit
        let limitedUsers = try await context.queryArray(TestUser.self) {
            Match.node(TestUser.self, alias: "u")
            Return.node("u")
                .orderBy(.ascending("u.name"))
                .limit(2)
        }
        
        #expect(limitedUsers.count == 2)
        #expect(limitedUsers[0].name == "Alice")
        #expect(limitedUsers[1].name == "Bob")
    }
    
    @Test("Return node properties individually")
    func testReturnNodeProperties() async throws {
        let config = GraphConfiguration(
            databasePath: ":memory:",
            options: GraphConfiguration.Options(enableLogging: true)
        )
        
        let context = try await GraphContext(configuration: config)
        
        // Create schema
        try await context.createSchema(for: [TestUser.self])
        
        // Insert test data
        let user = TestUser(name: "TestUser", age: 28, email: "test@example.com")
        try await context.save(user)
        
        // Test returning individual properties using raw query
        let result = try await context.raw(
            "MATCH (u:TestUser) WHERE u.name = $name RETURN u.name AS name, u.age AS age, u.email AS userEmail",
            bindings: ["name": "TestUser"]
        )
        
        guard let row = try result.mapFirst() else {
            throw GraphError.invalidOperation(message: "No rows returned")
        }
        
        #expect(row["name"] as? String == "TestUser")
        #expect(row["age"] as? Int64 == 28)  // Kuzu returns Int64
        #expect(row["userEmail"] as? String == "test@example.com")
    }
    
    @Test("Mixed return with node and scalar values")
    func testMixedReturn() async throws {
        let config = GraphConfiguration(
            databasePath: ":memory:",
            options: GraphConfiguration.Options(enableLogging: true)
        )
        
        let context = try await GraphContext(configuration: config)
        
        // Create schema
        try await context.createSchema(for: [TestUser.self, TestFollows.self])
        
        // Insert test data
        let alice = TestUser(name: "Alice", age: 30, email: "alice@example.com")
        let bob = TestUser(name: "Bob", age: 25, email: "bob@example.com")
        
        try await context.save(alice)
        try await context.save(bob)
        
        // Create relationship
        let follows = TestFollows()
        try await context.createRelationship(from: alice, to: bob, edge: follows)
        
        // Test mixed return: node + count using raw query
        let result = try await context.raw(
            """
            MATCH (follower:TestUser)-[f:TestFollows]->(followed:TestUser)
            WHERE follower.name = $name
            RETURN followed, COUNT(*) AS relationshipCount
            """,
            bindings: ["name": "Alice"]
        )
        
        guard let row = try result.mapFirst() else {
            throw GraphError.invalidOperation(message: "No rows returned")
        }
        
        // The node should be in the "followed" key as properties
        #expect(row["followed"] != nil)
        if let followedProps = row["followed"] as? [String: Any] {
            #expect(followedProps["name"] as? String == "Bob")
            #expect(followedProps["age"] as? Int64 == 25)  // Kuzu returns Int64
        }
        
        #expect(row["relationshipCount"] as? Int64 == 1)
    }
    
    @Test("Raw query with node return")
    func testRawQueryNodeReturn() async throws {
        let config = GraphConfiguration(
            databasePath: ":memory:",
            options: GraphConfiguration.Options(enableLogging: true)
        )
        
        let context = try await GraphContext(configuration: config)
        
        // Create schema
        try await context.createSchema(for: [TestUser.self])
        
        // Insert test data
        let user = TestUser(name: "RawQueryUser", age: 40, email: "raw@example.com")
        try await context.save(user)
        
        // Test raw query that returns a node
        let result = try await context.raw(
            "MATCH (u:TestUser) WHERE u.name = $name RETURN u",
            bindings: ["name": "RawQueryUser"]
        )
        
        // Use the improved map(to:) method
        let users = try result.map(to: TestUser.self)
        
        #expect(users.count == 1)
        #expect(users[0].name == "RawQueryUser")
        #expect(users[0].age == 40)
        #expect(users[0].email == "raw@example.com")
    }
    
    @Test("Return all nodes without filter")
    func testReturnAllNodes() async throws {
        let config = GraphConfiguration(
            databasePath: ":memory:",
            options: GraphConfiguration.Options(enableLogging: true)
        )
        
        let context = try await GraphContext(configuration: config)
        
        // Create schema
        try await context.createSchema(for: [TestUser.self])
        
        // Insert multiple users
        let userCount = 5
        for i in 1...userCount {
            let user = TestUser(name: "User\(i)", age: 20 + i, email: "user\(i)@example.com")
            try await context.save(user)
        }
        
        // Test returning all nodes
        let allUsers = try await context.queryArray(TestUser.self) {
            Match.node(TestUser.self, alias: "u")
            Return.all()
        }
        
        #expect(allUsers.count == userCount)
        
        // Verify all users are present
        for i in 1...userCount {
            #expect(allUsers.contains(where: { $0.name == "User\(i)" }))
        }
    }
}