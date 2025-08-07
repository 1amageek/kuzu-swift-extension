import Foundation
import Kuzu

public struct ConnectionConfiguration: Sendable {
    public let maxNumThreadsPerQuery: Int?
    public let queryTimeout: TimeInterval?
    
    public init(
        maxNumThreadsPerQuery: Int? = nil,
        queryTimeout: TimeInterval? = nil
    ) {
        self.maxNumThreadsPerQuery = maxNumThreadsPerQuery
        self.queryTimeout = queryTimeout
    }
    
    func apply(to connection: Connection) {
        if let maxThreads = maxNumThreadsPerQuery {
            connection.setMaxNumThreadForExec(UInt64(maxThreads))
        }
        
        if let timeout = queryTimeout {
            connection.setQueryTimeout(UInt64(timeout * 1000))
        }
    }
}

public extension Connection {
    func configure(with configuration: ConnectionConfiguration) {
        configuration.apply(to: self)
    }
    
    func interruptQuery() {
        self.interrupt()
    }
}