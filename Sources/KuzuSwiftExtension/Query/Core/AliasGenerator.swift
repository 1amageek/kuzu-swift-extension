import Foundation

/// Generates unique aliases for query components
public final class AliasGenerator: @unchecked Sendable {
    nonisolated(unsafe) private static let shared = AliasGenerator()
    private var counters: [String: Int] = [:]
    private let lock = NSLock()
    
    private init() {}
    
    /// Generate a unique alias for a given type
    public static func generate<T>(for type: T.Type) -> String {
        shared.generateAlias(for: String(describing: type))
    }
    
    /// Generate a unique alias for a given type name
    public static func generate(for typeName: String) -> String {
        shared.generateAlias(for: typeName)
    }
    
    private func generateAlias(for typeName: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        
        let baseName = typeName.lowercased()
        let count = counters[baseName, default: 0] + 1
        counters[baseName] = count
        
        return "\(baseName)_\(count)"
    }
    
    /// Reset all counters (useful for testing)
    public static func reset() {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        shared.counters.removeAll()
    }
}