import Foundation
import Kuzu

public extension QueryResult {
    // Removed redundant wrapper methods - use Kuzu's native methods directly:
    // - resetIterator() instead of reset()
    // - hasNextQueryResult() instead of hasMultipleResults
    // - getNextQueryResult() instead of nextQueryResult()
    
    func iterateResults() -> QueryResultSequence {
        return QueryResultSequence(result: self)
    }
}

public struct QueryResultSequence: Sequence {
    let result: QueryResult
    
    public func makeIterator() -> QueryResultIterator {
        return QueryResultIterator(result: result)
    }
}

public struct QueryResultIterator: IteratorProtocol {
    private let result: QueryResult
    private var hasMore: Bool = true
    
    init(result: QueryResult) {
        self.result = result
    }
    
    public mutating func next() -> QueryResult? {
        guard hasMore else { return nil }
        
        if result.hasNextQueryResult() {
            let nextResult = try? result.getNextQueryResult()
            return nextResult
        } else {
            hasMore = false
            return nil
        }
    }
}

public extension QueryResult {
    func streamRows<T>(batchSize: Int = 1000, transform: @escaping @Sendable ([String: Any]) throws -> T?) -> AsyncThrowingStream<T, Error> where T: Sendable {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var batch: [[String: Any]] = []
                    
                    while self.hasNext() {
                        guard let row = try self.mapFirst() else { break }
                        batch.append(row)
                        
                        if batch.count >= batchSize {
                            for row in batch {
                                if let transformed = try transform(row) {
                                    continuation.yield(transformed)
                                }
                            }
                            batch.removeAll(keepingCapacity: true)
                        }
                    }
                    
                    for row in batch {
                        if let transformed = try transform(row) {
                            continuation.yield(transformed)
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}