import Foundation

// MARK: - GraphNodeModel Extensions for Query DSL

public extension GraphNodeModel {
    
    /// Match nodes of this type
    static func match() -> NodeReference<Self> where Self: Decodable {
        NodeReference<Self>()
    }
    
    /// Match nodes with a WHERE condition using KeyPath
    static func `where`<Value: Sendable>(_ keyPath: KeyPath<Self, Value>, _ op: ComparisonOperator, _ value: Value) -> NodeReference<Self> where Self: Decodable {
        let nodeRef = NodeReference<Self>()
        return nodeRef.where(keyPath, op, value)
    }
    
    /// Match nodes with a WHERE condition using comparison tuple
    static func `where`<Value: Equatable & Sendable>(_ comparison: (KeyPath<Self, Value>, ComparisonOperator, Value)) -> NodeReference<Self> where Self: Decodable {
        let (keyPath, op, value) = comparison
        return Self.where(keyPath, op, value)
    }
    
    /// Match nodes with a custom predicate
    static func `where`(_ predicate: (PropertyProxy<Self>) -> Predicate) -> NodeReference<Self> where Self: Decodable {
        let proxy = PropertyProxy<Self>()
        let pred = predicate(proxy)
        return NodeReference<Self>(predicate: pred)
    }
    
    /// Create a new node with properties
    static func create(_ properties: [String: any Sendable] = [:]) -> CreateNode<Self> {
        CreateNode<Self>(properties: properties)
    }
    
    /// Create a new node from an instance
    static func create(_ instance: Self) throws -> CreateNode<Self> where Self: Encodable {
        let encoder = KuzuEncoder()
        let properties = try encoder.encode(instance)
        return CreateNode<Self>(properties: properties)
    }
    
    /// Merge (upsert) a node
    static func merge(on keyPath: KeyPath<Self, some Equatable>, equals value: any Sendable) -> MergeNode<Self> {
        let columnName = KeyPathUtilities.columnName(from: keyPath)
        return MergeNode<Self>(matchProperties: [columnName: value])
    }
    
    /// Merge (upsert) a node with multiple match properties
    static func merge(matching properties: [String: any Sendable]) -> MergeNode<Self> {
        MergeNode<Self>(matchProperties: properties)
    }
    
    /// Optional match for nodes
    static func optional() -> NodeReference<Self> where Self: Decodable {
        NodeReference<Self>(isOptional: true)
    }
    
    /// Optional match with WHERE condition
    static func optional<Value: Sendable>(where keyPath: KeyPath<Self, Value>, _ op: ComparisonOperator, _ value: Value) -> NodeReference<Self> where Self: Decodable {
        let nodeRef = NodeReference<Self>(isOptional: true)
        return nodeRef.where(keyPath, op, value)
    }
}

// MARK: - Property Proxy for type-safe property access

@dynamicMemberLookup
public struct PropertyProxy<Model> {
    public init() {}
    
    public subscript<Value>(dynamicMember keyPath: KeyPath<Model, Value>) -> PropertyExpression<Model, Value> {
        PropertyExpression(keyPath: keyPath)
    }
}

// MARK: - Property Expression

public struct PropertyExpression<Model, Value> {
    let keyPath: KeyPath<Model, Value>
    
    init(keyPath: KeyPath<Model, Value>) {
        self.keyPath = keyPath
    }
    
    /// Generate a property reference for a given alias
    func toPropertyReference(alias: String) -> PropertyReference {
        let propertyName = String(describing: keyPath).components(separatedBy: ".").last ?? ""
        return PropertyReference(alias: alias, property: propertyName)
    }
}

// MARK: - Comparison operators for PropertyExpression

public extension PropertyExpression where Value: Equatable & Sendable {
    static func == (lhs: PropertyExpression, rhs: Value) -> Predicate {
        let propRef = lhs.toPropertyReference(alias: "temp")
        let comparison = ComparisonExpression(lhs: propRef, op: .equal, rhs: .value(rhs))
        return Predicate(node: .comparison(comparison))
    }
    
    static func != (lhs: PropertyExpression, rhs: Value) -> Predicate {
        let propRef = lhs.toPropertyReference(alias: "temp")
        let comparison = ComparisonExpression(lhs: propRef, op: .notEqual, rhs: .value(rhs))
        return Predicate(node: .comparison(comparison))
    }
}

public extension PropertyExpression where Value: Comparable & Sendable {
    static func < (lhs: PropertyExpression, rhs: Value) -> Predicate {
        let propRef = lhs.toPropertyReference(alias: "temp")
        let comparison = ComparisonExpression(lhs: propRef, op: .lessThan, rhs: .value(rhs))
        return Predicate(node: .comparison(comparison))
    }
    
