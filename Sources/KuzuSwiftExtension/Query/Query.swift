import Foundation

public struct Query {
    internal let components: [QueryComponent]
    
    internal init(components: [QueryComponent]) {
        self.components = components
    }
}

public protocol QueryComponent {
    func toCypher() throws -> CypherFragment
}

public struct CypherFragment: Sendable {
    let query: String
    let parameters: [String: any Encodable & Sendable]
    
    init(query: String, parameters: [String: any Encodable & Sendable] = [:]) {
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