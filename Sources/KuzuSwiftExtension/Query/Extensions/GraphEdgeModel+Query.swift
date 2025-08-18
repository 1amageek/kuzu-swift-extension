import Foundation

// MARK: - GraphEdgeModel Extensions for Query DSL

public extension GraphEdgeModel {
    
    /// Create an edge builder starting from a source node
    static func from<From: GraphNodeModel>(_ source: NodeReference<From>) -> NewEdgeBuilder<Self, From> {
        NewEdgeBuilder<Self, From>(from: source)
    }
    
    /// Create an edge directly between two nodes
    static func between<From: GraphNodeModel, To: GraphNodeModel>(
        from source: NodeReference<From>,
        to target: NodeReference<To>
    ) -> EdgeReference<Self> {
        EdgeReference<Self>(from: source, to: target)
    }
    
    /// Create an optional edge
    static func optional<From: GraphNodeModel, To: GraphNodeModel>(
        from source: NodeReference<From>,
        to target: NodeReference<To>
    ) -> EdgeReference<Self> {
        EdgeReference<Self>(from: source, to: target, isOptional: true)
    }
    
    /// Create a new edge
    static func create<From: GraphNodeModel, To: GraphNodeModel>(
        from source: NodeReference<From>,
        to target: NodeReference<To>,
        properties: [String: any Sendable] = [:]
    ) -> CreateEdge<Self> {
        CreateEdge<Self>(from: source, to: target, properties: properties)
    }
    
    /// Create a new edge from an instance
    static func create<From: GraphNodeModel, To: GraphNodeModel>(
        from source: NodeReference<From>,
        to target: NodeReference<To>,
        _ instance: Self
    ) throws -> CreateEdge<Self> where Self: Encodable {
        let encoder = KuzuEncoder()
        let properties = try encoder.encode(instance)
        return CreateEdge<Self>(from: source, to: target, properties: properties)
    }
    
    /// Match edges of this type
    static func match() -> EdgeMatchBuilder<Self> {
        EdgeMatchBuilder<Self>()
    }
    
    /// Merge (upsert) an edge
    static func merge<From: GraphNodeModel, To: GraphNodeModel>(
        from source: NodeReference<From>,
        to target: NodeReference<To>,
        matching properties: [String: any Sendable] = [:]
    ) -> MergeEdge<Self> {
        MergeEdge<Self>(from: source, to: target, matchProperties: properties)
    }
}

// MARK: - Edge Match Builder

public struct EdgeMatchBuilder<Model: GraphEdgeModel> {
    let predicate: Predicate?
    let isOptional: Bool
    
    init(predicate: Predicate? = nil, isOptional: Bool = false) {
        self.predicate = predicate
        self.isOptional = isOptional
    }
    
    /// Add a WHERE condition
    public func `where`(_ predicate: Predicate) -> EdgeMatchBuilder {
        let combined = self.predicate.map { $0.and(predicate) } ?? predicate
        return EdgeMatchBuilder(predicate: combined, isOptional: isOptional)
    }
    
    /// Make this an optional match
    public func optional() -> EdgeMatchBuilder {
        EdgeMatchBuilder(predicate: predicate, isOptional: true)
    }
    
    /// Specify the source and target nodes
    public func from<From: GraphNodeModel>(_ source: NodeReference<From>) -> EdgeBuilderWithPredicate<Model, From> {
        EdgeBuilderWithPredicate(from: source, predicate: predicate, isOptional: isOptional)
    }
}

// MARK: - Edge Builder with Predicate

public struct EdgeBuilderWithPredicate<Model: GraphEdgeModel, From: GraphNodeModel> {
    let from: NodeReference<From>
    let predicate: Predicate?
    let isOptional: Bool
    
    /// Specify the target node
    public func to<To: GraphNodeModel>(_ target: NodeReference<To>) -> EdgeReference<Model> {
        EdgeReference<Model>(from: from, to: target, predicate: predicate, isOptional: isOptional)
    }
}

// MARK: - Merge Edge Operation

public struct MergeEdge<Model: GraphEdgeModel>: QueryComponent {
    public typealias Result = Model
    
    let from: any AliasedComponent
    let to: any AliasedComponent
    let matchProperties: [String: any Sendable]
    let onCreateProperties: [String: any Sendable]
    let onMatchProperties: [String: any Sendable]
    let alias: String
    
    init(from: any AliasedComponent,
         to: any AliasedComponent,
         matchProperties: [String: any Sendable],
         onCreateProperties: [String: any Sendable] = [:],
         onMatchProperties: [String: any Sendable] = [:],
         alias: String? = nil) {
        self.from = from
        self.to = to
        self.matchProperties = matchProperties
        self.onCreateProperties = onCreateProperties
        self.onMatchProperties = onMatchProperties
        self.alias = alias ?? AliasGenerator.generate(for: Model.self)
    }
    
    /// Add ON CREATE SET properties
    public func onCreate(set properties: [String: any Sendable]) -> MergeEdge {
        MergeEdge(
            from: from,
            to: to,
            matchProperties: matchProperties,
            onCreateProperties: properties,
            onMatchProperties: onMatchProperties,
            alias: alias
        )
    }
    
    /// Add ON MATCH SET properties
    public func onMatch(set properties: [String: any Sendable]) -> MergeEdge {
        MergeEdge(
            from: from,
            to: to,
            matchProperties: matchProperties,
            onCreateProperties: onCreateProperties,
            onMatchProperties: properties,
            alias: alias
        )
    }
    
    public func toCypher() throws -> CypherFragment {
        let typeName = String(describing: Model.self)
        var parameters: [String: any Sendable] = [:]
        var query = "MERGE (\(from.alias))-[\(alias):\(typeName)"
        
        // Add match properties
        if !matchProperties.isEmpty {
            var propStrings: [String] = []
            for (key, value) in matchProperties {
                let paramName = OptimizedParameterGenerator.semantic(alias: "\(alias)_match", property: key)
                parameters[paramName] = value
                propStrings.append("\(key): $\(paramName)")
            }
            query += " {\(propStrings.joined(separator: ", "))}"
        }
        query += "]->(\(to.alias))"
        
        // Add ON CREATE SET
        if !onCreateProperties.isEmpty {
            var propStrings: [String] = []
            for (key, value) in onCreateProperties {
                let paramName = OptimizedParameterGenerator.semantic(alias: "\(alias)_create", property: key)
                parameters[paramName] = value
                
                // Check if this is a timestamp property
                let columns = Model._kuzuColumns
                let columnInfo = columns.first { $0.name == key }
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
        if !onMatchProperties.isEmpty {
            var propStrings: [String] = []
            for (key, value) in onMatchProperties {
                let paramName = OptimizedParameterGenerator.semantic(alias: "\(alias)_match_set", property: key)
                parameters[paramName] = value
                
                // Check if this is a timestamp property
                let columns = Model._kuzuColumns
                let columnInfo = columns.first { $0.name == key }
                let columnType = columnInfo?.type ?? ""
                
                if columnType == "TIMESTAMP" {
                    propStrings.append("\(alias).\(key) = timestamp($\(paramName))")
                } else {
                    propStrings.append("\(alias).\(key) = $\(paramName)")
                }
            }
            query += " ON MATCH SET \(propStrings.joined(separator: ", "))"
        }
        
        return CypherFragment(query: query, parameters: parameters)
    }
}