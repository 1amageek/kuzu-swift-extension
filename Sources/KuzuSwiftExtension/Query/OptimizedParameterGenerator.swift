import Foundation

/// Optimized parameter name generator with caching and lightweight generation
public struct OptimizedParameterGenerator {
    nonisolated(unsafe) private static let counter = AtomicCounter()
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = QueryConstants.parameterCacheSize
        return cache
    }()
    
    /// Generate semantic parameter names with caching
    public static func semantic(alias: String, property: String) -> String {
        let key = "\(alias)_\(property)" as NSString
        
        // Check cache first
        if let cached = cache.object(forKey: key) {
            return cached as String
        }
        
        // Generate new semantic name
        let paramName = "param_\(alias)_\(property)_\(counter.increment())"
        cache.setObject(paramName as NSString, forKey: key)
        return paramName
    }
    
    /// Generate lightweight counter-based parameter names
    public static func lightweight(prefix: String = "p") -> String {
        return "\(prefix)\(counter.increment())"
    }
    
    /// Generate cached parameter name for a value
    public static func cached(for value: any Sendable) -> String {
        let key = String(describing: value).hashValue
        let cacheKey = NSString(string: "v_\(key)")
        
        if let cached = cache.object(forKey: cacheKey) {
            return cached as String
        }
        
        let paramName = lightweight(prefix: "param_")
        cache.setObject(NSString(string: paramName), forKey: cacheKey)
        return paramName
    }
    
    /// Reset the generator (useful for testing)
    public static func reset() {
        counter.reset()
        cache.removeAllObjects()
    }
    
    /// Get current counter value (for debugging)
    public static var currentCount: Int64 {
        counter.value
    }
}

/// Thread-safe atomic counter
private final class AtomicCounter: @unchecked Sendable {
    private var _value: Int64 = 0
    private let lock = NSLock()
    
    var value: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    
    func increment() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
        return _value
    }
    
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        _value = 0
    }
}

// Note: ParameterNameGenerator extension moved to avoid duplication