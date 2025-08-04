import XCTest
import Kuzu
@testable import KuzuSwiftExtension

final class ConnectionPoolTests: XCTestCase {
    var database: Database!
    
    override func setUp() async throws {
        try await super.setUp()
        database = try Database(":memory:")
    }
    
    override func tearDown() async throws {
        database = nil
        try await super.tearDown()
    }
    
    func testConnectionPoolBasicOperations() async throws {
        let pool = try await ConnectionPool(
            database: database,
            maxConnections: 3,
            minConnections: 1,
            timeout: 1.0
        )
        
        // Test checkout
        let connection1 = try await pool.checkout()
        XCTAssertNotNil(connection1)
        
        // Test checkin
        await pool.checkin(connection1)
        
        // Test multiple checkouts
        let conn1 = try await pool.checkout()
        let conn2 = try await pool.checkout()
        let conn3 = try await pool.checkout()
        
        // All connections are checked out, next checkout should wait
        let checkoutTask = Task {
            try await pool.checkout()
        }
        
        // Give the task time to start waiting
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Return a connection
        await pool.checkin(conn1)
        
        // The waiting task should now succeed
        let conn4 = try await checkoutTask.value
        XCTAssertNotNil(conn4)
        
        // Cleanup
        await pool.checkin(conn2)
        await pool.checkin(conn3)
        await pool.checkin(conn4)
        await pool.drain()
    }
    
    func testConnectionPoolTimeout() async throws {
        print("testConnectionPoolTimeout: Starting test")
        let pool = try await ConnectionPool(
            database: database,
            maxConnections: 1,
            minConnections: 0,
            timeout: 0.5 // 500ms timeout
        )
        
        print("testConnectionPoolTimeout: Pool created with 0.5s timeout")
        
        // Checkout the only connection
        let connection = try await pool.checkout()
        print("testConnectionPoolTimeout: First connection checked out")
        
        // Try to checkout another connection, should timeout
        print("testConnectionPoolTimeout: Attempting second checkout (should timeout)")
        do {
            _ = try await pool.checkout()
            XCTFail("Expected timeout error")
        } catch let error as GraphError {
            print("testConnectionPoolTimeout: Got GraphError: \(error)")
            if case .connectionTimeout(let duration) = error {
                XCTAssertEqual(duration, 0.5)
            } else {
                XCTFail("Expected connectionTimeout error, got \(error)")
            }
        } catch {
            print("testConnectionPoolTimeout: Got unexpected error: \(error)")
            XCTFail("Expected GraphError.connectionTimeout, got \(error)")
        }
        
        print("testConnectionPoolTimeout: Starting cleanup")
        // Cleanup
        await pool.checkin(connection)
        await pool.drain()
        print("testConnectionPoolTimeout: Test completed")
    }
    
    func testConnectionPoolCancellation() async throws {
        let pool = try await ConnectionPool(
            database: database,
            maxConnections: 1,
            minConnections: 0,
            timeout: 5.0 // Long timeout
        )
        
        // Checkout the only connection
        let connection = try await pool.checkout()
        
        // Start a checkout task that will wait
        let checkoutTask = Task {
            try await pool.checkout()
        }
        
        // Give it time to start waiting
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Return the connection to unblock the waiting task
        await pool.checkin(connection)
        
        // Cancel the task after it might have already gotten a connection
        checkoutTask.cancel()
        
        // The task might succeed or throw cancellation error
        do {
            let conn = try await checkoutTask.value
            // This is OK - the task got a connection before being cancelled
            await pool.checkin(conn)
        } catch {
            // Either CancellationError or the task succeeded - both are valid
            if !(error is CancellationError) {
                XCTFail("Expected CancellationError or success, got: \(error)")
            }
        }
        
        // Cleanup
        await pool.drain()
    }
    
    func testConnectionPoolDrain() async throws {
        let pool = try await ConnectionPool(
            database: database,
            maxConnections: 3,
            minConnections: 1,
            timeout: 1.0
        )
        
        // Checkout all available connections
        let conn1 = try await pool.checkout()
        let conn2 = try await pool.checkout()
        let conn3 = try await pool.checkout()
        
        // Start a waiting task that will actually wait
        let waitingTask = Task {
            try await pool.checkout()
        }
        
        // Give it time to start waiting
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Drain the pool
        await pool.drain()
        
        // The waiting task should fail
        do {
            _ = try await waitingTask.value
            XCTFail("Expected error from drained pool")
        } catch let error as GraphError {
            if case .connectionPoolExhausted = error {
                // Expected
            } else {
                XCTFail("Expected connectionPoolExhausted error, got \(error)")
            }
        }
    }
}