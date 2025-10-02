import Foundation

/// Internal utilities for KeyPath operations
internal struct KeyPathUtilities {
    /// Extracts the property name from a KeyPath string representation
    static func extractPropertyName(from keyPathString: String) -> String {
        // KeyPath string format is like: \TypeName.propertyName
        // We need to extract the property name after the last dot
        let components = keyPathString.components(separatedBy: ".")
        if let lastComponent = components.last {
            // Remove any trailing characters that might be added
            let cleanName = lastComponent
                .replacingOccurrences(of: ")", with: "")
                .replacingOccurrences(of: ">", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleanName
        }
        return keyPathString
    }

    /// Extracts property name from a PartialKeyPath
    static func propertyName<T>(from keyPath: PartialKeyPath<T>, on type: T.Type) -> String {
        let keyPathString = String(describing: keyPath)
        return extractPropertyName(from: keyPathString)
    }

    /// Converts a Swift property name to database column name using CodingKeys mapping
    /// - Parameters:
    ///   - keyPath: KeyPath to the property
    ///   - type: The GraphNodeModel type
    /// - Returns: The database column name (respects CodingKeys mapping)
    static func columnName<T: GraphNodeModel>(from keyPath: PartialKeyPath<T>) -> String {
        let propertyName = self.propertyName(from: keyPath, on: T.self)

        // Look up the column name in _kuzuColumns
        if let column = T._kuzuColumns.first(where: { $0.propertyName == propertyName }) {
            return column.columnName
        }

        // Fallback: if not found, assume property name == column name
        return propertyName
    }
}