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
}