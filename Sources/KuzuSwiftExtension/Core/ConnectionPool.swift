import Foundation
import KuzuFramework

actor ConnectionPool {
    private var available: [Connection]
    private var inUse: Set<ObjectIdentifier> = []
    private let database: Database
    private let maxSize: Int
    private var waitingContinuations: [CheckedContinuation<Connection, Error>] = []
    
    init(database: Database, size: Int) throws {
        self.database = database
        self.maxSize = size
        self.available = []
        
        // Pre-create connections
        for _ in 0..<size {
            available.append(try Connection(database))
        }
    }
    
    func acquire() async throws -> Connection {
        // If connection available, return it
        if let connection = available.popLast() {
            inUse.insert(ObjectIdentifier(connection))
            return connection
        }
        
        // If pool not exhausted, create new connection
        if inUse.count < maxSize {
            let connection = try Connection(database)
            inUse.insert(ObjectIdentifier(connection))
            return connection
        }
        
        // Wait for available connection
        return try await withCheckedThrowingContinuation { continuation in
            waitingContinuations.append(continuation)
        }
    }
    
    func release(_ connection: Connection) {
        inUse.remove(ObjectIdentifier(connection))
        
        // If someone is waiting, give them the connection
        if let continuation = waitingContinuations.first {
            waitingContinuations.removeFirst()
            inUse.insert(ObjectIdentifier(connection))
            continuation.resume(returning: connection)
        } else {
            // Otherwise, return to available pool
            available.append(connection)
        }
    }
    
    func withConnection<T>(_ block: (Connection) async throws -> T) async throws -> T {
        let connection = try await acquire()
        defer {
            Task {
                await release(connection)
            }
        }
        return try await block(connection)
    }
}