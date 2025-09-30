import Foundation

/// Represents a Cypher query fragment with parameters and optional structure
public struct CypherFragment: Sendable {
    public let query: String
    public let parameters: [String: any Sendable]
    public let structure: QueryStructure?
    
    public init(
        query: String,
        parameters: [String: any Sendable] = [:],
        structure: QueryStructure? = nil
    ) {
        self.query = query
        self.parameters = parameters
        self.structure = structure
    }
    
    public func merged(with other: CypherFragment) -> CypherFragment {
        var mergedParams = parameters
        for (key, value) in other.parameters {
            mergedParams[key] = value
        }
        
        // If both have structures, use QueryCombiner to merge properly
        if structure != nil, other.structure != nil {
            let combiner = QueryCombiner()
            do {
                try combiner.add(self)
                try combiner.add(other)
                return try combiner.build()
            } catch {
                // Fallback to simple concatenation
                return CypherFragment(
                    query: query + " " + other.query,
                    parameters: mergedParams
                )
            }
        }
        
        return CypherFragment(
            query: query + " " + other.query,
            parameters: mergedParams,
            structure: structure ?? other.structure
        )
    }
}