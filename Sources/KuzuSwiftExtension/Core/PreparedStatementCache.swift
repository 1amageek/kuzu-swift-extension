import Foundation
import Kuzu

actor PreparedStatementCache {
    private struct CacheEntry {
        let statement: PreparedStatement
        var lastAccessed: Date
        var hitCount: Int
    }
    
    private var cache: [String: CacheEntry] = [:]
    private let maxSize: Int
    private let ttl: TimeInterval
    
    init(maxSize: Int = 100, ttl: TimeInterval = 3600) {
        self.maxSize = maxSize
        self.ttl = ttl
    }
    
    func get(_ query: String, connection: Connection) throws -> PreparedStatement {
        let now = Date()
        
        if var entry = cache[query] {
            if now.timeIntervalSince(entry.lastAccessed) < ttl {
                entry.lastAccessed = now
                entry.hitCount += 1
                cache[query] = entry
                return entry.statement
            } else {
                cache.removeValue(forKey: query)
            }
        }
        
        let statement = try connection.prepare(query)
        
        if cache.count >= maxSize {
            evictLRU()
        }
        
        cache[query] = CacheEntry(
            statement: statement,
            lastAccessed: now,
            hitCount: 0
        )
        
        return statement
    }
    
    private func evictLRU() {
        guard !cache.isEmpty else { return }
        
        let sortedEntries = cache.sorted { lhs, rhs in
            let lhsScore = Double(lhs.value.hitCount) / Date().timeIntervalSince(lhs.value.lastAccessed)
            let rhsScore = Double(rhs.value.hitCount) / Date().timeIntervalSince(rhs.value.lastAccessed)
            return lhsScore < rhsScore
        }
        
        let toEvict = max(1, cache.count / 10)
        for (key, _) in sortedEntries.prefix(toEvict) {
            cache.removeValue(forKey: key)
        }
    }
    
    func clear() {
        cache.removeAll()
    }
    
    func stats() -> (hits: Int, entries: Int, avgHitRate: Double) {
        let totalHits = cache.values.reduce(0) { $0 + $1.hitCount }
        let avgHitRate = cache.isEmpty ? 0 : Double(totalHits) / Double(cache.count)
        return (totalHits, cache.count, avgHitRate)
    }
}