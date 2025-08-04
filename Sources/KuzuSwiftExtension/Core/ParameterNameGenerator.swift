import Foundation

/// Generates parameter names for Cypher queries with different strategies
public struct ParameterNameGenerator {
    
    /// Strategy for generating parameter names
    public enum Strategy {
        /// Semantic naming using alias and property name (e.g., "person_name")
        case semantic(alias: String, property: String)
        
        /// UUID-based naming with optional prefix (e.g., "param_a1b2c3d4")
        case uuid(prefix: String = "param")
    }
    
    /// Generates a parameter name using the specified strategy
    public static func generate(using strategy: Strategy) -> String {
        switch strategy {
        case .semantic(let alias, let property):
            let sanitizedAlias = sanitizeName(alias)
            let sanitizedProperty = sanitizeName(property)
            return "\(sanitizedAlias)_\(sanitizedProperty)"
            
        case .uuid(let prefix):
            let sanitizedPrefix = sanitizeName(prefix)
            let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            return "\(sanitizedPrefix)_\(uuid)"
        }
    }
    
    /// Sanitizes a name by replacing non-alphanumeric characters with underscores
    private static func sanitizeName(_ name: String) -> String {
        // Replace any character that is not alphanumeric or underscore with an underscore
        let pattern = "[^a-zA-Z0-9_]"
        let sanitized = name.replacingOccurrences(
            of: pattern,
            with: "_",
            options: .regularExpression
        )
        
        // Ensure the name doesn't start with a number (prepend underscore if needed)
        if let firstChar = sanitized.first, firstChar.isNumber {
            return "_" + sanitized
        }
        
        // Return empty string as "param" if the result is empty
        return sanitized.isEmpty ? "param" : sanitized
    }
    
    /// Convenience method for generating UUID-based parameter names
    public static func generateUUID(prefix: String = "param") -> String {
        generate(using: .uuid(prefix: prefix))
    }
    
    /// Convenience method for generating semantic parameter names
    public static func generateSemantic(alias: String, property: String) -> String {
        generate(using: .semantic(alias: alias, property: property))
    }
}