import Foundation
import Kuzu

/// Represents an UNWIND clause in a Cypher query for processing lists
public struct Unwind: QueryComponent {
    let items: any Sendable
    let alias: String
    
    private init(items: any Sendable, alias: String) {
        self.items = items
        self.alias = alias
    }
    
    /// Creates an UNWIND clause for processing an array of items
    /// - Parameters:
    ///   - items: The array of items to unwind
    ///   - alias: The alias to use for each item in the array
    public static func items<T: Encodable & Sendable>(_ items: [T], as alias: String) -> Unwind {
        Unwind(items: items, alias: alias)
    }
    
    /// Creates an UNWIND clause from a parameter reference
    /// - Parameters:
    ///   - parameterName: The name of the parameter containing the array
    ///   - alias: The alias to use for each item
    public static func parameter(_ parameterName: String, as alias: String) -> Unwind {
        Unwind(items: "$\(parameterName)", alias: alias)
    }
    
    public func toCypher() throws -> CypherFragment {
        if let paramRef = items as? String, paramRef.starts(with: "$") {
            // It's already a parameter reference
            return CypherFragment(query: "UNWIND \(paramRef) AS \(alias)")
        } else {
            // Encode the items as a parameter
            let paramName = ParameterNameGenerator.generateUUID()
            return CypherFragment(
                query: "UNWIND $\(paramName) AS \(alias)",
                parameters: [paramName: items]
            )
        }
    }
}

// MARK: - Batch Operations Extension

extension GraphContext {
    
    // MARK: - Batch Create
    
    /// Creates multiple nodes in a single operation
    /// - Parameter models: Array of node models to create
    /// - Returns: The created nodes
    public func createMany<T: GraphNodeModel & Encodable>(_ models: [T]) async throws {
        guard !models.isEmpty else { return }
        
        let encoder = KuzuEncoder()
        // Use raw query for batch create
        let typeName = String(describing: T.self)
        let encodedModels = try models.map { try encoder.encode($0) }
        
        // Kuzu requires primary key in CREATE statement
        // Build CREATE with properties inline
        guard let firstModel = encodedModels.first else { return }
        let propertyAssignments = firstModel.keys.map { "\($0): item.\($0)" }.joined(separator: ", ")
        
        let cypher = """
            UNWIND $items AS item
            CREATE (n:\(typeName) {\(propertyAssignments)})
            RETURN n
            """
        
        _ = try await raw(cypher, bindings: ["items": encodedModels])
    }
    
    // MARK: - Batch Update
    
    /// Updates multiple nodes matching a condition
    /// - Parameters:
    ///   - type: The type of nodes to update
    ///   - matching: A predicate to match nodes
    ///   - updates: The properties to update
    public func updateMany<T: GraphNodeModel>(
        _ type: T.Type,
        matching predicate: Predicate,
        set updates: [String: any Sendable]
    ) async throws {
        // Use raw query for now to avoid ambiguity
        let typeName = String(describing: T.self)
        // Replace any "u." references with "n." to match our alias
        let predicateCypher = try predicate.toCypher()
        let whereClause = predicateCypher.query.replacingOccurrences(of: "u.", with: "n.")
        
        var cypher = "MATCH (n:\(typeName)) WHERE \(whereClause) SET "
        var bindings = predicateCypher.parameters
        
        var setClauses: [String] = []
        for (key, value) in updates {
            let paramName = "update_\(key)"
            setClauses.append("n.\(key) = $\(paramName)")
            bindings[paramName] = value
        }
        
        cypher += setClauses.joined(separator: ", ")
        cypher += " RETURN n"
        
        _ = try await raw(cypher, bindings: bindings)
    }
    
    /// Updates multiple specific nodes
    /// - Parameters:
    ///   - models: The models to update (must have ID properties)
    ///   - properties: The specific properties to update
    public func updateMany<T: GraphNodeModel & Encodable>(
        _ models: [T],
        properties: Set<String>? = nil
    ) async throws {
        guard !models.isEmpty else { return }
        
        let encoder = KuzuEncoder()
        
        for model in models {
            // Extract ID
            let mirror = Mirror(reflecting: model)
            var modelId: Any?
            
            for child in mirror.children {
                if child.label == "id" || child.label == "_id" {
                    // Handle property wrapper
                    let propMirror = Mirror(reflecting: child.value)
                    for prop in propMirror.children {
                        if prop.label == "wrappedValue" {
                            modelId = prop.value
                            break
                        }
                    }
                    if modelId == nil {
                        modelId = child.value
                    }
                    break
                }
            }
            
            guard let id = modelId else {
                throw GraphError.missingIdentifier
            }
            
            // Encode and filter properties
            var updates = try encoder.encode(model)
            
            // Remove ID from updates
            updates.removeValue(forKey: "id")
            
            // Filter to specific properties if requested
            if let properties = properties {
                updates = updates.filter { properties.contains($0.key) }
            }
            
            // Use raw query to update by ID
            let typeName = String(describing: T.self)
            
            var cypher = "MATCH (n:\(typeName) {id: $nodeId}) SET "
            // Cast id to a concrete Sendable type
            let nodeId: any Sendable
            if let uuidId = id as? UUID {
                nodeId = uuidId.uuidString
            } else if let stringId = id as? String {
                nodeId = stringId
            } else if let intId = id as? Int {
                nodeId = intId
            } else {
                // Fallback to string representation
                nodeId = String(describing: id)
            }
            
            var bindings: [String: any Sendable] = ["nodeId": nodeId]
            
            var setClauses: [String] = []
            for (key, value) in updates {
                let paramName = "update_\(key)"
                setClauses.append("n.\(key) = $\(paramName)")
                bindings[paramName] = value
            }
            
            cypher += setClauses.joined(separator: ", ")
            cypher += " RETURN n"
            
            _ = try await raw(cypher, bindings: bindings)
        }
    }
    
