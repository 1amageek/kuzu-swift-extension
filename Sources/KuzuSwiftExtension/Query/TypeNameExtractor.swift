import Foundation

/// Internal utility for extracting clean type names from Swift types
internal struct TypeNameExtractor {
    
    /// Extracts the type name without module prefix
    /// - Parameter type: The type to extract name from
    /// - Returns: Clean type name without module prefix
    static func extractTypeName<T>(_ type: T.Type) -> String {
        let fullName = String(describing: type)
        // Remove module prefix if present (e.g., "MyModule.Person" -> "Person")
        return fullName.components(separatedBy: ".").last ?? fullName
    }
    
    /// Extracts type name and generates default alias
    /// - Parameter type: The type to extract name from
    /// - Returns: Tuple of (typeName, defaultAlias)
    static func extractTypeInfo<T>(_ type: T.Type) -> (typeName: String, defaultAlias: String) {
        let typeName = extractTypeName(type)
        let defaultAlias = typeName.lowercased()
        return (typeName, defaultAlias)
    }
    
    /// Cache for type names to improve performance
    nonisolated(unsafe) private static var typeNameCache: [String: String] = [:]
    private static let cacheLock = NSLock()
    
    /// Extracts type name with caching for performance
    static func extractTypeNameCached<T>(_ type: T.Type) -> String {
        let key = String(describing: type)
        
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        if let cached = typeNameCache[key] {
            return cached
        }
        
        let typeName = extractTypeName(type)
        typeNameCache[key] = typeName
        return typeName
    }
}