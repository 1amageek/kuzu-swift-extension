import Foundation

public enum GraphError: LocalizedError {
    case schemaMigrationFailed(sql: String, underlying: Error)
    case destructiveMigrationBlocked(table: String, column: String?)
    case connectionFailed(Error)
    case invalidConfiguration(String)
    
    public var errorDescription: String? {
        switch self {
        case .schemaMigrationFailed(let sql, let error):
            return "Schema migration failed for SQL: \(sql), Error: \(error)"
        case .destructiveMigrationBlocked(let table, let column):
            return "Destructive migration blocked for table: \(table), column: \(column ?? "N/A")"
        case .connectionFailed(let error):
            return "Database connection failed: \(error)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        }
    }
}