import Foundation

/// Optimized parameter name generator with lightweight generation
public struct OptimizedParameterGenerator {
    private static let counter = AtomicCounter()

    /// Generate semantic parameter names
    public static func semantic(alias: String, property: String) -> String {
        return "param_\(alias)_\(property)_\(counter.increment())"
    }

    /// Generate lightweight counter-based parameter names
    public static func lightweight(prefix: String = "p") -> String {
        return "\(prefix)\(counter.increment())"
    }

    /// Reset the generator (useful for testing)
    public static func reset() {
        counter.reset()
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