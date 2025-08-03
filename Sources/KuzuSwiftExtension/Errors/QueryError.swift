import Foundation

public enum QueryError: LocalizedError {
    case compilationFailed(query: String, reason: String)
    case executionFailed(query: String, reason: String)
    case bindingFailed(parameter: String, valueType: String)
    case resultMappingFailed(type: String, reason: String)
    case invalidPattern(pattern: String, reason: String)
    case missingRequiredProperty(property: String)
    case typeMismatch(expected: String, actual: String)
    case constraintViolation(constraint: String)
    case parameterConversionFailed(parameter: String, valueType: String, reason: String)
    case unsupportedParameterType(parameter: String, type: String)
    
    public var errorDescription: String? {
        switch self {
        case .compilationFailed(let query, let reason):
            return "Failed to compile query: \(reason)\nQuery: \(query)"
        case .executionFailed(let query, let reason):
            return "Failed to execute query: \(reason)\nQuery: \(query)"
        case .bindingFailed(let parameter, let valueType):
            return "Failed to bind parameter '\(parameter)' with value type: \(valueType)"
        case .resultMappingFailed(let type, let reason):
            return "Failed to map result to type '\(type)': \(reason)"
        case .invalidPattern(let pattern, let reason):
            return "Invalid pattern '\(pattern)': \(reason)"
        case .missingRequiredProperty(let property):
            return "Missing required property: \(property)"
        case .typeMismatch(let expected, let actual):
            return "Type mismatch: expected '\(expected)', got '\(actual)'"
        case .constraintViolation(let constraint):
            return "Constraint violation: \(constraint)"
        case .parameterConversionFailed(let parameter, let valueType, let reason):
            return "Failed to convert parameter '\(parameter)' of type '\(valueType)': \(reason)"
        case .unsupportedParameterType(let parameter, let type):
            return "Unsupported parameter type for '\(parameter)': \(type)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .compilationFailed:
            return "Check Cypher syntax and ensure all referenced nodes/relationships exist"
        case .executionFailed:
            return "Verify data integrity and check for concurrent modifications"
        case .bindingFailed:
            return "Ensure parameter value is Encodable and matches expected type"
        case .resultMappingFailed:
            return "Verify result structure matches the target type"
        case .invalidPattern:
            return "Review pattern syntax and ensure it follows Cypher conventions"
        case .missingRequiredProperty:
            return "Provide all required properties when creating nodes/edges"
        case .typeMismatch:
            return "Ensure property types match the schema definition"
        case .constraintViolation:
            return "Check for duplicate keys or invalid relationships"
        case .parameterConversionFailed:
            return "Ensure the parameter value is a supported type"
        case .unsupportedParameterType:
            return "Use a supported parameter type: String, Int, Double, Bool, Date, UUID, or [Double]"
        }
    }
}