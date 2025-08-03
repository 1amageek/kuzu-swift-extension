import Foundation

/// Utility for converting between different parameter representations
public struct ParameterConverter {
    
    /// Converts a dictionary of Encodable values to SendableParameters
    public static func convert(_ bindings: [String: any Encodable & Sendable]) throws -> SendableParameters {
        var converted: SendableParameters = [:]
        
        for (key, value) in bindings {
            do {
                converted[key] = try ParameterValue.from(value)
            } catch {
                // Re-throw with more context
                throw QueryError.parameterConversionFailed(
                    parameter: key,
                    valueType: String(describing: type(of: value)),
                    reason: error.localizedDescription
                )
            }
        }
        
        return converted
    }
    
    /// Converts SendableParameters to Kuzu-compatible parameters
    public static func toKuzuParameters(_ parameters: SendableParameters) -> [String: Any?] {
        var kuzuParams: [String: Any?] = [:]
        
        for (key, value) in parameters {
            kuzuParams[key] = value.kuzuValue
        }
        
        return kuzuParams
    }
    
    /// Validates that all parameter values are supported types
    public static func validate(_ parameters: SendableParameters) throws {
        for (key, value) in parameters {
            switch value {
            case .vector(let values):
                // Validate vector dimensions if needed
                if values.isEmpty {
                    throw QueryError.parameterConversionFailed(
                        parameter: key,
                        valueType: "Vector",
                        reason: "Vector cannot be empty"
                    )
                }
            case .json(let jsonString):
                // Validate JSON if needed
                let data = jsonString.data(using: .utf8) ?? Data()
                do {
                    _ = try JSONSerialization.jsonObject(with: data)
                } catch {
                    throw QueryError.parameterConversionFailed(
                        parameter: key,
                        valueType: "JSON",
                        reason: "Invalid JSON: \(error.localizedDescription)"
                    )
                }
            default:
                // Other types are already validated
                break
            }
        }
    }
}