    // MARK: - Batch Delete
    
    /// Deletes multiple nodes matching a condition
    /// - Parameters:
    ///   - type: The type of nodes to delete
    ///   - predicate: The condition to match nodes for deletion
    public func deleteMany<T: GraphNodeModel>(
        _ type: T.Type,
        where predicate: Predicate
    ) async throws {
        // Use raw query for deletion
        let typeName = String(describing: T.self)
        // Replace any "u." references with "n." to match our alias
        let predicateCypher = try predicate.toCypher()
        let whereClause = predicateCypher.query.replacingOccurrences(of: "u.", with: "n.")
        
        let cypher = "MATCH (n:\(typeName)) WHERE \(whereClause) DETACH DELETE n RETURN COUNT(*)"
        
        _ = try await raw(cypher, bindings: predicateCypher.parameters)
    }
    
    /// Deletes specific nodes by their IDs
    /// - Parameters:
    ///   - type: The type of nodes to delete
    ///   - ids: The IDs of nodes to delete
    public func deleteMany<T: GraphNodeModel>(
        _ type: T.Type,
        ids: [any Sendable]
    ) async throws {
        guard !ids.isEmpty else { return }
        
        // Use raw query for batch deletion
        let typeName = String(describing: T.self)
        
        let cypher = """
            UNWIND $ids AS nodeId
            MATCH (n:\(typeName) {id: nodeId})
            DETACH DELETE n
            RETURN COUNT(*)
            """
        
        _ = try await raw(cypher, bindings: ["ids": ids])
    }
    
    // MARK: - Batch Merge (Upsert)
    
    /// Creates or updates multiple nodes
    /// - Parameters:
    ///   - models: The models to merge
    ///   - matchOn: The property to match on (usually "id")
    ///   - onCreate: Properties to set only on creation
    ///   - onMatch: Properties to set only on match
    public func mergeMany<T: GraphNodeModel & Encodable>(
        _ models: [T],
        matchOn property: String = "id",
        onCreate: [String: any Sendable]? = nil,
        onMatch: [String: any Sendable]? = nil
    ) async throws {
        guard !models.isEmpty else { return }
        
        let encoder = KuzuEncoder()
        
        for model in models {
            let encoded = try encoder.encode(model)
            
            // Extract the match property value
            guard let matchValue = encoded[property] else {
                throw GraphError.missingIdentifier
            }
            
            var merge = Merge.node(T.self, matchProperties: [property: matchValue])
            
            // Add onCreate properties
            if let onCreate = onCreate {
                merge = merge.onCreate(set: onCreate)
            } else {
                // Use all properties except the match property for onCreate
                var createProps = encoded
                createProps.removeValue(forKey: property)
                if !createProps.isEmpty {
                    merge = merge.onCreate(set: createProps)
                }
            }
            
            // Add onMatch properties
            if let onMatch = onMatch {
                merge = merge.onMatch(set: onMatch)
            }
            
            // Execute merge directly
            let mergeCypher = try merge.toCypher()
            _ = try await raw(mergeCypher.query + " RETURN \(merge.pattern.alias)", bindings: mergeCypher.parameters)
        }
    }
}

// MARK: - Batch Query Builder

/// Helper for building complex batch operations
public struct BatchBuilder {
    private let context: GraphContext
    
    init(context: GraphContext) {
        self.context = context
    }
    
    /// Performs a batch operation with a custom query
    public func execute<T: Encodable & Sendable>(
        items: [T],
        @QueryBuilder query: (String) -> Query
    ) async throws -> QueryResult {
        let unwind = Unwind.items(items, as: "item")
        let queryComponents = query("item").components
        
        // Combine components
        var allComponents: [QueryComponent] = [unwind]
        allComponents.append(contentsOf: queryComponents)
        
        // Create a query with all components
        let combinedQuery = Query(components: allComponents)
        return try await context.raw(try CypherCompiler.compile(combinedQuery).query, bindings: try CypherCompiler.compile(combinedQuery).parameters)
    }
    
    /// Processes items in chunks to avoid memory issues
    public func chunked<T: GraphNodeModel & Encodable>(
        _ models: [T],
        chunkSize: Int = 1000,
        operation: ([T]) async throws -> Void
    ) async throws {
        for chunk in models.chunked(into: chunkSize) {
            try await operation(chunk)
        }
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    /// Splits the array into chunks of the specified size
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}