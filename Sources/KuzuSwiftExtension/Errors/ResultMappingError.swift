import Foundation

/// Errors that can occur during result mapping operations
public enum ResultMappingError: LocalizedError {
    case noResults
    case typeMismatch(expected: String, actual: String, field: String?)
    case decodingFailed(field: String, underlyingError: Error)
    case invalidValue(field: String, valueDescription: String)
    case missingRequiredField(String)
    case nullValueForNonOptionalType(field: String, type: String)
    case columnIndexOutOfBounds(index: Int, columnCount: Int)
    case columnNotFound(column: String)
    
    public var errorDescription: String? {
        switch self {
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
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .noResults:
            return "The query returned no results"
            
        case .typeMismatch:
            return "The value type doesn't match the expected Swift type"
            
        case .decodingFailed:
            return "Failed to decode the value using the specified decoder"
            
        case .invalidValue:
            return "The value doesn't meet the requirements for the target type"
            
        case .missingRequiredField:
            return "A required field was not found in the query result"
            
        case .nullValueForNonOptionalType:
            return "Attempted to map a null value to a non-optional type"
            
        case .columnIndexOutOfBounds:
            return "The specified column index doesn't exist in the result"
            
        case .columnNotFound:
            return "The specified column name doesn't exist in the result"
        }
    }
}