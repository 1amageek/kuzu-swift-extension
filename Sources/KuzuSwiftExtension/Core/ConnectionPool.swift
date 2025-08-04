import Foundation
import Kuzu

// MARK: - Sendable Conformance
//
// Safety Note: Connection and Database are marked as @unchecked Sendable because
// the underlying kuzu-swift types are assumed to be thread-safe based on Kuzu's
// C++ library guarantees for connection pooling scenarios.
//
// Key assumptions:
// 1. Kuzu's C++ Database class is thread-safe for read operations
// 2. Kuzu's C++ Connection instances are independent and can be used from different threads
// 3. Connection operations don't share mutable state between instances
//
// If these assumptions are incorrect, additional synchronization would be required,
// such as wrapping operations in a serial DispatchQueue or using locks.
//
// References:
// - Kuzu Documentation: https://docs.kuzudb.com/
// - Issue tracking: https://github.com/kuzudb/kuzu/issues
extension Connection: @unchecked Sendable {}
extension Database: @unchecked Sendable {}

actor ConnectionPool {
    private let database: Database
    private let maxConnections: Int
    private let minConnections: Int
    private let timeout: TimeInterval
    private let clock = ContinuousClock()
    
    private var availableConnections: [Connection] = []
    private var activeConnections: Set<ObjectIdentifier> = []
    private var waitingTasks: [WaitingTask] = []
    
    private struct WaitingTask {
        let continuation: CheckedContinuation<Connection, Error>
        let timeoutTask: Task<Void, Never>
        
        func cancel() {
            timeoutTask.cancel()
        }
    }
    
    init(
        database: Database,
        maxConnections: Int,
        minConnections: Int,
        timeout: TimeInterval
    ) async throws {
        self.database = database
        self.maxConnections = maxConnections
        self.minConnections = minConnections
        self.timeout = timeout
        
        for _ in 0..<minConnections {
            let connection = try Connection(database)
            availableConnections.append(connection)
        }
    }
    
    func checkout() async throws -> Connection {
        if let connection = availableConnections.popLast() {
            activeConnections.insert(ObjectIdentifier(connection))
            return connection
        }
        
        if activeConnections.count + availableConnections.count < maxConnections {
            let connection = try Connection(database)
            activeConnections.insert(ObjectIdentifier(connection))
            return connection
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task {
                do {
                    try await clock.sleep(for: .seconds(timeout))
                    await handleTimeout(for: continuation)
                } catch is CancellationError {
                    // Task was cancelled - this is expected when connection becomes available
                    // before timeout. The continuation will be resumed by checkin().
                    return
                } catch {
                    // Unexpected error during sleep - should not happen with clock.sleep
                    // Log for debugging if needed
                    return
                }
            }
            
            let waitingTask = WaitingTask(
                continuation: continuation,
                timeoutTask: timeoutTask
            )
            waitingTasks.append(waitingTask)
        }
    }
    
    private func handleTimeout(for continuation: CheckedContinuation<Connection, Error>) async {
        if let index = waitingTasks.firstIndex(where: { 
            $0.continuation as AnyObject === continuation as AnyObject 
        }) {
            let task = waitingTasks.remove(at: index)
            task.cancel()
            continuation.resume(throwing: GraphError.connectionTimeout(duration: timeout))
        }
    }
    
    func checkin(_ connection: Connection) {
        let id = ObjectIdentifier(connection)
        guard activeConnections.contains(id) else { return }
        
        activeConnections.remove(id)
        
        if let waitingTask = waitingTasks.first {
            waitingTasks.removeFirst()
            activeConnections.insert(id)
            waitingTask.cancel()
            waitingTask.continuation.resume(returning: connection)
        } else {
            availableConnections.append(connection)
        }
    }
    
    func drain() async {
        for waitingTask in waitingTasks {
            waitingTask.cancel()
            waitingTask.continuation.resume(throwing: GraphError.connectionPoolExhausted)
        }
        waitingTasks.removeAll()
        
        availableConnections.removeAll()
        activeConnections.removeAll()
    }
}