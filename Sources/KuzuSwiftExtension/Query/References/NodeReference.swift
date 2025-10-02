import Foundation
import Kuzu

/// A reference to a node in a graph query
@dynamicMemberLookup
public struct NodeReference<Model: GraphNodeModel & Decodable>: AliasedComponent {
    public typealias Result = [Model]
    
    public let alias: String
    public let predicate: Predicate?
    public let isOptional: Bool
    private let operations: [NodeOperation]
    
    /// Create a new node reference
    public init(alias: String? = nil, predicate: Predicate? = nil, isOptional: Bool = false) {
        self.alias = alias ?? AliasGenerator.generate(for: Model.self)
        self.predicate = predicate
        self.isOptional = isOptional
        self.operations = []
    }
    
    private init(alias: String, predicate: Predicate?, isOptional: Bool, operations: [NodeOperation]) {
        self.alias = alias
        self.predicate = predicate
        self.isOptional = isOptional
        self.operations = operations
    }
    
    // MARK: - Property Access
    
    /// Dynamic member lookup for property access
    public subscript<Value>(dynamicMember keyPath: KeyPath<Model, Value>) -> PropertyReference {
        let columnName = KeyPathUtilities.columnName(from: keyPath)
        return PropertyReference(alias: alias, property: columnName)
    }
    
    // MARK: - Query Operations
    
    /// Add a WHERE condition
    public func `where`(_ predicate: Predicate) -> NodeReference {
        let combined = self.predicate.map { $0.and(predicate) } ?? predicate
        return NodeReference(alias: alias, predicate: combined, isOptional: isOptional, operations: operations)
    }
    
    /// Add a WHERE condition using KeyPath
    public func `where`<Value: Sendable>(_ keyPath: KeyPath<Model, Value>, _ op: ComparisonOperator, _ value: Value) -> NodeReference {
        let columnName = KeyPathUtilities.columnName(from: keyPath)
        let propRef = PropertyReference(alias: alias, property: columnName)
        let comparison = ComparisonExpression(lhs: propRef, op: op, rhs: .value(value))
        let predicate = Predicate(node: .comparison(comparison))
        return self.where(predicate)
    }
    
    /// Add ORDER BY clause
    public func orderBy<Value>(_ keyPath: KeyPath<Model, Value>, _ direction: SortDirection = .ascending) -> NodeReference {
        let columnName = KeyPathUtilities.columnName(from: keyPath)
        let operation = NodeOperation.orderBy(property: columnName, direction: direction)
        return NodeReference(alias: alias, predicate: predicate, isOptional: isOptional, operations: operations + [operation])
    }
    
    /// Add LIMIT clause
    public func limit(_ count: Int) -> NodeReference {
        let operation = NodeOperation.limit(count)
        return NodeReference(alias: alias, predicate: predicate, isOptional: isOptional, operations: operations + [operation])
    }
    
    /// Add SKIP clause
    public func skip(_ count: Int) -> NodeReference {
        let operation = NodeOperation.skip(count)
        return NodeReference(alias: alias, predicate: predicate, isOptional: isOptional, operations: operations + [operation])
    }
    
    /// Set property values
    public func set<Value: Sendable>(_ keyPath: KeyPath<Model, Value>, to value: Value) -> NodeReference {
        let columnName = KeyPathUtilities.columnName(from: keyPath)
        let operation = NodeOperation.set(property: columnName, value: value)
        return NodeReference(alias: alias, predicate: predicate, isOptional: isOptional, operations: operations + [operation])
    }
    
    /// Delete this node
    public func delete(detach: Bool = false) -> NodeReference {
        let operation = NodeOperation.delete(detach: detach)
        return NodeReference(alias: alias, predicate: predicate, isOptional: isOptional, operations: operations + [operation])
    }
    
    /// Add a HAVING clause (for aggregations)
    public func having(_ predicate: Predicate) -> NodeReference {
        let operation = NodeOperation.having(predicate)
        return NodeReference(alias: alias, predicate: predicate, isOptional: isOptional, operations: operations + [operation])
    }
    
    /// Check if a subquery exists
    public func whereExists(@QueryBuilder _ builder: () -> any QueryComponent) -> NodeReference {
        let subquery = builder()
        let operation = NodeOperation.whereExists(subquery)
        return NodeReference(alias: alias, predicate: predicate, isOptional: isOptional, operations: operations + [operation])
    }
    
    // MARK: - Aggregation Functions
    
    /// Count nodes
    public func count() -> Count<Model> {
        Count(nodeRef: self)
    }
    
    /// Average of a property
    public func average<Value: Numeric>(_ keyPath: KeyPath<Model, Value>) -> Average<Model, Value> {
        Average(nodeRef: self, keyPath: keyPath)
    }
    
    /// Sum of a property
    public func sum<Value: Numeric>(_ keyPath: KeyPath<Model, Value>) -> Sum<Model, Value> {
        Sum(self, keyPath: keyPath)
    }
    
    /// Minimum value of a property
    public func min<Value: Comparable>(_ keyPath: KeyPath<Model, Value>) -> Min<Model, Value> {
        Min(nodeRef: self, keyPath: keyPath)
    }
    
    /// Maximum value of a property
    public func max<Value: Comparable>(_ keyPath: KeyPath<Model, Value>) -> Max<Model, Value> {
        Max(nodeRef: self, keyPath: keyPath)
    }
    
    /// Collect nodes into an array
    public func collect() -> Collect<Model> {
        Collect(nodeRef: self)
    }
    
