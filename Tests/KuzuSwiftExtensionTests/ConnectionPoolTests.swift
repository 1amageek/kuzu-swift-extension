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
        let pool = try await ConnectionPool(
            database: database,
            maxConnections: 1,
            minConnections: 0,
            timeout: 0.5 // 500ms timeout
        )
        
        // Checkout the only connection
        let connection = try await pool.checkout()
        
        // Try to checkout another connection, should timeout
        do {
            _ = try await pool.checkout()
            XCTFail("Expected timeout error")
        } catch let error as GraphError {
            if case .connectionTimeout(let duration) = error {
                XCTAssertEqual(duration, 0.5)
            } else {
                XCTFail("Expected connectionTimeout error, got \(error)")
            }
        }
        
        // Cleanup
        await pool.checkin(connection)
        await pool.drain()
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
        
        // Cancel the task
        checkoutTask.cancel()
        
        // The task should throw CancellationError
        do {
            _ = try await checkoutTask.value
            XCTFail("Expected cancellation error")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        
        // Cleanup
        await pool.checkin(connection)
        await pool.drain()
    }
    
    func testConnectionPoolDrain() async throws {
        let pool = try await ConnectionPool(
            database: database,
            maxConnections: 3,
            minConnections: 1,
            timeout: 1.0
        )
        
        // Checkout some connections
        let conn1 = try await pool.checkout()
        let conn2 = try await pool.checkout()
        
        // Start a waiting task
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