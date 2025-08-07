import Foundation

/// Shared utility for type conversions between Swift and Kuzu types
internal struct TypeConversion {
    
    /// Convert any value to the target type with automatic type coercion
    static func convert<T>(_ value: Any, to type: T.Type) -> T? {
        // Direct cast if already correct type
        if let typedValue = value as? T {
            return typedValue
        }
        
        // Numeric conversions
        switch (value, type) {
        // Int conversions
        case (let int as Int, is Int64.Type):
            return Int64(int) as? T
        case (let int as Int, is Double.Type):
            return Double(int) as? T
        case (let int as Int, is Float.Type):
            return Float(int) as? T
            
        // Int64 conversions
        case (let int64 as Int64, is Int.Type):
            // Check for overflow
            guard int64 >= Int64(Int.min) && int64 <= Int64(Int.max) else {
                return nil
            }
            return Int(int64) as? T
        case (let int64 as Int64, is Float.Type):
            return Float(int64) as? T
        case (let int64 as Int64, is Double.Type):
            return Double(int64) as? T
            
        // Float conversions
        case (let float as Float, is Double.Type):
            return Double(float) as? T
        case (let float as Float, is Int.Type):
            return Int(float) as? T
        case (let float as Float, is Int64.Type):
            return Int64(float) as? T
            
        // Double conversions
        case (let double as Double, is Float.Type):
            // Check for Float overflow
            guard abs(double) <= Double(Float.greatestFiniteMagnitude) else {
                return nil
            }
            return Float(double) as? T
        case (let double as Double, is Int.Type):
            // Check for integer overflow and valid range
            guard double >= Double(Int.min) && double <= Double(Int.max) && double.isFinite else {
                return nil
            }
            return Int(double) as? T
        case (let double as Double, is Int64.Type):
            // Check for Int64 overflow and valid range
            guard double >= Double(Int64.min) && double <= Double(Int64.max) && double.isFinite else {
                return nil
            }
            return Int64(double) as? T
            
        // Date conversions
        case (let double as Double, is Date.Type):
            return Date(timeIntervalSince1970: double) as? T
        case (let int as Int, is Date.Type):
            return Date(timeIntervalSince1970: Double(int)) as? T
        case (let int64 as Int64, is Date.Type):
            return Date(timeIntervalSince1970: Double(int64)) as? T
        case (let string as String, is Date.Type):
            return parseISO8601Date(string) as? T
            
        // UUID conversions
        case (let string as String, is UUID.Type):
            // Validate UUID string format
            guard let uuid = UUID(uuidString: string) else {
                return nil
            }
            return uuid as? T
            
        // String conversions
        case (_, is String.Type) where !(value is NSNull):
            return String(describing: value) as? T
            
        default:
            return nil
        }
    }
    
    /// Parse ISO8601 date string
    static func parseISO8601Date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
    
    /// Format date as ISO8601 string
    static func formatISO8601Date(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}