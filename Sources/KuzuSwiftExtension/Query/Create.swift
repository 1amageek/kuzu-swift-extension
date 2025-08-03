import Foundation

public struct Create<T: _KuzuGraphModel> {
    internal var clause: CreateClause
    
    public init(_ instance: T, as variable: String? = nil) {
        var properties: [String: Any] = [:]
        
        // Extract properties using Mirror
        let mirror = Mirror(reflecting: instance)
        for child in mirror.children {
            if let label = child.label {
                properties[label] = child.value
            }
        }
        
        self.clause = CreateClause(
            variable: variable,
            type: type(of: instance),
            properties: properties
        )
    }
    
    public init(_ type: T.Type, as variable: String? = nil, properties: [String: Any] = [:]) {
        self.clause = CreateClause(
            variable: variable,
            type: type,
            properties: properties
        )
    }
    
    internal init(clause: CreateClause) {
        self.clause = clause
    }
}