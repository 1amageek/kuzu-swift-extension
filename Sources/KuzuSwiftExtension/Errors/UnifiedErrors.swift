import Foundation

/// Unified error type for all Kuzu operations
public enum KuzuError: LocalizedError {
    // MARK: - Connection & Infrastructure
    case connectionFailed(reason: String)
    case databaseNotFound(path: String)
    case databaseInitializationFailed(String)
    case invalidConfiguration(message: String)
    case connectionPoolExhausted
    case connectionTimeout(duration: TimeInterval)
    case transactionFailed(reason: String)
    case migrationFailed(reason: String)
    case resourceCleanupFailed(reason: String)
    case contextNotAvailable(reason: String)
    case wrapped(underlyingError: Error)
    case kuzuError(error: Error, query: String?)

    // MARK: - Schema Management
    case indexCreationFailed(table: String, index: String, reason: String)
    
    // MARK: - Model Operations
    case missingIdentifier
    case invalidOperation(message: String)
    case conversionFailed(from: String, to: String)
    
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
        // Connection & Infrastructure
        case .connectionFailed(let reason):
            return "Failed to connect to database: \(reason)"
        case .databaseNotFound(let path):
            return "Database not found at path: \(path)"
        case .databaseInitializationFailed(let message):
            return "Database initialization failed: \(message)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .connectionPoolExhausted:
            return "Connection pool exhausted. All connections are in use."
        case .connectionTimeout(let duration):
            return "Connection request timed out after \(duration) seconds"
        case .transactionFailed(let reason):
            return "Transaction failed: \(reason)"
        case .migrationFailed(let reason):
            return "Migration failed: \(reason)"
        case .resourceCleanupFailed(let reason):
            return "Failed to cleanup resources: \(reason)"
        case .contextNotAvailable(let reason):
            return "Database context not available: \(reason)"
        case .wrapped(let underlyingError):
            return "Error: \(underlyingError.localizedDescription)"
        case .kuzuError(let error, let query):
            let queryInfo = query.map { " (Query: \($0))" } ?? ""
            return "Kuzu database error: \(error.localizedDescription)\(queryInfo)"
            
        // Model Operations
        case .missingIdentifier:
            return "Node model is missing an identifier (id property)"
        case .invalidOperation(let message):
            return "Invalid operation: \(message)"
        case .conversionFailed(let from, let to):
            return "Failed to convert value from type '\(from)' to type '\(to)'"
            
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
            
        // Schema Management
        case .indexCreationFailed(let table, let index, let reason):
            return "Failed to create index '\(index)' on table '\(table)': \(reason)"

        // Schema & Constraints
        case .missingRequiredProperty(let property):
            return "Missing required property: \(property)"
        case .constraintViolation(let constraint):
            return "Constraint violation: \(constraint)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        // Connection & Infrastructure
        case .connectionFailed:
            return "Check database path and permissions"
        case .databaseNotFound:
            return "Ensure the database file exists or use ':memory:' for in-memory database"
        case .databaseInitializationFailed:
            return "Check database path, permissions, and ensure no corrupted database files exist. The database may need to be removed and recreated."
        case .invalidConfiguration:
            return "Review your GraphConfiguration settings"
        case .connectionPoolExhausted:
            return "Increase maxConnections in configuration or wait for connections to be released"
        case .connectionTimeout:
            return "Increase connectionTimeout in configuration or reduce concurrent operations"
        case .transactionFailed:
            return "Check for concurrent modifications or constraint violations"
        case .migrationFailed:
            return "Review migration policy and schema compatibility"
        case .resourceCleanupFailed:
            return "Check for resource leaks and ensure proper connection management"
        case .contextNotAvailable:
            return "Restart the application or create a new test context"
        case .wrapped:
            return "Check the underlying error for more details"
        case .kuzuError:
            return "Review the query syntax and ensure the database schema is correct"
            
        // Model Operations
        case .missingIdentifier:
            return "Ensure the model has an @ID property"
        case .invalidOperation:
            return "Review the operation parameters and requirements"
        case .conversionFailed:
            return "Ensure the value types are compatible or implement proper type conversion"
            
        // Query Compilation
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
        case .indexCreationFailed:
            return "Ensure the table exists, column type is correct for the index type, and no conflicting indexes exist"
        }
    }
}

// MARK: - Compatibility Type Aliases

/// Compatibility alias for GraphError
public typealias GraphError = KuzuError

/// Compatibility alias for QueryError
public typealias QueryError = KuzuError

/// Compatibility alias for ResultMappingError
public typealias ResultMappingError = KuzuError