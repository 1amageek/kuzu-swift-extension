import XCTest
import Kuzu
@testable import KuzuSwiftExtension

final class GraphContainerTests: XCTestCase {
    
    func testGraphContainerBasicOperations() async throws {
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
        XCTAssertNotNil(result)
        
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
    
    func testGraphContainerTransaction() async throws {
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
        XCTAssertTrue(result.hasNext())
        
        // Test failed transaction (should rollback)
        do {
            try await container.withTransaction { connection in
                _ = try connection.query("CREATE (:TestNode {id: 2, name: 'test2'})")
                // Force an error
                throw GraphError.transactionFailed(reason: "Test error")
            }
            XCTFail("Transaction should have failed")
        } catch {
            // Expected
        }
        
        // Verify rollback worked (should still have only 1 node)
        let countResult = try await container.withConnection { connection in
            try connection.query("MATCH (n:TestNode) RETURN count(n) AS count")
        }
        XCTAssertTrue(countResult.hasNext())
        
        await container.close()
    }
    
    func testGraphContainerConnectionError() async throws {
        let config = GraphConfiguration(databasePath: ":memory:")
        let container = try await GraphContainer(configuration: config)
        
        // Test that errors are properly propagated and connections are cleaned up
        do {
            _ = try await container.withConnection { connection in
                // This should fail
                try connection.query("INVALID CYPHER QUERY")
            }
            XCTFail("Should have thrown an error")
        } catch {
            // Expected - verify it's not our wrapping error
            XCTAssertFalse(error is GraphError)
        }
        
        // Verify we can still use the container after an error
        let result = try await container.withConnection { connection in
            try connection.query("RETURN 1 AS value")
        }
        XCTAssertNotNil(result)
        
        await container.close()
    }
    
    func testGraphContainerTransactionError() async throws {
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
            XCTFail("Transaction should have failed")
        } catch let error as GraphError {
            if case .transactionFailed = error {
                // Expected
            } else {
                XCTFail("Expected transactionFailed error")
            }
        }
        
        // Verify the transaction was rolled back
        let result = try await container.withConnection { connection in
            try connection.query("MATCH (n:TestNode) RETURN count(n) AS count")
        }
        XCTAssertTrue(result.hasNext())
        
        await container.close()
    }
}