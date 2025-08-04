import Foundation
import Kuzu

// Ensure Kuzu types are Sendable for safe concurrent usage
// Note: This assumes kuzu-swift's Connection and Database are thread-safe
// If they are not, additional synchronization would be required
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
                } catch {
                    // Task was cancelled, ignore
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