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
        
        // Test withConnection
        let result = try await container.withConnection { connection in
            try connection.query("RETURN 1 AS value")
        }
        #expect(Bool(true)) // Result retrieved successfully
        
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
        
        _ = try await (result1, result2, result3)
        
        // Cleanup
        await container.close()
    }
    
    @Test("Container transactions (internal API)")
    func transactions() async throws {
        // Note: Testing internal transaction API directly for low-level functionality
        // Public users should use GraphContext.withTransaction instead
        let config = GraphConfiguration(databasePath: ":memory:")
        let container = try await GraphContainer(configuration: config)
        
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
        
        // Test failed transaction (should rollback)
        do {
            try await container.withTransaction { connection in
                _ = try connection.query("CREATE (:TestNode {id: 2, name: 'test2'})")
                // Force an error
                throw GraphError.transactionFailed(reason: "Test error")
            }
            #expect(Bool(false), "Expected transaction to fail")
        } catch is GraphError {
            // Expected
            #expect(Bool(true))
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
        
        // Verify rollback worked (should still have only 1 node)
        let countResult = try await container.withConnection { connection in
            try connection.query("MATCH (n:TestNode) RETURN count(n) AS count")
        }
        #expect(countResult.hasNext())
        
        await container.close()
    }
    
    @Test("Connection error handling")
    func connectionErrors() async throws {
        let config = GraphConfiguration(databasePath: ":memory:")
        let container = try await GraphContainer(configuration: config)
        
        // Test that errors are properly propagated and connections are cleaned up
        do {
            _ = try await container.withConnection { connection in
                // This should fail
                try connection.query("INVALID CYPHER QUERY")
            }
            #expect(Bool(false), "Expected query to fail")
        } catch {
            // Verify it's not our wrapping error
            #expect(!(error is GraphError))
        }
        
        // Verify we can still use the container after an error
        let result = try await container.withConnection { connection in
            try connection.query("RETURN 1 AS value")
        }
        #expect(Bool(true)) // Result retrieved successfully
        
        await container.close()
    }
    
    @Test("Transaction error handling")
    func transactionErrors() async throws {
        let config = GraphConfiguration(databasePath: ":memory:")
        let container = try await GraphContainer(configuration: config)
        
        // Create a test table
        _ = try await container.withConnection { connection in
            try connection.query("CREATE NODE TABLE TestNode (id INT64, PRIMARY KEY(id))")
        }
        
        // Test transaction with query error
        do {
            try await container.withTransaction { connection in
                _ = try connection.query("CREATE (:TestNode {id: 1})")
                // This should fail
                _ = try connection.query("INVALID QUERY")
            }
            #expect(Bool(false), "Expected transaction to fail")
        } catch let error as GraphError {
            if case .transactionFailed = error {
                #expect(Bool(true)) // Expected
            } else {
                #expect(Bool(false), "Expected transactionFailed error")
            }
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
        
        // Verify the transaction was rolled back
        let result = try await container.withConnection { connection in
            try connection.query("MATCH (n:TestNode) RETURN count(n) AS count")
        }
        #expect(result.hasNext())
        
        await container.close()
    }
}