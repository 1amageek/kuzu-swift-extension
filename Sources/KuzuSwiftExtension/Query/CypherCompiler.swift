import Foundation

public struct CypherCompiler {
    public struct CompiledQuery {
        public let query: String
        public let parameters: [String: any Sendable]
    }
    
    public static func compile(_ query: Query) throws -> CompiledQuery {
        var cypherFragments: [CypherFragment] = []
        var allParameters: [String: any Sendable] = [:]
        
        // Process each component in order
        for component in query.components {
            let fragment = try component.toCypher()
            cypherFragments.append(fragment)
            
            // Merge parameters, checking for conflicts
            for (key, value) in fragment.parameters {
                if let existingValue = allParameters[key] {
                    // Can't directly compare existential types, so just check if key exists
                    throw QueryError.compilationFailed(
                        query: fragment.query,
                        reason: "Parameter conflict: '\(key)' is already defined"
                    )
                } else {
                    allParameters[key] = value
                }
            }
        }
        
        // Join fragments with spaces
        let compiledQuery = cypherFragments
            .map { $0.query }
            .joined(separator: " ")
        
        return CompiledQuery(
            query: compiledQuery,
            parameters: allParameters
        )
    }
}