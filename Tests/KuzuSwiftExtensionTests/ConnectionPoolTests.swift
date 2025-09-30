import Testing
import Kuzu
@testable import KuzuSwiftExtension

@Suite("Connection Pool Tests", .serialized)
struct ConnectionPoolTests {

    func createDatabase() throws -> Database {
        return try Database(":memory:")
    }

    // MARK: - Basic Operations

    @Test("Checkout and checkin single connection")
    func checkoutCheckinSingle() async throws {
        let database = try createDatabase()
        let pool = try await ConnectionPool(
            database: database,
            maxConnections: 3,
            minConnections: 1,
            timeout: 1.0
        )

        // Test checkout - verify connection is valid
        let connection = try await pool.checkout()

        // Verify connection works
        let result = try connection.query("RETURN 1 AS value")
        #expect(result.hasNext())
        if let row = try result.getNext(),
           let value = try row.getValue(0) as? Int64 {
            #expect(value == 1)
        } else {
            Issue.record("Failed to execute query on connection")
        }

        // Return connection
        await pool.checkin(connection)

        // Verify connection is reused
        let connection2 = try await pool.checkout()
        let result2 = try connection2.query("RETURN 2 AS value")
        #expect(result2.hasNext())

        await pool.checkin(connection2)
        await pool.drain()
    }

    @Test("Multiple concurrent connections within max limit")
    func concurrentConnectionsWithinLimit() async throws {
        let database = try createDatabase()
        let pool = try await ConnectionPool(
            database: database,
            maxConnections: 3,
            minConnections: 1,
            timeout: 1.0
        )

        // Use TaskGroup for explicit concurrency control
        try await withThrowingTaskGroup(of: Int64.self) { group in
            // Start 3 concurrent tasks (exactly at max limit)
            for i in 1...3 {
                group.addTask {
                    let connection = try await pool.checkout()
                    let result = try connection.query("RETURN \(i) AS value")

                    // Hold connection briefly to ensure all 3 are checked out simultaneously
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms

                    #expect(result.hasNext())
                    let row = try result.getNext()
                    let value = try row?.getValue(0) as? Int64

                    await pool.checkin(connection)
                    return value ?? 0
                }
            }

            // Collect all results
            var results: [Int64] = []
            for try await value in group {
                results.append(value)
            }

            // Verify all tasks completed successfully
            #expect(results.count == 3)
            #expect(Set(results) == Set([1, 2, 3]))
        }

        await pool.drain()
    }

    @Test("Connection reuse after checkin")
    func connectionReuse() async throws {
        let database = try createDatabase()
        let pool = try await ConnectionPool(
            database: database,
            maxConnections: 2,
            minConnections: 1,
            timeout: 1.0
        )

        // Checkout and return connection multiple times
        for i in 1...5 {
            let connection = try await pool.checkout()
            let result = try connection.query("RETURN \(i) AS value")
            #expect(result.hasNext())
            await pool.checkin(connection)
        }

        await pool.drain()
    }

    // MARK: - Timeout Tests

