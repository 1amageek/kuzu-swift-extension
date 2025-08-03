import Foundation

/// A Sendable-compliant value type for query parameters
public enum ParameterValue: Sendable, Equatable {
    case string(String)
    case int64(Int64)
    case double(Double)
    case bool(Bool)
    case timestamp(TimeInterval)
    case uuid(String)
    case vector([Double])
    case json(String)
    case null
    
    /// Converts the parameter value to the type expected by Kuzu
    var kuzuValue: Any? {
        switch self {
        case .string(let value):
            return value
        case .int64(let value):
            return value
        case .double(let value):
            return value
        case .bool(let value):
            return value
        case .timestamp(let value):
            return value
        case .uuid(let value):
            return value
        case .vector(let value):
            return value
        case .json(let value):
            return value
        case .null:
            return nil
        }
    }
    
    /// Creates a ParameterValue from an Encodable value
    static func from<T: Encodable & Sendable>(_ value: T) throws -> ParameterValue {
        switch value {
        case let v as String:
            return .string(v)
        case let v as Int:
            return .int64(Int64(v))
        case let v as Int32:
            return .int64(Int64(v))
        case let v as Int64:
            return .int64(v)
        case let v as Double:
            return .double(v)
        case let v as Float:
            return .double(Double(v))
        case let v as Bool:
            return .bool(v)
        case let v as Date:
            return .timestamp(v.timeIntervalSince1970)
        case let v as UUID:
            return .uuid(v.uuidString)
        case let v as [Double]:
            return .vector(v)
        default:
            // Try JSON encoding for complex types
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .sortedKeys
            
            do {
                let data = try encoder.encode(value)
                guard let json = String(data: data, encoding: .utf8) else {
                    throw QueryError.parameterConversionFailed(
                        parameter: String(describing: T.self),
                        valueType: String(describing: type(of: value)),
                        reason: "Failed to convert encoded data to UTF-8 string"
                    )
                }
                return .json(json)
            } catch {
                throw QueryError.parameterConversionFailed(
                    parameter: String(describing: T.self),
                    valueType: String(describing: type(of: value)),
                    reason: error.localizedDescription
                )
            }
        }
    }
}

/// Type alias for Sendable parameter collections
public typealias SendableParameters = [String: ParameterValue]