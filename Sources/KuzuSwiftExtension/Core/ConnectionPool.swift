import Foundation
import Kuzu

actor ConnectionPool {
    private let database: Database
    private let maxConnections: Int
    private let minConnections: Int
    private let timeout: TimeInterval
    
    private var availableConnections: [Connection] = []
    private var activeConnections: Set<ObjectIdentifier> = []
    private var waitingTasks: [CheckedContinuation<Connection, Error>] = []
    
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
            waitingTasks.append(continuation)
            
            Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let index = waitingTasks.firstIndex(where: { $0 as AnyObject === continuation as AnyObject }) {
                    waitingTasks.remove(at: index)
                    continuation.resume(throwing: GraphError.connectionPoolExhausted)
                }
            }
        }
    }
    
    func checkin(_ connection: Connection) {
        let id = ObjectIdentifier(connection)
        guard activeConnections.contains(id) else { return }
        
        activeConnections.remove(id)
        
        if let waitingTask = waitingTasks.first {
            waitingTasks.removeFirst()
            activeConnections.insert(id)
            waitingTask.resume(returning: connection)
        } else {
            availableConnections.append(connection)
        }
    }
    
    func drain() async {
        for continuation in waitingTasks {
            continuation.resume(throwing: GraphError.connectionPoolExhausted)
        }
        waitingTasks.removeAll()
        
        availableConnections.removeAll()
        activeConnections.removeAll()
    }
}