    @Test("Connection timeout when pool exhausted")
    func connectionTimeout() async throws {
        let database = try createDatabase()
        let pool = try await ConnectionPool(
            database: database,
            maxConnections: 1,
            minConnections: 0,
            timeout: 0.5 // 500ms timeout
        )

        // Checkout the only connection
        let connection = try await pool.checkout()

        // Measure timeout duration
        let startTime = ContinuousClock.now

        // Try to checkout another connection - should timeout
        do {
            _ = try await pool.checkout()
            Issue.record("Expected timeout error but checkout succeeded")
        } catch let error as GraphError {
            let elapsed = startTime.duration(to: ContinuousClock.now)

            if case .connectionTimeout(let duration) = error {
                // Verify timeout duration is correct (allow 50ms tolerance)
                #expect(abs(duration - 0.5) < 0.05, "Timeout duration mismatch: expected 0.5s, got \(duration)s")

                // Verify actual elapsed time matches timeout setting
                let elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                #expect(abs(elapsedSeconds - 0.5) < 0.1, "Actual elapsed time \(elapsedSeconds)s doesn't match timeout 0.5s")
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

    @Test("Waiting task unblocks when connection available")
    func waitingTaskUnblocks() async throws {
        let database = try createDatabase()
        let pool = try await ConnectionPool(
            database: database,
            maxConnections: 1,
            minConnections: 0,
            timeout: 5.0 // Long timeout to avoid timeout during test
        )

        // Checkout the only connection
        let connection1 = try await pool.checkout()

        try await withThrowingTaskGroup(of: Bool.self) { group in
            // Task 1: Wait for connection to become available
            group.addTask {
                let startTime = ContinuousClock.now
                let conn = try await pool.checkout()
                let elapsed = startTime.duration(to: ContinuousClock.now)
                let elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

                // Should have waited approximately 200ms
                let waitedCorrectly = elapsedSeconds > 0.15 && elapsedSeconds < 0.4

                await pool.checkin(conn)
                return waitedCorrectly
            }

            // Task 2: Return connection after 200ms
            group.addTask {
                try await Task.sleep(nanoseconds: 200_000_000) // 200ms
                await pool.checkin(connection1)
                return true
            }

            // Verify both tasks completed successfully
            var results: [Bool] = []
            for try await result in group {
                results.append(result)
            }

            #expect(results.count == 2)
            #expect(results.allSatisfy { $0 == true }, "Waiting task should have unblocked correctly")
        }

        await pool.drain()
    }

    // MARK: - Error Handling Tests

    @Test("Error propagation and connection cleanup")
    func errorPropagation() async throws {
        let database = try createDatabase()
        let pool = try await ConnectionPool(
            database: database,
            maxConnections: 2,
            minConnections: 1,
            timeout: 1.0
        )

        // Test that errors are properly propagated
        await #expect(throws: Error.self, "Invalid query should fail") {
            let connection = try await pool.checkout()
            defer {
                Task { await pool.checkin(connection) }
            }
            _ = try connection.query("INVALID CYPHER QUERY")
        }

        // Verify pool is still functional after error
        let connection = try await pool.checkout()
        let result = try connection.query("RETURN 1 AS value")
        #expect(result.hasNext())
        await pool.checkin(connection)

        await pool.drain()
    }

    // MARK: - Drain Tests

    @Test("Drain interrupts waiting tasks")
    func drainInterruptsWaiting() async throws {
        let database = try createDatabase()
        let pool = try await ConnectionPool(
            database: database,
            maxConnections: 1,
            minConnections: 0,
            timeout: 10.0 // Long timeout
        )

        // Checkout the only connection
        let connection = try await pool.checkout()

        let waitingTask = Task {
            do {
                _ = try await pool.checkout()
                return false // Should not reach here
            } catch let error as GraphError {
                if case .connectionPoolExhausted = error {
                    return true // Expected error
                }
                return false
            } catch {
                return false
            }
        }

        // Give task time to start waiting
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Drain pool - should interrupt waiting task
        await pool.drain()

        let gotExpectedError = try await waitingTask.value
        #expect(gotExpectedError, "Waiting task should receive connectionPoolExhausted error")
    }

    @Test("Drain prevents new checkouts")
    func drainPreventsNewCheckouts() async throws {
        let database = try createDatabase()
        let pool = try await ConnectionPool(
            database: database,
            maxConnections: 2,
            minConnections: 1,
            timeout: 1.0
        )

        // Verify pool works initially
        let connection = try await pool.checkout()
        await pool.checkin(connection)

        // Drain the pool
        await pool.drain()

        // Verify new checkouts fail
        do {
            _ = try await pool.checkout()
            Issue.record("Checkout should fail after drain")
        } catch let error as GraphError {
            if case .connectionPoolExhausted = error {
                // Expected error
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Drain clears all connections")
    func drainClearsConnections() async throws {
        let database = try createDatabase()
        let pool = try await ConnectionPool(
            database: database,
            maxConnections: 3,
            minConnections: 2,
            timeout: 1.0
        )

        // Checkout and return some connections to ensure they exist
        let conn1 = try await pool.checkout()
        let conn2 = try await pool.checkout()
        await pool.checkin(conn1)
        await pool.checkin(conn2)

        // Drain pool
        await pool.drain()

        // Verify subsequent operations fail
        await #expect(throws: GraphError.self) {
            _ = try await pool.checkout()
        }
    }

    // MARK: - Min/Max Connection Tests

    @Test("Minimum connections initialized")
    func minimumConnectionsInitialized() async throws {
        let database = try createDatabase()
        let pool = try await ConnectionPool(
            database: database,
            maxConnections: 5,
            minConnections: 3,
            timeout: 1.0
        )

        // Should be able to immediately checkout minConnections without creating new ones
        let conn1 = try await pool.checkout()
        let conn2 = try await pool.checkout()
        let conn3 = try await pool.checkout()

        // All should work
        _ = try conn1.query("RETURN 1")
        _ = try conn2.query("RETURN 1")
        _ = try conn3.query("RETURN 1")

        await pool.checkin(conn1)
        await pool.checkin(conn2)
        await pool.checkin(conn3)
        await pool.drain()
    }

    @Test("Pool creates connections up to max")
    func poolCreatesUpToMax() async throws {
        let database = try createDatabase()
        let pool = try await ConnectionPool(
            database: database,
            maxConnections: 3,
            minConnections: 0,
            timeout: 1.0
        )

        // Checkout more than minConnections, up to maxConnections
        let conn1 = try await pool.checkout()
        let conn2 = try await pool.checkout()
        let conn3 = try await pool.checkout()

        // All should work
        _ = try conn1.query("RETURN 1")
        _ = try conn2.query("RETURN 2")
        _ = try conn3.query("RETURN 3")

        await pool.checkin(conn1)
        await pool.checkin(conn2)
        await pool.checkin(conn3)
        await pool.drain()
    }
}
