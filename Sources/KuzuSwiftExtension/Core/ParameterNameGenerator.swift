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
            return "\(alias)_\(property)"
            
        case .uuid(let prefix):
            let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            return "\(prefix)_\(uuid)"
        }
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