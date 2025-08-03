import Foundation

public struct CypherCompiler {
    public struct CompiledQuery {
        public let query: String
        public let parameters: SendableParameters
    }
    
    public static func compile(_ query: Query) throws -> CompiledQuery {
        var cypherFragments: [CypherFragment] = []
        var allParameters: SendableParameters = [:]
        
        // Process each component in order
        for component in query.components {
            let fragment = try component.toCypher()
            cypherFragments.append(fragment)
            
            // Convert and merge parameters
            let convertedParams = try ParameterConverter.convert(fragment.parameters)
            
            // Merge parameters, checking for conflicts
            for (key, value) in convertedParams {
                if let existingValue = allParameters[key] {
                    // ParameterValue is Equatable, so we can compare directly
                    if existingValue != value {
                        throw QueryError.compilationFailed(
                            query: fragment.query,
                            reason: "Parameter conflict: '\(key)' has different values"
                        )
                    }
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