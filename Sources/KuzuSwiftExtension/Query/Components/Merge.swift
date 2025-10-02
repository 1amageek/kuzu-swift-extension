import Foundation

/// Standalone MERGE component for query DSL
public struct Merge: QueryComponent {
    public typealias Result = Void
    public var isReturnable: Bool { false }
    
    private let fragment: CypherFragment
    
    private init(fragment: CypherFragment) {
        self.fragment = fragment
    }
    
    /// Merge a node of the specified type
    public static func node<Model: GraphNodeModel>(
        _ type: Model.Type,
        matching: [String: any Sendable],
        onCreate: [String: any Sendable] = [:],
        onMatch: [String: any Sendable] = [:]
    ) -> Merge {
        let alias = AliasGenerator.generate(for: Model.self)
        let typeName = String(describing: Model.self)
        var parameters: [String: any Sendable] = [:]
        var query = "MERGE (\(alias):\(typeName)"
        
        // Handle timestamp properties specially
        let columns = Model._kuzuColumns
        
        // Add match properties
        if !matching.isEmpty {
            var propStrings: [String] = []
            for (key, value) in matching {
                let paramName = OptimizedParameterGenerator.semantic(alias: "\(alias)_match", property: key)
                parameters[paramName] = value
                
                // Check if this is a timestamp property
                let columnInfo = columns.first { $0.columnName == key }
                let columnType = columnInfo?.type ?? ""
                
                if columnType == "TIMESTAMP" {
                    propStrings.append("\(key): timestamp($\(paramName))")
                } else {
                    propStrings.append("\(key): $\(paramName)")
                }
            }
            query += " {\(propStrings.joined(separator: ", "))}"
        }
        query += ")"
        
        // Add ON CREATE SET
        if !onCreate.isEmpty {
            var propStrings: [String] = []
            for (key, value) in onCreate {
                let paramName = OptimizedParameterGenerator.semantic(alias: "\(alias)_create", property: key)
                parameters[paramName] = value
                
                // Check if this is a timestamp property
                let columnInfo = columns.first { $0.columnName == key }
                let columnType = columnInfo?.type ?? ""
                
                if columnType == "TIMESTAMP" {
                    propStrings.append("\(alias).\(key) = timestamp($\(paramName))")
                } else {
                    propStrings.append("\(alias).\(key) = $\(paramName)")
                }
            }
            query += " ON CREATE SET \(propStrings.joined(separator: ", "))"
        }
        
        // Add ON MATCH SET
        if !onMatch.isEmpty {
            var propStrings: [String] = []
            for (key, value) in onMatch {
                let paramName = OptimizedParameterGenerator.semantic(alias: "\(alias)_match_set", property: key)
                parameters[paramName] = value
                
                // Check if this is a timestamp property
                let columnInfo = columns.first { $0.columnName == key }
                let columnType = columnInfo?.type ?? ""
                
                if columnType == "TIMESTAMP" {
                    propStrings.append("\(alias).\(key) = timestamp($\(paramName))")
                } else {
                    propStrings.append("\(alias).\(key) = $\(paramName)")
                }
            }
            query += " ON MATCH SET \(propStrings.joined(separator: ", "))"
        }
        
        return Merge(fragment: CypherFragment(query: query, parameters: parameters))
    }
    
    /// Merge an edge between two nodes
    public static func edge<Edge: GraphEdgeModel, From: GraphNodeModel, To: GraphNodeModel>(
        _ type: Edge.Type,
        from: NodeReference<From>,
        to: NodeReference<To>,
        matching: [String: any Sendable] = [:],
        onCreate: [String: any Sendable] = [:],
        onMatch: [String: any Sendable] = [:]
    ) -> Merge {
        let alias = AliasGenerator.generate(for: Edge.self)
        let typeName = String(describing: Edge.self)
        var parameters: [String: any Sendable] = [:]
        var query = "MERGE (\(from.alias))-[\(alias):\(typeName)"
        
        // Handle timestamp properties specially
        let columns = Edge._kuzuColumns
        
        // Add match properties
        if !matching.isEmpty {
            var propStrings: [String] = []
            for (key, value) in matching {
                let paramName = OptimizedParameterGenerator.semantic(alias: "\(alias)_match", property: key)
                parameters[paramName] = value
                
                // Check if this is a timestamp property
                let columnInfo = columns.first { $0.columnName == key }
                let columnType = columnInfo?.type ?? ""
                
                if columnType == "TIMESTAMP" {
                    propStrings.append("\(key): timestamp($\(paramName))")
                } else {
                    propStrings.append("\(key): $\(paramName)")
                }
            }
            query += " {\(propStrings.joined(separator: ", "))}"
        }
        query += "]->(\(to.alias))"
        
        // Add ON CREATE SET
        if !onCreate.isEmpty {
            var propStrings: [String] = []
            for (key, value) in onCreate {
                let paramName = OptimizedParameterGenerator.semantic(alias: "\(alias)_create", property: key)
                parameters[paramName] = value
                
                // Check if this is a timestamp property
                let columnInfo = columns.first { $0.columnName == key }
                let columnType = columnInfo?.type ?? ""
                
                if columnType == "TIMESTAMP" {
                    propStrings.append("\(alias).\(key) = timestamp($\(paramName))")
                } else {
                    propStrings.append("\(alias).\(key) = $\(paramName)")
                }
            }
            query += " ON CREATE SET \(propStrings.joined(separator: ", "))"
        }
        
        // Add ON MATCH SET
        if !onMatch.isEmpty {
            var propStrings: [String] = []
            for (key, value) in onMatch {
                let paramName = OptimizedParameterGenerator.semantic(alias: "\(alias)_match_set", property: key)
                parameters[paramName] = value
                
                // Check if this is a timestamp property
                let columnInfo = columns.first { $0.columnName == key }
                let columnType = columnInfo?.type ?? ""
                
                if columnType == "TIMESTAMP" {
                    propStrings.append("\(alias).\(key) = timestamp($\(paramName))")
                } else {
                    propStrings.append("\(alias).\(key) = $\(paramName)")
                }
            }
            query += " ON MATCH SET \(propStrings.joined(separator: ", "))"
        }
        
        return Merge(fragment: CypherFragment(query: query, parameters: parameters))
    }
    
    public func toCypher() throws -> CypherFragment {
        fragment
    }
}