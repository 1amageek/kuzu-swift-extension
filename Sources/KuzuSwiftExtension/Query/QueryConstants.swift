import Foundation

/// Configurable constants for Query DSL operations
public struct QueryConstants {
    
    /// Maximum number of return items (default: unlimited)
    nonisolated(unsafe) public static var maxReturnItems = Int.max
    
    /// Parameter cache size
    nonisolated(unsafe) public static var parameterCacheSize = 1000
    
    /// Debug mode flag
    nonisolated(unsafe) public static var debugMode = false
    
    /// Default batch size for operations
    nonisolated(unsafe) public static var defaultBatchSize = 100
    
    /// Enable performance logging
    nonisolated(unsafe) public static var performanceLoggingEnabled = false
    
    /// Query compilation timeout (in seconds)
    nonisolated(unsafe) public static var compilationTimeout: TimeInterval = 10.0
    
    /// Reset all constants to defaults
    public static func reset() {
        maxReturnItems = Int.max
        parameterCacheSize = 1000
        debugMode = false
        defaultBatchSize = 100
        performanceLoggingEnabled = false
        compilationTimeout = 10.0
    }
    
    /// Configure for testing environment
    public static func configureForTesting() {
        debugMode = true
        performanceLoggingEnabled = true
        parameterCacheSize = 100 // Smaller cache for testing
    }
    
    /// Configure for production environment
    public static func configureForProduction() {
        debugMode = false
        performanceLoggingEnabled = false
        parameterCacheSize = 10000 // Larger cache for production
    }
}

/// Performance tracking utilities
public struct QueryPerformance {
    nonisolated(unsafe) private static var measurements: [String: [TimeInterval]] = [:]
    private static let lock = NSLock()
    
    /// Measure execution time of a block
    public static func measure<T>(
        _ label: String,
        block: () throws -> T
    ) rethrows -> T {
        guard QueryConstants.performanceLoggingEnabled else {
            return try block()
        }
        
        let start = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        lock.lock()
        defer { lock.unlock() }
        
        if measurements[label] == nil {
            measurements[label] = []
        }
        measurements[label]?.append(elapsed)
        
        #if DEBUG
        if QueryConstants.debugMode {
            print("[Performance] \(label): \(String(format: "%.3f", elapsed * 1000))ms")
        }
        #endif
        
        return result
    }
    
    /// Get performance statistics
    public static func statistics(for label: String) -> (min: TimeInterval, max: TimeInterval, avg: TimeInterval)? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let times = measurements[label], !times.isEmpty else {
            return nil
        }
        
        let min = times.min() ?? 0
        let max = times.max() ?? 0
        let avg = times.reduce(0, +) / Double(times.count)
        
        return (min: min, max: max, avg: avg)
    }
    
    /// Clear all measurements
    public static func reset() {
        lock.lock()
        defer { lock.unlock() }
        measurements.removeAll()
    }
}