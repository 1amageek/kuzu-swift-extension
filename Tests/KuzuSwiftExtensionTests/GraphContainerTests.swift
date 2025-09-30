import Testing
import Kuzu
@testable import KuzuSwiftExtension

@Suite("Graph Container Tests")
struct GraphContainerTests {

    // MARK: - Basic Operations

    @Test("Basic container operations")
    func basicOperations() async throws {
        let config = GraphConfiguration(
            databasePath: ":memory:",
            options: GraphConfiguration.Options(
                maxConnections: 3,
                minConnections: 1
            )
        )

        let container = try await GraphContainer(configuration: config)

        // Test withConnection - verify actual result value
        let result = try await container.withConnection { connection in
            try connection.query("RETURN 1 AS value")
        }
        #expect(result.hasNext())

        if let flatTuple = try result.getNext(),
           let value = try flatTuple.getValue(0) as? Int64 {
            #expect(value == 1)
        } else {
            Issue.record("Failed to get result value")
        }

        // Test multiple concurrent connections
        async let result1 = container.withConnection { connection in
            try connection.query("RETURN 1 AS value")
        }
        async let result2 = container.withConnection { connection in
            try connection.query("RETURN 2 AS value")
        }
        async let result3 = container.withConnection { connection in
            try connection.query("RETURN 3 AS value")
        }

        let results = try await (result1, result2, result3)
        #expect(results.0.hasNext())
        #expect(results.1.hasNext())
        #expect(results.2.hasNext())

        await container.close()
    }

    // MARK: - Transaction Tests

    @Test("Transaction commits successfully")
    func transactionCommit() async throws {
        let config = GraphConfiguration(databasePath: ":memory:")
        let container = try await GraphContainer(configuration: config)

        // Create a test table
        _ = try await container.withConnection { connection in
            try connection.query("CREATE NODE TABLE TestNode (id INT64, name STRING, PRIMARY KEY(id))")
        }

        // Execute transaction with multiple operations
        try await container.withTransaction { connection in
            _ = try connection.query("CREATE (:TestNode {id: 1, name: 'Alice'})")
            _ = try connection.query("CREATE (:TestNode {id: 2, name: 'Bob'})")
            _ = try connection.query("CREATE (:TestNode {id: 3, name: 'Charlie'})")
        }

        // Verify all nodes were created
        let result = try await container.withConnection { connection in
            try connection.query("MATCH (n:TestNode) RETURN count(n) AS count")
        }
        #expect(result.hasNext())

        if let flatTuple = try result.getNext(),
           let count = try flatTuple.getValue(0) as? Int64 {
            #expect(count == 3, "Expected 3 nodes after successful transaction")
        } else {
            Issue.record("Failed to get count")
        }

        await container.close()
    }

    @Test("Transaction rolls back on primary key violation")
    func transactionRollbackOnPrimaryKeyViolation() async throws {
        let config = GraphConfiguration(databasePath: ":memory:")
        let container = try await GraphContainer(configuration: config)

        // Create a test table with PRIMARY KEY constraint
        _ = try await container.withConnection { connection in
            try connection.query("CREATE NODE TABLE TestNode (id INT64, name STRING, PRIMARY KEY(id))")
        }

        // Insert initial node
        _ = try await container.withConnection { connection in
            try connection.query("CREATE (:TestNode {id: 1, name: 'Alice'})")
        }

        // Attempt transaction that will violate PRIMARY KEY constraint
        await #expect(throws: GraphError.self) {
            try await container.withTransaction { connection in
                _ = try connection.query("CREATE (:TestNode {id: 2, name: 'Bob'})")
                _ = try connection.query("CREATE (:TestNode {id: 1, name: 'Duplicate'})") // Duplicate PRIMARY KEY
            }
        }

        // Verify rollback: should still have only 1 node (Alice)
        let countResult = try await container.withConnection { connection in
            try connection.query("MATCH (n:TestNode) RETURN count(n) AS count")
        }
        #expect(countResult.hasNext())

        if let flatTuple = try countResult.getNext(),
           let count = try flatTuple.getValue(0) as? Int64 {
            #expect(count == 1, "Expected only 1 node after rollback (Bob should not exist)")
        } else {
            Issue.record("Failed to get count after rollback")
        }

        // Verify only Alice exists
        let nameResult = try await container.withConnection { connection in
            try connection.query("MATCH (n:TestNode) RETURN n.name AS name")
        }
        #expect(nameResult.hasNext())

        if let flatTuple = try nameResult.getNext(),
           let name = try flatTuple.getValue(0) as? String {
            #expect(name == "Alice", "Only Alice should exist after rollback")
        }

