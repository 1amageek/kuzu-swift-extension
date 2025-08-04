import Foundation

/// Extracts Sendable values from Swift objects, handling property wrappers and type conversions
public enum SendableExtractor {
    
    // MARK: - Private Properties
    
    /// Creates an ISO8601 formatter for converting Date to Kuzu TIMESTAMP format
    private static func createISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
    
    // MARK: - Public API
    
    /// Extracts a Sendable value from any Swift value
    /// - Parameter value: The value to extract from
    /// - Returns: A Sendable value, or nil if extraction fails
    public static func extract(from value: Any) -> (any Sendable)? {
        // Handle Optional unwrapping using Mirror to avoid type casting issues
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            if let (_, some) = mirror.children.first {
                return extract(from: some)
            } else {
                return nil
            }
        }
        
        // Try to unwrap property wrappers
        if let wrappedValue = unwrapPropertyWrapper(value) {
            return extract(from: wrappedValue)
        }
        
        // Extract typed values with Kuzu conversions
        return extractTypedValue(from: value)
    }
    
    /// Extracts multiple Sendable values from a dictionary
    /// - Parameter dictionary: Dictionary to extract from
    /// - Returns: Dictionary with extracted Sendable values
    public static func extractAll(from dictionary: [String: Any]) -> [String: any Sendable] {
        dictionary.compactMapValues { extract(from: $0) }
    }
    
    // MARK: - Private Implementation
    
    /// Attempts to unwrap a property wrapper to access its wrapped value
    private static func unwrapPropertyWrapper(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        
        // Look for common property wrapper patterns
        for child in mirror.children {
            if let label = child.label,
               (label == "wrappedValue" || label == "_wrappedValue" || label == "value") {
                return child.value
            }
        }
        
        // Check if the type itself has a wrappedValue property
        if mirror.displayStyle == .struct || mirror.displayStyle == .class {
            for child in mirror.children {
                if child.label == "wrappedValue" || child.label == "_wrappedValue" {
                    return child.value
                }
            }
        }
        
        return nil
    }
    
    /// Extracts a Sendable value from a typed value, applying necessary conversions
    private static func extractTypedValue(from value: Any) -> (any Sendable)? {
        switch value {
        // Basic Sendable types - pass through directly
        case let v as String:
            return v
        case let v as Int:
            return v
        case let v as Int64:
            return v
        case let v as Int32:
            return Int(v)
        case let v as Int16:
            return Int(v)
        case let v as Int8:
            return Int(v)
        case let v as UInt:
            return Int(v)
        case let v as UInt64:
            return Int64(v)
        case let v as UInt32:
            return Int(v)
        case let v as UInt16:
            return Int(v)
        case let v as UInt8:
            return Int(v)
        case let v as Double:
            return v
        case let v as Float:
            return Double(v)
        case let v as Bool:
            return v
            
        // Types requiring conversion for Kuzu
        case let v as Date:
            return createISO8601Formatter().string(from: v)
        case let v as UUID:
            return v.uuidString
            
        // Collections
        case let array as [Any]:
            return array.compactMap { extract(from: $0) }
            
        case let dict as [String: Any]:
            var result: [String: any Sendable] = [:]
            for (key, val) in dict {
                if let sendableVal = extract(from: val) {
                    result[key] = sendableVal
                }
            }
            return result.isEmpty ? nil : result
            
        // NSNumber special handling
        case let number as NSNumber:
            // Check the underlying type of NSNumber
            let type = String(cString: number.objCType)
            switch type {
            case "c", "C": // char, unsigned char (Bool)
                return number.boolValue
            case "s", "S", "i", "I", "l", "L", "q", "Q": // Various integers
                return number.intValue
            case "f": // float
                return number.doubleValue
            case "d": // double
                return number.doubleValue
            default:
                return number.intValue
            }
            
        // Data
        case let data as Data:
            return data
            
        // URL
        case let url as URL:
            return url.absoluteString
            
        default:
            return nil
        }
    }
}