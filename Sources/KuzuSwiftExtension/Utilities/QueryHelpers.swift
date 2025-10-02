import Foundation

/// Helper functions for query building
public enum QueryHelpers {
    
    /// Builds a property assignment string for a column, handling TIMESTAMP types
    /// - Parameters:
    ///   - columnName: The name of the column
    ///   - columnType: The type of the column
    ///   - parameterName: The parameter name to use in the query
    ///   - isAssignment: If true, generates "column = value" format; if false, generates "column: value" format
    /// - Returns: The formatted property assignment string
    public static func buildPropertyAssignment(
        columnName: String,
        columnType: String,
        parameterName: String,
        isAssignment: Bool = false
    ) -> String {
        let separator = isAssignment ? " = " : ": "
        
        if columnType == "TIMESTAMP" {
            return "\(columnName)\(separator)timestamp($\(parameterName))"
        } else {
            return "\(columnName)\(separator)$\(parameterName)"
        }
    }
    
    /// Builds property assignments for multiple columns
    /// - Parameters:
    ///   - columns: Array of column definitions
    ///   - parameterPrefix: Optional prefix for parameter names
    ///   - isAssignment: If true, generates "column = value" format; if false, generates "column: value" format
    /// - Returns: Array of formatted property assignment strings
    public static func buildPropertyAssignments(
        columns: [(propertyName: String, columnName: String, type: String, constraints: [String])],
        parameterPrefix: String = "",
        isAssignment: Bool = false
    ) -> [String] {
        columns.map { column in
            let paramName = parameterPrefix.isEmpty ? column.propertyName : "\(parameterPrefix)_\(column.propertyName)"
            return buildPropertyAssignment(
                columnName: column.columnName,
                columnType: column.type,
                parameterName: paramName,
                isAssignment: isAssignment
            )
        }
    }
}