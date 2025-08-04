import Foundation

public enum GraphError: LocalizedError {
    case connectionFailed(reason: String)
    case databaseNotFound(path: String)
    case invalidConfiguration(message: String)
    case connectionPoolExhausted
    case connectionTimeout(duration: TimeInterval)
    case transactionFailed(reason: String)
    case extensionLoadFailed(extension: String, reason: String)
    case migrationFailed(reason: String)
    case resourceCleanupFailed(reason: String)
    case wrapped(underlyingError: Error)
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return "Failed to connect to database: \(reason)"
        case .databaseNotFound(let path):
            return "Database not found at path: \(path)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .connectionPoolExhausted:
            return "Connection pool exhausted. All connections are in use."
        case .connectionTimeout(let duration):
            return "Connection request timed out after \(duration) seconds"
        case .transactionFailed(let reason):
            return "Transaction failed: \(reason)"
        case .extensionLoadFailed(let ext, let reason):
            return "Failed to load extension '\(ext)': \(reason)"
        case .migrationFailed(let reason):
            return "Migration failed: \(reason)"
        case .resourceCleanupFailed(let reason):
            return "Failed to cleanup resources: \(reason)"
        case .wrapped(let underlyingError):
            return "Error: \(underlyingError.localizedDescription)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .connectionFailed:
            return "Check database path and permissions"
        case .databaseNotFound:
            return "Ensure the database file exists or use ':memory:' for in-memory database"
        case .invalidConfiguration:
            return "Review your GraphConfiguration settings"
        case .connectionPoolExhausted:
            return "Increase maxConnections in configuration or wait for connections to be released"
        case .connectionTimeout:
            return "Increase connectionTimeout in configuration or reduce concurrent operations"
        case .transactionFailed:
            return "Check for concurrent modifications or constraint violations"
        case .extensionLoadFailed:
            return "Ensure the extension is properly installed and compatible"
        case .migrationFailed:
            return "Review migration policy and schema compatibility"
        case .resourceCleanupFailed:
            return "Check for resource leaks and ensure proper connection management"
        case .wrapped:
            return "Check the underlying error for more details"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .wrapped(let underlyingError):
            return (underlyingError as? LocalizedError)?.failureReason
        default:
            return nil
        }
    }
}