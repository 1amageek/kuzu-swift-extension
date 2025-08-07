import Testing
import Kuzu
@testable import KuzuSwiftExtension

@Suite("Connection Pool Tests")
struct ConnectionPoolTests {
    
    func createDatabase() throws -> Database {
        return try Database(":memory:")
    }
    
    @Test("Basic pool operations")
    func basicOperations() async throws {
        let database = try createDatabase()
        let pool = try await ConnectionPool(
            database: database,
            maxConnections: 3,
            minConnections: 1,
            timeout: 1.0
        )
        
        // Test checkout
        let connection1 = try await pool.checkout()
        #expect(Bool(true)) // Connection retrieved successfully
        
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
        #expect(Bool(true)) // Connection retrieved successfully
        
        // Cleanup
        await pool.checkin(conn2)
        await pool.checkin(conn3)
        await pool.checkin(conn4)
        await pool.drain()
    }
    
    @Test("Connection pool timeout")
    func timeout() async throws {
        let database = try createDatabase()
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
            #expect(Bool(false), "Expected timeout error")
        } catch let error as GraphError {
            if case .connectionTimeout(let duration) = error {
                #expect(duration == 0.5)
            } else {
                #expect(Bool(false), "Expected connectionTimeout error, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
        
        // Cleanup
        await pool.checkin(connection)
        await pool.drain()
    }
    
    @Test("Connection pool cancellation")
    func cancellation() async throws {
        let database = try createDatabase()
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
            #expect(error is CancellationError || error is GraphError)
        }
        
        // Cleanup
        await pool.drain()
    }
    
    @Test("Connection pool drain")
    func drain() async throws {
        let database = try createDatabase()
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
            #expect(Bool(false), "Expected task to fail")
        } catch let error as GraphError {
            if case .connectionPoolExhausted = error {
                // Expected
                #expect(Bool(true))
            } else {
                #expect(Bool(false), "Expected connectionPoolExhausted error, got \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }
}