    static func <= (lhs: PropertyExpression, rhs: Value) -> Predicate {
        let propRef = lhs.toPropertyReference(alias: "temp")
        let comparison = ComparisonExpression(lhs: propRef, op: .lessThanOrEqual, rhs: .value(rhs))
        return Predicate(node: .comparison(comparison))
    }
    
    static func > (lhs: PropertyExpression, rhs: Value) -> Predicate {
        let propRef = lhs.toPropertyReference(alias: "temp")
        let comparison = ComparisonExpression(lhs: propRef, op: .greaterThan, rhs: .value(rhs))
        return Predicate(node: .comparison(comparison))
    }
    
    static func >= (lhs: PropertyExpression, rhs: Value) -> Predicate {
        let propRef = lhs.toPropertyReference(alias: "temp")
        let comparison = ComparisonExpression(lhs: propRef, op: .greaterThanOrEqual, rhs: .value(rhs))
        return Predicate(node: .comparison(comparison))
    }
}

// MARK: - Create Node Operation

public struct CreateNode<Model: GraphNodeModel>: QueryComponent {
    public typealias Result = Model
    
    let properties: [String: any Sendable]
    let alias: String
    
    init(properties: [String: any Sendable], alias: String? = nil) {
        self.properties = properties
        self.alias = alias ?? AliasGenerator.generate(for: Model.self)
    }
    
    public func toCypher() throws -> CypherFragment {
        let typeName = String(describing: Model.self)
        var parameters: [String: any Sendable] = [:]
        var propStrings: [String] = []
        
        // Handle timestamp properties specially
        let columns = Model._kuzuColumns
        
        for (key, value) in properties {
            let paramName = OptimizedParameterGenerator.semantic(alias: alias, property: key)
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
        
        let propsClause = propStrings.isEmpty ? "" : " {\(propStrings.joined(separator: ", "))}"
        let query = "CREATE (\(alias):\(typeName)\(propsClause))"
        
        return CypherFragment(query: query, parameters: parameters)
    }
}

// MARK: - Merge Node Operation

public struct MergeNode<Model: GraphNodeModel>: QueryComponent {
    public typealias Result = Model
    
    let matchProperties: [String: any Sendable]
    let onCreateProperties: [String: any Sendable]
    let onMatchProperties: [String: any Sendable]
    let alias: String
    
    init(matchProperties: [String: any Sendable], 
         onCreateProperties: [String: any Sendable] = [:],
         onMatchProperties: [String: any Sendable] = [:],
         alias: String? = nil) {
        self.matchProperties = matchProperties
        self.onCreateProperties = onCreateProperties
        self.onMatchProperties = onMatchProperties
        self.alias = alias ?? AliasGenerator.generate(for: Model.self)
    }
    
    /// Add ON CREATE SET properties
    public func onCreate(_ builder: (inout Model) -> Void) -> MergeNode where Model: Encodable {
        // This would require creating a mutable instance, which is complex
        // For now, use property dictionary
        return self
    }
    
    /// Add ON CREATE SET properties using dictionary
    public func onCreate(set properties: [String: any Sendable]) -> MergeNode {
        MergeNode(
            matchProperties: matchProperties,
            onCreateProperties: properties,
            onMatchProperties: onMatchProperties,
            alias: alias
        )
    }
    
    /// Add ON MATCH SET properties using dictionary
    public func onMatch(set properties: [String: any Sendable]) -> MergeNode {
        MergeNode(
            matchProperties: matchProperties,
            onCreateProperties: onCreateProperties,
            onMatchProperties: properties,
            alias: alias
        )
    }
    
    public func toCypher() throws -> CypherFragment {
        let typeName = String(describing: Model.self)
        var parameters: [String: any Sendable] = [:]
        var query = "MERGE (\(alias):\(typeName)"
        
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
        query += ")"
        
        // Add ON CREATE SET
        if !onCreateProperties.isEmpty {
            var propStrings: [String] = []
            for (key, value) in onCreateProperties {
                let paramName = OptimizedParameterGenerator.semantic(alias: "\(alias)_create", property: key)
                parameters[paramName] = value
                propStrings.append("\(alias).\(key) = $\(paramName)")
            }
            query += " ON CREATE SET \(propStrings.joined(separator: ", "))"
        }
        
        // Add ON MATCH SET
        if !onMatchProperties.isEmpty {
            var propStrings: [String] = []
            for (key, value) in onMatchProperties {
                let paramName = OptimizedParameterGenerator.semantic(alias: "\(alias)_match_set", property: key)
                parameters[paramName] = value
                propStrings.append("\(alias).\(key) = $\(paramName)")
            }
            query += " ON MATCH SET \(propStrings.joined(separator: ", "))"
        }
        
        return CypherFragment(query: query, parameters: parameters)
    }
}