        await container.close()
    }

    @Test("Transaction rolls back on query syntax error")
    func transactionRollbackOnSyntaxError() async throws {
        let config = GraphConfiguration(databasePath: ":memory:")
        let container = try await GraphContainer(configuration: config)

        // Create a test table
        _ = try await container.withConnection { connection in
            try connection.query("CREATE NODE TABLE TestNode (id INT64, name STRING, PRIMARY KEY(id))")
        }

        // Attempt transaction with syntax error
        await #expect(throws: GraphError.self) {
            try await container.withTransaction { connection in
                _ = try connection.query("CREATE (:TestNode {id: 1, name: 'Alice'})")
                _ = try connection.query("INVALID CYPHER SYNTAX HERE")
            }
        }

        // Verify rollback: no nodes should exist
        let countResult = try await container.withConnection { connection in
            try connection.query("MATCH (n:TestNode) RETURN count(n) AS count")
        }
        #expect(countResult.hasNext())

        if let flatTuple = try countResult.getNext(),
           let count = try flatTuple.getValue(0) as? Int64 {
            #expect(count == 0, "Expected no nodes after rollback")
        } else {
            Issue.record("Failed to get count after rollback")
        }

        await container.close()
    }

    @Test("Transaction atomicity with multiple operations")
    func transactionAtomicity() async throws {
        let config = GraphConfiguration(databasePath: ":memory:")
        let container = try await GraphContainer(configuration: config)

        // Create test tables
        _ = try await container.withConnection { connection in
            try connection.query("CREATE NODE TABLE User (id INT64, name STRING, PRIMARY KEY(id))")
        }
        _ = try await container.withConnection { connection in
            try connection.query("CREATE NODE TABLE Post (id INT64, title STRING, PRIMARY KEY(id))")
        }

        // Execute transaction creating nodes in both tables
        try await container.withTransaction { connection in
            _ = try connection.query("CREATE (:User {id: 1, name: 'Alice'})")
            _ = try connection.query("CREATE (:Post {id: 1, title: 'First Post'})")
            _ = try connection.query("CREATE (:User {id: 2, name: 'Bob'})")
            _ = try connection.query("CREATE (:Post {id: 2, title: 'Second Post'})")
        }

        // Verify both tables have data
        let userCount = try await container.withConnection { connection in
            try connection.query("MATCH (u:User) RETURN count(u) AS count")
        }
        let postCount = try await container.withConnection { connection in
            try connection.query("MATCH (p:Post) RETURN count(p) AS count")
        }

        if let userTuple = try userCount.getNext(),
           let userCountValue = try userTuple.getValue(0) as? Int64 {
            #expect(userCountValue == 2, "Expected 2 users")
        }

        if let postTuple = try postCount.getNext(),
           let postCountValue = try postTuple.getValue(0) as? Int64 {
            #expect(postCountValue == 2, "Expected 2 posts")
        }

        // Now attempt transaction that fails halfway
        await #expect(throws: GraphError.self) {
            try await container.withTransaction { connection in
                _ = try connection.query("CREATE (:User {id: 3, name: 'Charlie'})")
                _ = try connection.query("CREATE (:Post {id: 1, title: 'Duplicate'})")  // Duplicate PRIMARY KEY
            }
        }

        // Verify atomicity: Charlie should NOT exist (entire transaction rolled back)
        let finalUserCount = try await container.withConnection { connection in
            try connection.query("MATCH (u:User) RETURN count(u) AS count")
        }

        if let tuple = try finalUserCount.getNext(),
           let count = try tuple.getValue(0) as? Int64 {
            #expect(count == 2, "User count should still be 2 (Charlie should not exist)")
        }

        await container.close()
    }

    @Test("Nested transaction operations")
    func nestedTransactionOperations() async throws {
        let config = GraphConfiguration(databasePath: ":memory:")
        let container = try await GraphContainer(configuration: config)

        // Create a test table
        _ = try await container.withConnection { connection in
            try connection.query("CREATE NODE TABLE TestNode (id INT64, value INT64, PRIMARY KEY(id))")
        }

        // Execute complex transaction with conditional logic
        try await container.withTransaction { connection in
            // Insert first node
            _ = try connection.query("CREATE (:TestNode {id: 1, value: 10})")

            // Query to check value
            let result = try connection.query("MATCH (n:TestNode {id: 1}) RETURN n.value AS value")
            if result.hasNext(),
               let tuple = try result.getNext(),
               let value = try tuple.getValue(0) as? Int64 {
                // Based on the value, insert another node
                if value == 10 {
                    _ = try connection.query("CREATE (:TestNode {id: 2, value: 20})")
                }
            }

            // Insert third node
            _ = try connection.query("CREATE (:TestNode {id: 3, value: 30})")
        }

        // Verify all operations committed
        let countResult = try await container.withConnection { connection in
            try connection.query("MATCH (n:TestNode) RETURN count(n) AS count")
        }

        if let tuple = try countResult.getNext(),
           let count = try tuple.getValue(0) as? Int64 {
            #expect(count == 3, "All nodes should be committed")
        }

        await container.close()
    }

    // MARK: - Error Handling Tests

    @Test("Connection error handling and recovery")
    func connectionErrorHandling() async throws {
        let config = GraphConfiguration(databasePath: ":memory:")
        let container = try await GraphContainer(configuration: config)

        // Test that errors are properly propagated
        await #expect(throws: Error.self, "Invalid query should fail") {
            _ = try await container.withConnection { connection in
                try connection.query("INVALID CYPHER QUERY")
            }
        }

        // Verify container is still functional after error
        let result = try await container.withConnection { connection in
            try connection.query("RETURN 1 AS value")
        }
        #expect(result.hasNext())

        if let flatTuple = try result.getNext(),
           let value = try flatTuple.getValue(0) as? Int64 {
            #expect(value == 1, "Container should work after error")
        }

        await container.close()
    }

    @Test("Transaction error preserves database state")
    func transactionErrorPreservesState() async throws {
        let config = GraphConfiguration(databasePath: ":memory:")
        let container = try await GraphContainer(configuration: config)

        // Create test table and insert initial data
        _ = try await container.withConnection { connection in
            try connection.query("CREATE NODE TABLE TestNode (id INT64, name STRING, PRIMARY KEY(id))")
        }
        _ = try await container.withConnection { connection in
            try connection.query("CREATE (:TestNode {id: 1, name: 'Initial'})")
        }

        // Record initial state
        let initialResult = try await container.withConnection { connection in
            try connection.query("MATCH (n:TestNode) RETURN n.id AS id, n.name AS name")
        }

        var initialNodes: [(Int64, String)] = []
        while initialResult.hasNext() {
            if let tuple = try initialResult.getNext(),
               let id = try tuple.getValue(0) as? Int64,
               let name = try tuple.getValue(1) as? String {
                initialNodes.append((id, name))
            }
        }

        // Attempt failed transaction
        await #expect(throws: GraphError.self) {
            try await container.withTransaction { connection in
                _ = try connection.query("CREATE (:TestNode {id: 2, name: 'New'})")
                _ = try connection.query("CREATE (:TestNode {id: 1, name: 'Conflict'})") // PRIMARY KEY violation
            }
        }

        // Verify state is preserved (only Initial node exists)
        let finalResult = try await container.withConnection { connection in
            try connection.query("MATCH (n:TestNode) RETURN n.id AS id, n.name AS name ORDER BY n.id")
        }

        var finalNodes: [(Int64, String)] = []
        while finalResult.hasNext() {
            if let tuple = try finalResult.getNext(),
               let id = try tuple.getValue(0) as? Int64,
               let name = try tuple.getValue(1) as? String {
                finalNodes.append((id, name))
            }
        }

        #expect(finalNodes.count == initialNodes.count, "Node count should be preserved")

        // Verify each node individually
        for (index, initialNode) in initialNodes.enumerated() {
            #expect(finalNodes[index].0 == initialNode.0, "Node ID should be preserved")
            #expect(finalNodes[index].1 == initialNode.1, "Node name should be preserved")
        }

        await container.close()
    }

    // MARK: - Container Lifecycle Tests

    @Test("Container closes cleanly")
    func containerCloses() async throws {
        let config = GraphConfiguration(databasePath: ":memory:")
        let container = try await GraphContainer(configuration: config)

        // Perform some operations
        _ = try await container.withConnection { connection in
            try connection.query("RETURN 1 AS value")
        }

        // Close container
        await container.close()

        // After close, new operations should fail
        await #expect(throws: GraphError.self) {
            _ = try await container.withConnection { connection in
                try connection.query("RETURN 1")
            }
        }
    }

    @Test("Multiple containers with same database path")
    func multipleContainers() async throws {
        // Note: This test uses different database paths to avoid conflicts
        let config1 = GraphConfiguration(databasePath: ":memory:")
        let config2 = GraphConfiguration(databasePath: ":memory:")

        let container1 = try await GraphContainer(configuration: config1)
        let container2 = try await GraphContainer(configuration: config2)

        // Both containers should work independently
        let result1 = try await container1.withConnection { connection in
            try connection.query("RETURN 1 AS value")
        }
        let result2 = try await container2.withConnection { connection in
            try connection.query("RETURN 2 AS value")
        }

        #expect(result1.hasNext())
        #expect(result2.hasNext())

        await container1.close()
        await container2.close()
    }
}
