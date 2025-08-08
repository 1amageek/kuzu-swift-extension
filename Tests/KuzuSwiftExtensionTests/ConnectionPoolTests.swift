import Testing
import Kuzu
@testable import KuzuSwiftExtension

@Suite("Connection Pool Tests", .serialized)
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
        
        // Test checkout - verify connection is valid
        let connection1 = try await pool.checkout()
        // Connection is non-optional, just verify we got here without error
        
        // Test checkin and reuse
        await pool.checkin(connection1)
        
        // Test multiple checkouts don't exceed max
        let conn1 = try await pool.checkout()
        let conn2 = try await pool.checkout()
        let conn3 = try await pool.checkout()
        
        // All connections are checked out, next checkout should wait
        // Use confirmation to verify that checkout is blocked until a connection is returned
        try await confirmation("Connection checkout completes after checkin") { checkoutCompleted in
            let checkoutTask = Task {
                let conn = try await pool.checkout()
                checkoutCompleted()
                return conn
            }
            
            // Give the task a moment to start and hit the wait state
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            // Return a connection to unblock the waiting checkout
            await pool.checkin(conn1)
            
            // Wait for the checkout to complete
            let conn4 = try await checkoutTask.value
            
            // Cleanup
            await pool.checkin(conn2)
            await pool.checkin(conn3)
            await pool.checkin(conn4)
        }
        
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
        await #expect(throws: GraphError.self) {
            _ = try await pool.checkout()
        }
        
        // Verify the specific error type and duration
        do {
            _ = try await pool.checkout()
            Issue.record("Expected timeout error but succeeded")
        } catch let error as GraphError {
            if case .connectionTimeout(let duration) = error {
                // Allow small tolerance for timing
                #expect(abs(duration - 0.5) < 0.01, "Timeout duration mismatch: \(duration)")
            } else {
                Issue.record("Expected connectionTimeout error, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
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
        
        // Use confirmation to test cancellation behavior
        // We expect either: task gets cancelled (0 confirmations) or task succeeds before cancel (1 confirmation)
        try await confirmation("Checkout task behavior", expectedCount: 0...1) { checkoutOccurred in
            let checkoutTask = Task {
                let conn = try await pool.checkout()
                checkoutOccurred()
                return conn
            }
            
            // Give the task a moment to start and hit the wait state
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            // Cancel the task
            checkoutTask.cancel()
            
            // Return the connection - this might unblock the task before cancellation takes effect
            await pool.checkin(connection)
            
            // Check the task result
            do {
                let conn = try await checkoutTask.value
                // Task succeeded before cancellation
                await pool.checkin(conn)
            } catch is CancellationError {
                // Task was cancelled as expected
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
        
        await pool.drain()
    }
    
    @Test("Connection pool drain")
    func drain() async throws {
        let database = try createDatabase()
        let pool = try await ConnectionPool(
            database: database,
            maxConnections: 2,  // Only 2 connections max
            minConnections: 0,
            timeout: 1.0
        )
        
        // Checkout all available connections
        let conn1 = try await pool.checkout()
        let conn2 = try await pool.checkout()
        
        // Now pool is at max, next checkout will wait
        let waitingTask = Task {
            do {
                _ = try await pool.checkout()
                Issue.record("Checkout succeeded when it should have failed")
                return false
            } catch let error as GraphError {
                if case .connectionPoolExhausted = error {
                    return true  // Got expected error
                } else {
                    Issue.record("Wrong error type: \(error)")
                    return false
                }
            } catch {
                Issue.record("Unexpected error type: \(error)")
                return false
            }
        }
        
        // Give the task a moment to start and hit the wait state
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Drain the pool - this should interrupt the waiting task
        await pool.drain()
        
        // Check result
        let gotExpectedError = try await waitingTask.value
        #expect(gotExpectedError, "Waiting task should get connectionPoolExhausted error")
        
        // Verify pool is drained - new checkout should fail
        await #expect(throws: GraphError.self) {
            _ = try await pool.checkout()
        }
    }
}
