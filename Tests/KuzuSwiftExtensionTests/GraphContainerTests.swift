import Testing
import Kuzu
@testable import KuzuSwiftExtension

// Test models at top level
@GraphNode
fileprivate struct TestNode: Codable {
    @ID var id: Int
    var value: Int
}

@GraphNode
fileprivate struct TransactionTestNode: Codable {
    @ID var id: Int
    var name: String
}

@GraphNode
fileprivate struct User: Codable {
    @ID var id: Int
    var name: String
    var age: Int
}

@GraphNode
fileprivate struct Post: Codable {
    @ID var id: Int
    var title: String
}

@Suite("Graph Container Tests")
struct GraphContainerTests {

    // MARK: - Basic Operations

    @Test("Basic container operations")
    func basicOperations() throws {
        let container = try GraphContainer(for: TestNode.self, configuration: GraphConfiguration(databasePath: ":memory:"))
        let context = GraphContext(container)

        // Insert and query
        let node = TestNode(id: 1, value: 42)
        context.insert(node)
        try context.save()

        let result = try context.raw("MATCH (n:TestNode) RETURN n.value AS value")
        #expect(result.hasNext())

        if let flatTuple = try result.getNext(),
           let value = try flatTuple.getValue(0) as? Int64 {
            #expect(value == 42)
        } else {
            Issue.record("Failed to get result value")
        }
    }

    // MARK: - Transaction Tests

    @Test("Transaction commits successfully")
    func transactionCommit() throws {
        let container = try GraphContainer(for: TransactionTestNode.self, configuration: GraphConfiguration(databasePath: ":memory:"))
        let context = GraphContext(container)

        // Execute transaction with multiple operations
        try context.transaction {
            context.insert(TransactionTestNode(id: 1, name: "Alice"))
            context.insert(TransactionTestNode(id: 2, name: "Bob"))
            context.insert(TransactionTestNode(id: 3, name: "Charlie"))
        }

        // Verify all nodes were created
        let result = try context.raw("MATCH (n:TransactionTestNode) RETURN count(n) AS count")
        #expect(result.hasNext())

        if let flatTuple = try result.getNext(),
           let count = try flatTuple.getValue(0) as? Int64 {
            #expect(count == 3, "Expected 3 nodes after successful transaction")
        } else {
            Issue.record("Failed to get count")
        }
    }

    @Test("Transaction rolls back on error")
    func transactionRollback() throws {
        let container = try GraphContainer(for: TransactionTestNode.self, configuration: GraphConfiguration(databasePath: ":memory:"))
        let context = GraphContext(container)

        // Insert initial node
        context.insert(TransactionTestNode(id: 1, name: "Alice"))
        try context.save()

        // Attempt transaction that will fail
        #expect(throws: Error.self) {
            try context.transaction {
                context.insert(TransactionTestNode(id: 2, name: "Bob"))
                // Force an error by executing invalid query
                _ = try context.raw("INVALID CYPHER SYNTAX")
            }
        }

        // Verify rollback: should still have only 1 node (Alice)
        let countResult = try context.raw("MATCH (n:TransactionTestNode) RETURN count(n) AS count")
        #expect(countResult.hasNext())

        if let flatTuple = try countResult.getNext(),
           let count = try flatTuple.getValue(0) as? Int64 {
            #expect(count == 1, "Expected only 1 node after rollback")
        } else {
            Issue.record("Failed to get count after rollback")
        }
    }

    // MARK: - SwiftData-style API Tests

    @Test("Insert and save pattern")
    func insertAndSave() throws {
        let container = try GraphContainer(for: User.self, configuration: GraphConfiguration(databasePath: ":memory:"))
        let context = GraphContext(container)

        // SwiftData-style: insert then save
        let user1 = User(id: 1, name: "Alice", age: 30)
        let user2 = User(id: 2, name: "Bob", age: 25)

        context.insert(user1)
        context.insert(user2)
        try context.save()

        // Verify
        let result = try context.raw("MATCH (u:User) RETURN count(u) AS count")
        if let tuple = try result.getNext(),
           let count = try tuple.getValue(0) as? Int64 {
            #expect(count == 2)
        }
    }

    @Test("Delete and save pattern")
    func deleteAndSave() throws {
        let container = try GraphContainer(for: User.self, configuration: GraphConfiguration(databasePath: ":memory:"))
        let context = GraphContext(container)

        // Insert users
        let user1 = User(id: 1, name: "Alice", age: 30)
        let user2 = User(id: 2, name: "Bob", age: 25)
        context.insert(user1)
        context.insert(user2)
        try context.save()

        // Delete one user
        context.delete(user1)
        try context.save()

        // Verify only Bob remains
        let result = try context.raw("MATCH (u:User) RETURN count(u) AS count")
        if let tuple = try result.getNext(),
           let count = try tuple.getValue(0) as? Int64 {
            #expect(count == 1)
        }
    }

    @Test("Rollback pattern")
    func rollbackPattern() throws {
        let container = try GraphContainer(for: User.self, configuration: GraphConfiguration(databasePath: ":memory:"))
        let context = GraphContext(container)

        // Insert and save
        context.insert(User(id: 1, name: "Alice", age: 30))
        try context.save()

        // Insert but rollback
        context.insert(User(id: 2, name: "Bob", age: 25))
        context.rollback()

        // Verify Bob was not saved
        let result = try context.raw("MATCH (u:User) RETURN count(u) AS count")
        if let tuple = try result.getNext(),
           let count = try tuple.getValue(0) as? Int64 {
            #expect(count == 1)
        }
    }

    // MARK: - Multi-model Tests

    @Test("Multiple model types")
    func multipleModels() throws {
        let container = try GraphContainer(for: User.self, Post.self, configuration: GraphConfiguration(databasePath: ":memory:"))
        let context = GraphContext(container)

        // Insert different model types
        context.insert(User(id: 1, name: "Alice", age: 30))
        context.insert(Post(id: 1, title: "First Post"))
        try context.save()

        // Verify both types exist
        let userResult = try context.raw("MATCH (u:User) RETURN count(u) AS count")
        if let tuple = try userResult.getNext(),
           let count = try tuple.getValue(0) as? Int64 {
            #expect(count == 1)
        }

        let postResult = try context.raw("MATCH (p:Post) RETURN count(p) AS count")
        if let tuple = try postResult.getNext(),
           let count = try tuple.getValue(0) as? Int64 {
            #expect(count == 1)
        }
    }

    // MARK: - MainContext Tests

    @Test("MainContext accessibility")
    @MainActor
    func mainContext() throws {
        let container = try GraphContainer(for: User.self, configuration: GraphConfiguration(databasePath: ":memory:"))

        // Access mainContext (should be @MainActor bound)
        let context = container.mainContext

        context.insert(User(id: 1, name: "Alice", age: 30))
        try context.save()

        let result = try context.raw("MATCH (u:User) RETURN count(u) AS count")
        if let tuple = try result.getNext(),
           let count = try tuple.getValue(0) as? Int64 {
            #expect(count == 1)
        }
    }
}