    // MARK: - Result Mapping
    
    public func mapResult(_ result: QueryResult, decoder: KuzuDecoder) throws -> Result {
        var nodes: [Model] = []
        
        // Get first row
        guard result.hasNext() else {
            return nodes
        }
        
        guard let row = try result.getNext() else {
            return nodes
        }
        
        // The first column should contain the collected nodes
        let value = try row.getValue(0)
        
        // Check if it's an array of nodes (from COLLECT)
        if let nodeArray = value as? [Any] {
            for item in nodeArray {
                if let kuzuNode = item as? KuzuNode {
                    let node = try decoder.decode(Model.self, from: kuzuNode.properties)
                    nodes.append(node)
                }
            }
        } else if let kuzuNode = value as? KuzuNode {
            // Single node result
            let node = try decoder.decode(Model.self, from: kuzuNode.properties)
            nodes.append(node)
            
            // Collect remaining nodes
            while result.hasNext() {
                guard let row = try result.getNext() else { continue }
                let val = try row.getValue(0)
                if let kuzuNode = val as? KuzuNode {
                    let node = try decoder.decode(Model.self, from: kuzuNode.properties)
                    nodes.append(node)
                }
            }
        }
        
        return nodes
    }
    
    // MARK: - Cypher Generation
    
    public func toCypher() throws -> CypherFragment {
        let typeName = String(describing: Model.self)
        var query = ""
        var parameters: [String: any Sendable] = [:]
        
        // Generate MATCH or OPTIONAL MATCH
        if isOptional {
            query = "OPTIONAL MATCH (\(alias):\(typeName))"
        } else {
            query = "MATCH (\(alias):\(typeName))"
        }
        
        // Add WHERE clause if predicate exists
        if let predicate = predicate {
            let predicateCypher = try predicate.toCypher()
            query += " WHERE \(predicateCypher.query)"
            parameters.merge(predicateCypher.parameters) { _, new in new }
        }
        
        // Apply operations
        for operation in operations {
            let opCypher = try operation.toCypher(alias: alias)
            if !opCypher.query.isEmpty {
                query += " \(opCypher.query)"
            }
            parameters.merge(opCypher.parameters) { _, new in new }
        }
        
        return CypherFragment(query: query, parameters: parameters)
    }
}

// MARK: - Node Operations

private enum NodeOperation {
    case orderBy(property: String, direction: SortDirection)
    case limit(Int)
    case skip(Int)
    case set(property: String, value: any Sendable)
    case delete(detach: Bool)
    case having(Predicate)
    case whereExists(any QueryComponent)
    
    func toCypher(alias: String) throws -> CypherFragment {
        switch self {
        case .orderBy(let property, let direction):
            let dir = direction == .ascending ? "ASC" : "DESC"
            return CypherFragment(query: "ORDER BY \(alias).\(property) \(dir)")
            
        case .limit(let count):
            return CypherFragment(query: "LIMIT \(count)")
            
        case .skip(let count):
            return CypherFragment(query: "SKIP \(count)")
            
        case .set(let property, let value):
            let paramName = OptimizedParameterGenerator.semantic(alias: alias, property: property)
            return CypherFragment(
                query: "SET \(alias).\(property) = $\(paramName)",
                parameters: [paramName: value]
            )
            
        case .delete(let detach):
            let deleteClause = detach ? "DETACH DELETE" : "DELETE"
            return CypherFragment(query: "\(deleteClause) \(alias)")
            
        case .having(let predicate):
            let predicateCypher = try predicate.toCypher()
            return CypherFragment(
                query: "HAVING \(predicateCypher.query)",
                parameters: predicateCypher.parameters
            )
            
        case .whereExists(let subquery):
            let subqueryCypher = try subquery.toCypher()
            return CypherFragment(
                query: "WHERE EXISTS { \(subqueryCypher.query) }",
                parameters: subqueryCypher.parameters
            )
        }
    }
}

// MARK: - Sort Direction

public enum SortDirection {
    case ascending
    case descending
}

// MARK: - Operator Overloads

public func == <Model, Value: Equatable>(_ lhs: KeyPath<Model, Value>, _ rhs: Value) -> (KeyPath<Model, Value>, ComparisonOperator, Value) {
    (lhs, .equal, rhs)
}

public func != <Model, Value: Equatable>(_ lhs: KeyPath<Model, Value>, _ rhs: Value) -> (KeyPath<Model, Value>, ComparisonOperator, Value) {
    (lhs, .notEqual, rhs)
}

public func < <Model, Value: Comparable>(_ lhs: KeyPath<Model, Value>, _ rhs: Value) -> (KeyPath<Model, Value>, ComparisonOperator, Value) {
    (lhs, .lessThan, rhs)
}

public func <= <Model, Value: Comparable>(_ lhs: KeyPath<Model, Value>, _ rhs: Value) -> (KeyPath<Model, Value>, ComparisonOperator, Value) {
    (lhs, .lessThanOrEqual, rhs)
}

public func > <Model, Value: Comparable>(_ lhs: KeyPath<Model, Value>, _ rhs: Value) -> (KeyPath<Model, Value>, ComparisonOperator, Value) {
    (lhs, .greaterThan, rhs)
}

public func >= <Model, Value: Comparable>(_ lhs: KeyPath<Model, Value>, _ rhs: Value) -> (KeyPath<Model, Value>, ComparisonOperator, Value) {
    (lhs, .greaterThanOrEqual, rhs)
}