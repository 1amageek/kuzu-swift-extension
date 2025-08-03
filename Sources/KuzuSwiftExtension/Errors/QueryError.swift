import Foundation

public enum QueryError: LocalizedError {
    case compileFailure(message: String, location: String?)
    case executionFailed(cypher: String, underlying: Error)
    case bindingTypeMismatch(parameter: String, expected: String, actual: String)
    
    public var errorDescription: String? {
        switch self {
        case .compileFailure(let message, let location):
            return "Query compilation failed: \(message) at \(location ?? "unknown")"
        case .executionFailed(let cypher, let error):
            return "Query execution failed for: \(cypher), Error: \(error)"
        case .bindingTypeMismatch(let param, let expected, let actual):
            return "Type mismatch for parameter \(param): expected \(expected), got \(actual)"
        }
    }
}