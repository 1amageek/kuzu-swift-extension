import Foundation

/// Unified error type for all Kuzu operations
public enum KuzuError: LocalizedError {
    // MARK: - Query Compilation
    case compilationFailed(query: String, reason: String)
    case invalidPattern(pattern: String, reason: String)
    
    // MARK: - Query Execution
    case executionFailed(query: String, reason: String)
    case bindingFailed(parameter: String, valueType: String)
    case parameterConversionFailed(parameter: String, valueType: String, reason: String)
    case unsupportedParameterType(parameter: String, type: String)
    
    // MARK: - Result Mapping
    case noResults
    case typeMismatch(expected: String, actual: String, field: String? = nil)
    case decodingFailed(field: String, underlyingError: Error)
    case invalidValue(field: String, valueDescription: String)
    case missingRequiredField(String)
    case nullValueForNonOptionalType(field: String, type: String)
    case columnIndexOutOfBounds(index: Int, columnCount: Int)
    case columnNotFound(column: String)
    
    // MARK: - Schema & Constraints
    case missingRequiredProperty(property: String)
    case constraintViolation(constraint: String)
    
    public var errorDescription: String? {
        switch self {
        // Query Compilation
        case .compilationFailed(let query, let reason):
            return "Failed to compile query: \(reason)\nQuery: \(query)"
        case .invalidPattern(let pattern, let reason):
            return "Invalid pattern '\(pattern)': \(reason)"
            
        // Query Execution
        case .executionFailed(let query, let reason):
            return "Failed to execute query: \(reason)\nQuery: \(query)"
        case .bindingFailed(let parameter, let valueType):
            return "Failed to bind parameter '\(parameter)' with value type: \(valueType)"
        case .parameterConversionFailed(let parameter, let valueType, let reason):
            return "Failed to convert parameter '\(parameter)' of type '\(valueType)': \(reason)"
        case .unsupportedParameterType(let parameter, let type):
            return "Unsupported parameter type for '\(parameter)': \(type)"
            
        // Result Mapping
        case .noResults:
            return "No results available to map"
        case .typeMismatch(let expected, let actual, let field):
            if let field = field {
                return "Type mismatch for field '\(field)': expected \(expected), got \(actual)"
            } else {
                return "Type mismatch: expected \(expected), got \(actual)"
            }
        case .decodingFailed(let field, let underlyingError):
            return "Failed to decode field '\(field)': \(underlyingError.localizedDescription)"
        case .invalidValue(let field, let valueDescription):
            return "Invalid value for field '\(field)': \(valueDescription)"
        case .missingRequiredField(let field):
            return "Required field '\(field)' is missing from the result"
        case .nullValueForNonOptionalType(let field, let type):
            return "Field '\(field)' contains null value but expected non-optional type \(type)"
        case .columnIndexOutOfBounds(let index, let columnCount):
            return "Column index \(index) is out of bounds (total columns: \(columnCount))"
        case .columnNotFound(let column):
            return "Column '\(column)' not found in query result"
            
        // Schema & Constraints
        case .missingRequiredProperty(let property):
            return "Missing required property: \(property)"
        case .constraintViolation(let constraint):
            return "Constraint violation: \(constraint)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .compilationFailed:
            return "Check Cypher syntax and ensure all referenced nodes/relationships exist"
        case .invalidPattern:
            return "Review pattern syntax and ensure it follows Cypher conventions"
        case .executionFailed:
            return "Verify data integrity and check for concurrent modifications"
        case .bindingFailed, .parameterConversionFailed:
            return "Ensure parameter value is Encodable and matches expected type"
        case .unsupportedParameterType:
            return "Use a supported parameter type: String, Int, Double, Bool, Date, UUID, or [Double]"
        case .noResults:
            return "Verify your query conditions match existing data"
        case .typeMismatch:
            return "Ensure property types match the schema definition"
        case .decodingFailed:
            return "Check that the value format matches the target type requirements"
        case .invalidValue:
            return "Ensure the value meets the validation requirements"
        case .missingRequiredField:
            return "Include all required fields in your query's RETURN clause"
        case .nullValueForNonOptionalType:
            return "Use optional types for fields that may contain null values"
        case .columnIndexOutOfBounds, .columnNotFound:
            return "Verify column names/indices match your query's RETURN clause"
        case .missingRequiredProperty:
            return "Provide all required properties when creating nodes/edges"
        case .constraintViolation:
            return "Check for duplicate keys or invalid relationships"
        }
    }
}

// MARK: - Compatibility Type Aliases

/// Compatibility alias for QueryError
public typealias QueryError = KuzuError

/// Compatibility alias for ResultMappingError
public typealias ResultMappingError = KuzuError