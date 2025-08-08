import Foundation

/// Error handling strategy for query operations
public enum ErrorStrategy {
    case throwError
    case defaultValue(any Sendable)
    case logAndDefault(any Sendable)
}

/// Unified error handler for Query DSL operations
public struct QueryErrorHandler {
    
    /// Handle errors with a specified strategy
    public static func handle<T>(
        _ operation: () throws -> T,
        strategy: ErrorStrategy = .throwError,
        context: String = ""
    ) throws -> T {
        do {
            return try operation()
        } catch {
            switch strategy {
            case .throwError:
                throw error
                
            case .defaultValue(let value):
                guard let typedValue = value as? T else {
                    throw QueryError.compilationFailed(
                        query: context,
                        reason: "Default value type mismatch. Expected \(T.self), got \(type(of: value))"
                    )
                }
                return typedValue
                
            case .logAndDefault(let value):
                // Log the error for debugging
                #if DEBUG
                print("[QueryError] Context: \(context)")
                print("[QueryError] Error: \(error)")
                #endif
                
                guard let typedValue = value as? T else {
                    throw QueryError.compilationFailed(
                        query: context,
                        reason: "Default value type mismatch. Expected \(T.self), got \(type(of: value))"
                    )
                }
                return typedValue
            }
        }
    }
    
    /// Handle async operations with error strategy
    public static func handleAsync<T>(
        _ operation: () async throws -> T,
        strategy: ErrorStrategy = .throwError,
        context: String = ""
    ) async throws -> T {
        do {
            return try await operation()
        } catch {
            switch strategy {
            case .throwError:
                throw error
                
            case .defaultValue(let value):
                guard let typedValue = value as? T else {
                    throw QueryError.compilationFailed(
                        query: context,
                        reason: "Default value type mismatch. Expected \(T.self), got \(type(of: value))"
                    )
                }
                return typedValue
                
            case .logAndDefault(let value):
                #if DEBUG
                print("[QueryError] Context: \(context)")
                print("[QueryError] Error: \(error)")
                #endif
                
                guard let typedValue = value as? T else {
                    throw QueryError.compilationFailed(
                        query: context,
                        reason: "Default value type mismatch. Expected \(T.self), got \(type(of: value))"
                    )
                }
                return typedValue
            }
        }
    }
}

/// Extension for QueryError to support enhanced error handling
public extension QueryError {
    /// Subquery-specific errors
    enum SubqueryError: LocalizedError {
        case compilationFailed(reason: String)
        case builderFailed(context: String)
        case typeResolutionFailed(expectedType: String)
        
        public var errorDescription: String? {
            switch self {
            case .compilationFailed(let reason):
                return "Subquery compilation failed: \(reason)"
            case .builderFailed(let context):
                return "Query builder failed in context: \(context)"
            case .typeResolutionFailed(let expectedType):
                return "Failed to resolve type: \(expectedType)"
            }
        }
    }
    
    /// Create a subquery error
    static func subqueryFailed(reason: String) -> QueryError {
        return .compilationFailed(
            query: "Subquery",
            reason: reason
        )
    }
}