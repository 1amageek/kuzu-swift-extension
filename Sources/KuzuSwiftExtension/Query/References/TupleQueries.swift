import Foundation
import Kuzu

/// A query that represents a tuple of query components (similar to SwiftUI's TupleView)
@frozen
public struct TupleQuery<each T> {
    /// The value containing the tuple of components
    public var value: (repeat each T)
    
    @inlinable
    public init(_ value: repeat each T) {
        self.value = (repeat each value)
    }
}

// MARK: - QueryComponent conformance

extension TupleQuery: QueryComponent where repeat each T: QueryComponent {
    public typealias Result = (repeat (each T).Result)
    
    public func toCypher() throws -> CypherFragment {
        let combiner = QueryCombiner()
        
        // Add all component cyphers to combiner
        for component in repeat each value {
            let cypher = try component.toCypher()
            try combiner.add(cypher)
        }
        
        // Build combined query
        var combined = try combiner.build()
        
        // Ensure RETURN clause includes all aliased components if needed
        if !combined.query.contains("RETURN") {
            var returnAliases: [String] = []
            
            // Collect aliases from each component
            for component in repeat each value {
                if let aliased = component as? any AliasedComponent {
                    returnAliases.append(aliased.alias)
                }
            }
            
            if !returnAliases.isEmpty {
                // For tuple queries, we need to collect all nodes of each type
                // Use COLLECT to return arrays
                let collectReturns = returnAliases.map { "collect(\($0))" }
                combined = CypherFragment(
                    query: combined.query + " RETURN " + collectReturns.joined(separator: ", "),
                    parameters: combined.parameters,
                    structure: combined.structure
                )
            }
        }
        
        return combined
    }
    
    public func mapResult(_ result: QueryResult, decoder: KuzuDecoder) throws -> Result {
        guard result.hasNext() else {
            throw KuzuError.noResults
        }
        
        guard let row = try result.getNext() else {
            throw KuzuError.noResults
        }
        
        var columnIndex: UInt64 = 0
        
        // Map each component result
        func nextValue<C: QueryComponent>(_ component: C) throws -> C.Result {
            let value = try row.getValue(columnIndex)
            columnIndex += 1
            
            // For NodeReference types, decode the collected array
            if let nodeRef = component as? any NodeReferenceProtocol {
                return try nodeRef.mapCollectedValue(value, decoder: decoder) as! C.Result
            }
            
            // Default: return the value as-is
            return value as! C.Result
        }
        
        return (repeat try nextValue(each value))
    }
}

// Protocol to help with type erasure
protocol NodeReferenceProtocol {
    func mapCollectedValue(_ value: Any?, decoder: KuzuDecoder) throws -> Any
}

extension NodeReference: NodeReferenceProtocol where Model: Decodable {
    func mapCollectedValue(_ value: Any?, decoder: KuzuDecoder) throws -> Any {
        var nodes: [Model] = []
        
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
        }
        
        return nodes
    }
}