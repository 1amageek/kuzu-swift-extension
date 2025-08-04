import Foundation

/// Converts values between Swift types and Kuzu-compatible types
public enum ValueConverter {
    
    // MARK: - Swift to Kuzu Conversion
    
    /// Converts a Swift value to a Kuzu-compatible value
    /// - Parameter value: The Swift value to convert
    /// - Returns: The Kuzu-compatible value, or nil if the value cannot be converted
    public static func toKuzuValue(_ value: Any) -> Any? {
        switch value {
        // Date conversion: Date → TimeInterval (seconds since epoch)
        case let date as Date:
            return date.timeIntervalSince1970
            
        // UUID conversion: UUID → String
        case let uuid as UUID:
            return uuid.uuidString
            
        // Null handling
        case is NSNull:
            return nil
            
        // Optional handling
        case Optional<Any>.none:
            return nil
            
        case Optional<Any>.some(let wrapped):
            return toKuzuValue(wrapped)
            
        // Collections
        case let array as [Any]:
            return array.map { toKuzuValue($0) }
            
        case let dict as [String: Any]:
            return dict.mapValues { toKuzuValue($0) }
            
        // Pass through other values
        default:
            return value
        }
    }
    
    // MARK: - Kuzu to Swift Conversion
    
    /// Converts a Kuzu value to a Swift type
    /// - Parameters:
    ///   - value: The Kuzu value to convert
    ///   - type: The target Swift type
    /// - Returns: The converted value, or nil if conversion fails
    public static func fromKuzuValue<T>(_ value: Any, to type: T.Type) -> T? {
        // Handle nil values
        if value is NSNull {
            return nil
        }
        
        // Direct type match
        if let directValue = value as? T {
            return directValue
        }
        
        // Type-specific conversions
        switch (value, type) {
        // Date conversion: TimeInterval → Date
        case (let timestamp as Double, is Date.Type):
            return Date(timeIntervalSince1970: timestamp) as? T
            
        case (let timestamp as Int, is Date.Type):
            return Date(timeIntervalSince1970: Double(timestamp)) as? T
            
        case (let timestamp as Int64, is Date.Type):
            return Date(timeIntervalSince1970: Double(timestamp)) as? T
            
        // UUID conversion: String → UUID
        case (let uuidString as String, is UUID.Type):
            return UUID(uuidString: uuidString) as? T
            
        // Numeric conversions
        case (let int as Int, is Int64.Type):
            return Int64(int) as? T
            
        case (let int64 as Int64, is Int.Type):
            return Int(int64) as? T
            
        case (let int as Int, is Double.Type):
            return Double(int) as? T
            
        case (let int64 as Int64, is Double.Type):
            return Double(int64) as? T
            
        case (let float as Float, is Double.Type):
            return Double(float) as? T
            
        case (let double as Double, is Float.Type):
            return Float(double) as? T
            
        // String conversions
        case (let stringValue, is String.Type):
            return String(describing: stringValue) as? T
            
        default:
            return nil
        }
    }
    
    // MARK: - Batch Conversion
    
    /// Converts a dictionary of Swift values to Kuzu-compatible values
    /// - Parameter values: Dictionary of Swift values
    /// - Returns: Dictionary with converted values
    public static func toKuzuValues(_ values: [String: Any]) -> [String: Any?] {
        values.mapValues { toKuzuValue($0) }
    }
    
    /// Converts an array of Swift values to Kuzu-compatible values
    /// - Parameter values: Array of Swift values
    /// - Returns: Array with converted values
    public static func toKuzuValues(_ values: [Any]) -> [Any?] {
        values.map { toKuzuValue($0) }
    }
}