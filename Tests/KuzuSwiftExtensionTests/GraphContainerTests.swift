import Testing
import Kuzu
@testable import KuzuSwiftExtension

@Suite("Graph Container Tests")
struct GraphContainerTests {
    
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
        // Cleanup will be at the end
        
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
    
    @Test("Container transactions (internal API)")
    func transactions() async throws {
        // Note: Testing internal transaction API directly for low-level functionality
        // Public users should use GraphContext.withTransaction instead
        let config = GraphConfiguration(databasePath: ":memory:")
        let container = try await GraphContainer(configuration: config)
        // Cleanup will be at the end
        
        // Create a test table
        _ = try await container.withConnection { connection in
            try connection.query("CREATE NODE TABLE TestNode (id INT64, name STRING, PRIMARY KEY(id))")
        }
        
        // Test successful transaction
        try await container.withTransaction { connection in
            _ = try connection.query("CREATE (:TestNode {id: 1, name: 'test'})")
        }
        
        // Verify the node was created
        let result = try await container.withConnection { connection in
            try connection.query("MATCH (n:TestNode) RETURN count(n) AS count")
        }
        #expect(result.hasNext())
        
        if let flatTuple = try result.getNext(),
           let count = try flatTuple.getValue(0) as? Int64 {
            #expect(count == 1, "Expected 1 node after successful transaction")
        } else {
            Issue.record("Failed to get count")
        }
        
        // Test failed transaction (should rollback)
        await #expect(throws: GraphError.self) {
            try await container.withTransaction { connection in
                _ = try connection.query("CREATE (:TestNode {id: 2, name: 'test2'})")
                // Force an error
                throw GraphError.transactionFailed(reason: "Test error")
            }
        }
        
        // Verify rollback worked (should still have only 1 node)
        let countResult = try await container.withConnection { connection in
            try connection.query("MATCH (n:TestNode) RETURN count(n) AS count")
        }
        #expect(countResult.hasNext())
        
        if let flatTuple = try countResult.getNext(),
           let count = try flatTuple.getValue(0) as? Int64 {
            #expect(count == 1, "Expected still 1 node after rollback")
        } else {
            Issue.record("Failed to get count after rollback")
        }
        
        await container.close()
    }
    
    @Test("Connection error handling")
    func connectionErrors() async throws {
        let config = GraphConfiguration(databasePath: ":memory:")
        let container = try await GraphContainer(configuration: config)
        // Cleanup will be at the end
        
        // Test that errors are properly propagated and connections are cleaned up
        await #expect(throws: Error.self, "Invalid query should fail") {
            _ = try await container.withConnection { connection in
                // This should fail
                try connection.query("INVALID CYPHER QUERY")
            }
        }
        
        // Verify we can still use the container after an error
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
    
    @Test("Transaction error handling")
    func transactionErrors() async throws {
        let config = GraphConfiguration(databasePath: ":memory:")
        let container = try await GraphContainer(configuration: config)
        // Cleanup will be at the end
        
        // Create a test table
        _ = try await container.withConnection { connection in
            try connection.query("CREATE NODE TABLE TestNode (id INT64, PRIMARY KEY(id))")
        }
        
        // Test transaction with query error
        await #expect(throws: GraphError.self) {
            try await container.withTransaction { connection in
                _ = try connection.query("CREATE (:TestNode {id: 1})")
                // This should fail
                _ = try connection.query("INVALID QUERY")
            }
        }
        
        // Verify the transaction was rolled back
        let result = try await container.withConnection { connection in
            try connection.query("MATCH (n:TestNode) RETURN count(n) AS count")
        }
        #expect(result.hasNext())
        
        if let flatTuple = try result.getNext(),
           let count = try flatTuple.getValue(0) as? Int64 {
            #expect(count == 0, "Transaction should have been rolled back")
        } else {
            Issue.record("Failed to verify rollback")
        }
        
        await container.close()
    }
}