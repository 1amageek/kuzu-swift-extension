import Foundation

/// Converts values between Swift types and Kuzu-compatible types
public enum ValueConverter {
    
    // MARK: - Private Properties
    
    private static let maxRecursionDepth = 10
    
    /// Creates an ISO8601 formatter for converting Date to/from Kuzu TIMESTAMP format
    private static func createISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
    
    // MARK: - Swift to Kuzu Conversion
    
    /// Converts a Swift value to a Kuzu-compatible value
    /// - Parameter value: The Swift value to convert
    /// - Returns: The Kuzu-compatible value, or nil if the value cannot be converted
    public static func toKuzuValue(_ value: Any) -> Any? {
        return toKuzuValueWithDepth(value, depth: 0)
    }
    
    /// Internal conversion method with recursion depth tracking
    private static func toKuzuValueWithDepth(_ value: Any, depth: Int) -> Any? {
        // Prevent infinite recursion
        guard depth < maxRecursionDepth else {
            print("[ValueConverter] Warning: Maximum recursion depth reached. Returning original value.")
            return value
        }
        
        // Handle nil first - check for nil using Mirror to avoid type casting issues
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            // Safely unwrap optional using Mirror
            if let (_, unwrapped) = mirror.children.first {
                // Recursive call with incremented depth
                return toKuzuValueWithDepth(unwrapped, depth: depth + 1)
            } else {
                // This is Optional.none
                return nil
            }
        }
        
        // Handle specific types
        switch value {
        // Date conversion: Date → ISO-8601 string for Kuzu TIMESTAMP
        case let date as Date:
            return createISO8601Formatter().string(from: date)
            
        // UUID conversion: UUID → String
        case let uuid as UUID:
            return uuid.uuidString
            
        // Null handling - use direct type check instead of 'is'
        case _ as NSNull:
            return nil
            
        // Collections with depth tracking
        case let array as [Any]:
            return array.map { toKuzuValueWithDepth($0, depth: depth + 1) }
            
        case let dict as [String: Any]:
            return dict.mapValues { toKuzuValueWithDepth($0, depth: depth + 1) }
            
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
        // Date conversion: ISO-8601 string → Date
        case (let dateString as String, is Date.Type):
            // Try ISO8601 formatter first
            if let date = createISO8601Formatter().date(from: dateString) {
                return date as? T
            }
            // Fallback to basic format without fractional seconds
            let basicFormatter = ISO8601DateFormatter()
            basicFormatter.formatOptions = [.withInternetDateTime]
            basicFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            return basicFormatter.date(from: dateString) as? T
            
        // Legacy support: TimeInterval → Date (for backward compatibility)
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