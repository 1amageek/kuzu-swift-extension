import Foundation

public struct CypherCompiler {
    public static func compile(_ query: Query) throws -> CypherFragment {
        var cypherFragments: [CypherFragment] = []
        var allParameters: [String: any Sendable] = [:]
        
        // Process each component in order
        for component in query.components {
            let fragment = try component.toCypher()
            cypherFragments.append(fragment)
            
            // Merge parameters with smart collision detection
            for (key, value) in fragment.parameters {
                if let existingValue = allParameters[key] {
                    // Try to compare values - if they're the same, it's OK to reuse the parameter
                    if !areValuesEqual(existingValue, value) {
                        throw QueryError.compilationFailed(
                            query: fragment.query,
                            reason: "Parameter conflict: '\(key)' has different values - existing: \(String(describing: existingValue)), new: \(String(describing: value))"
                        )
                    }
                    // Same parameter name with same value - continue without error
                } else {
                    allParameters[key] = value
                }
            }
        }
        
        // Join fragments with spaces
        let compiledQuery = cypherFragments
            .map { $0.query }
            .joined(separator: " ")
        
        return CypherFragment(
            query: compiledQuery,
            parameters: allParameters
        )
    }
    
    // Helper function to compare parameter values
    private static func areValuesEqual(_ lhs: any Sendable, _ rhs: any Sendable) -> Bool {
        // First try to convert to AnyHashable for comparison
        if let lhsHashable = lhs as? AnyHashable,
           let rhsHashable = rhs as? AnyHashable {
            return lhsHashable == rhsHashable
        }
        
        // For types that can't be directly compared, convert to string representation
        // This is a fallback that ensures we at least have some comparison
        let lhsString = String(describing: lhs)
        let rhsString = String(describing: rhs)
        
        return lhsString == rhsString
    }
}