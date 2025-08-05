import Foundation

public struct Query {
    public let components: [QueryComponent]
    
    public init(components: [QueryComponent]) {
        self.components = components
    }
}

public protocol QueryComponent {
    func toCypher() throws -> CypherFragment
}

public struct CypherFragment {
    public let query: String
    public let parameters: [String: any Sendable]
    
    public init(query: String, parameters: [String: any Sendable] = [:]) {
        self.query = query
        self.parameters = parameters
    }
    
    func merged(with other: CypherFragment) -> CypherFragment {
        var mergedParams = parameters
        for (key, value) in other.parameters {
            mergedParams[key] = value
        }
        
        return CypherFragment(
            query: query + " " + other.query,
            parameters: mergedParams
        )
    }
}