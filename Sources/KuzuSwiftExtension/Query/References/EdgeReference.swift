import Foundation

/// A reference to an edge in a graph query
public struct EdgeReference<Model: GraphEdgeModel>: AliasedComponent {
    public typealias Result = Void
    
    public let alias: String
    public let from: any AliasedComponent
    public let to: any AliasedComponent
    public let predicate: Predicate?
    public let isOptional: Bool
    public var isReturnable: Bool { false } // Edges are typically not returned
    
    /// Create a new edge reference
    public init(from: any AliasedComponent, to: any AliasedComponent, alias: String? = nil, predicate: Predicate? = nil, isOptional: Bool = false) {
        self.alias = alias ?? AliasGenerator.generate(for: Model.self)
        self.from = from
        self.to = to
        self.predicate = predicate
        self.isOptional = isOptional
    }
    
    /// Add a WHERE condition
    public func `where`(_ predicate: Predicate) -> EdgeReference {
        let combined = self.predicate.map { $0.and(predicate) } ?? predicate
        return EdgeReference(from: from, to: to, alias: alias, predicate: combined, isOptional: isOptional)
    }
    
    /// Add a WHERE condition using property comparison
    public func `where`<Value: Sendable>(_ property: String, _ op: ComparisonOperator, _ value: Value) -> EdgeReference {
        let propRef = PropertyReference(alias: alias, property: property)
        let comparison = ComparisonExpression(lhs: propRef, op: op, rhs: .value(value))
        let predicate = Predicate(node: .comparison(comparison))
        return self.where(predicate)
    }
    
    /// Set property values on the edge
    public func set(_ property: String, to value: any Sendable) -> SetOperation<Model> {
        SetOperation(edge: self, property: property, value: value)
    }
    
    /// Delete this edge
    public func delete() -> DeleteOperation<Model> {
        DeleteOperation(edge: self)
    }
    
    // MARK: - Cypher Generation
    
    public func toCypher() throws -> CypherFragment {
        let typeName = String(describing: Model.self)
        let fromAlias = from.alias
        let toAlias = to.alias
        var query = ""
        var parameters: [String: any Sendable] = [:]
        
        // Generate MATCH or OPTIONAL MATCH for the edge
        if isOptional {
            query = "OPTIONAL MATCH (\(fromAlias))-[\(alias):\(typeName)]->(\(toAlias))"
        } else {
            query = "MATCH (\(fromAlias))-[\(alias):\(typeName)]->(\(toAlias))"
        }
        
        // Add WHERE clause if predicate exists
        if let predicate = predicate {
            let predicateCypher = try predicate.toCypher()
            query += " WHERE \(predicateCypher.query)"
            parameters.merge(predicateCypher.parameters) { _, new in new }
        }
        
        return CypherFragment(query: query, parameters: parameters)
    }
}

// MARK: - New Edge Builder

/// Builder for creating edge references with fluent API
public struct NewEdgeBuilder<Model: GraphEdgeModel, From: GraphNodeModel> {
    let from: NodeReference<From>
    let alias: String?
    let predicate: Predicate?
    let isOptional: Bool
    
    public init(from: NodeReference<From>, alias: String? = nil, predicate: Predicate? = nil, isOptional: Bool = false) {
        self.from = from
        self.alias = alias
        self.predicate = predicate
        self.isOptional = isOptional
    }
    
    /// Specify the target node
    public func to<To: GraphNodeModel>(_ target: NodeReference<To>) -> EdgeReference<Model> {
        EdgeReference(from: from, to: target, alias: alias, predicate: predicate, isOptional: isOptional)
    }
}

// MARK: - Edge Operations

/// Set operation on an edge
public struct SetOperation<Model: GraphEdgeModel>: QueryComponent {
    public typealias Result = Void
    public var isReturnable: Bool { false }
    
    let edge: EdgeReference<Model>
    let property: String
    let value: any Sendable
    
    public func toCypher() throws -> CypherFragment {
        let paramName = OptimizedParameterGenerator.semantic(alias: edge.alias, property: property)
        return CypherFragment(
            query: "SET \(edge.alias).\(property) = $\(paramName)",
            parameters: [paramName: value]
        )
    }
}

/// Delete operation on an edge
public struct DeleteOperation<Model: GraphEdgeModel>: QueryComponent {
    public typealias Result = Void
    public var isReturnable: Bool { false }
    
    let edge: EdgeReference<Model>
    
    public func toCypher() throws -> CypherFragment {
        CypherFragment(query: "DELETE \(edge.alias)")
    }
}

// MARK: - Create Edge Operation

/// Create edge operation
public struct CreateEdge<Model: GraphEdgeModel>: QueryComponent {
    public typealias Result = Model
    
    let from: any AliasedComponent
    let to: any AliasedComponent
    let properties: [String: any Sendable]
    let alias: String
    
    public init(from: any AliasedComponent, to: any AliasedComponent, properties: [String: any Sendable] = [:], alias: String? = nil) {
        self.from = from
        self.to = to
        self.properties = properties
        self.alias = alias ?? AliasGenerator.generate(for: Model.self)
    }
    
    public func toCypher() throws -> CypherFragment {
        let typeName = String(describing: Model.self)
        var parameters: [String: any Sendable] = [:]
        var propStrings: [String] = []
        
        for (key, value) in properties {
            let paramName = OptimizedParameterGenerator.semantic(alias: alias, property: key)
            parameters[paramName] = value
            propStrings.append("\(key): $\(paramName)")
        }
        
        let propsClause = propStrings.isEmpty ? "" : " {\(propStrings.joined(separator: ", "))}"
        let query = "CREATE (\(from.alias))-[\(alias):\(typeName)\(propsClause)]->(\(to.alias))"
        
        return CypherFragment(query: query, parameters: parameters)
    }
}