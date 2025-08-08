import Foundation

/// Type-safe aggregation functions for queries
public enum Aggregation {
    case count(String) // alias or * for all
    case countDistinct(String)
    case max(PropertyReference)
    case min(PropertyReference)
    case sum(PropertyReference)
    case avg(PropertyReference)
    case collect(PropertyReference)
    case collectDistinct(PropertyReference)
    
    /// Converts the aggregation to a Cypher expression
    public func toCypher() -> String {
        switch self {
        case .count(let alias):
            return alias == "*" ? "COUNT(*)" : "COUNT(\(alias))"
        case .countDistinct(let alias):
            return "COUNT(DISTINCT \(alias))"
        case .max(let prop):
            return "MAX(\(prop.toCypher()))"
        case .min(let prop):
            return "MIN(\(prop.toCypher()))"
        case .sum(let prop):
            return "SUM(\(prop.toCypher()))"
        case .avg(let prop):
            return "AVG(\(prop.toCypher()))"
        case .collect(let prop):
            return "COLLECT(\(prop.toCypher()))"
        case .collectDistinct(let prop):
            return "COLLECT(DISTINCT \(prop.toCypher()))"
        }
    }
}

// MARK: - Type-safe Aggregation Builders

public extension Aggregation {
    /// Creates a COUNT aggregation for a node
    static func count<T: _KuzuGraphModel>(_ type: T.Type, alias: String? = nil) -> Aggregation {
        let nodeAlias = alias ?? String(describing: type).lowercased()
        return .count(nodeAlias)
    }
    
    /// Creates a COUNT aggregation for a property path
    static func count<T: _KuzuGraphModel>(_ path: PropertyPath<T>) -> Aggregation {
        return .count(path.propertyReference.toCypher())
    }
    
    /// Creates a COUNT DISTINCT aggregation
    static func countDistinct<T: _KuzuGraphModel>(_ type: T.Type, alias: String? = nil) -> Aggregation {
        let nodeAlias = alias ?? String(describing: type).lowercased()
        return .countDistinct(nodeAlias)
    }
    
    /// Creates a MAX aggregation for a property path
    static func max<T: _KuzuGraphModel>(_ path: PropertyPath<T>) -> Aggregation {
        return .max(path.propertyReference)
    }
    
    /// Creates a MIN aggregation for a property path
    static func min<T: _KuzuGraphModel>(_ path: PropertyPath<T>) -> Aggregation {
        return .min(path.propertyReference)
    }
    
    /// Creates a SUM aggregation for a property path
    static func sum<T: _KuzuGraphModel>(_ path: PropertyPath<T>) -> Aggregation {
        return .sum(path.propertyReference)
    }
    
    /// Creates an AVG aggregation for a property path
    static func avg<T: _KuzuGraphModel>(_ path: PropertyPath<T>) -> Aggregation {
        return .avg(path.propertyReference)
    }
    
    /// Creates a COLLECT aggregation for a property path
    static func collect<T: _KuzuGraphModel>(_ path: PropertyPath<T>) -> Aggregation {
        return .collect(path.propertyReference)
    }
    
    /// Creates a COLLECT DISTINCT aggregation
    static func collectDistinct<T: _KuzuGraphModel>(_ path: PropertyPath<T>) -> Aggregation {
        return .collectDistinct(path.propertyReference)
    }
}

// MARK: - Edge Aggregations

public extension Aggregation {
    /// Creates a MAX aggregation for an edge property
    static func max<E: _KuzuGraphModel, V>(_ edgePath: EdgePath<E, V>) -> Aggregation {
        return .max(edgePath.propertyReference)
    }
    
    /// Creates a MIN aggregation for an edge property
    static func min<E: _KuzuGraphModel, V>(_ edgePath: EdgePath<E, V>) -> Aggregation {
        return .min(edgePath.propertyReference)
    }
    
    /// Creates a SUM aggregation for an edge property
    static func sum<E: _KuzuGraphModel, V>(_ edgePath: EdgePath<E, V>) -> Aggregation {
        return .sum(edgePath.propertyReference)
    }
    
    /// Creates an AVG aggregation for an edge property
    static func avg<E: _KuzuGraphModel, V>(_ edgePath: EdgePath<E, V>) -> Aggregation {
        return .avg(edgePath.propertyReference)
    }
    
    /// Creates a COLLECT aggregation for an edge property
    static func collect<E: _KuzuGraphModel, V>(_ edgePath: EdgePath<E, V>) -> Aggregation {
        return .collect(edgePath.propertyReference)
    }
}

// MARK: - Return Statement Extensions

public extension Return {
    /// Returns an aggregation result
    static func aggregate(_ aggregation: Aggregation, as alias: String) -> Return {
        let item = ReturnItem.aliased(
            expression: aggregation.toCypher(),
            alias: alias
        )
        return Return.items(item)
    }
    
    /// Returns multiple aggregations
    static func aggregates(_ aggregations: (Aggregation, String)...) -> Return {
        let items = aggregations.map { agg, alias in
            ReturnItem.aliased(expression: agg.toCypher(), alias: alias)
        }
        // Use ItemBuilder to handle any number of items
        return Return.items(items)
    }
    
    /// Adds a GROUP BY clause with a property path
    func groupBy<T: _KuzuGraphModel>(_ path: PropertyPath<T>) -> Return {
        // In Cypher, GROUP BY is implicit based on non-aggregated columns in RETURN
        // We add the property to the return items if not already present
        var newItems = self.items
        let propItem = ReturnItem.property(alias: path.alias, property: path.propertyName)
        if !newItems.contains(where: { item in
            if case .property(let alias, let prop) = item {
                return alias == path.alias && prop == path.propertyName
            }
            return false
        }) {
            newItems.insert(propItem, at: 0)
        }
        // Rebuild using array-based API (no switch needed)
        let result = Return.items(newItems)
        var finalResult = result
        if self.distinct {
            finalResult = finalResult.withDistinct()
        }
        if let orderBy = self.orderBy, !orderBy.isEmpty {
            // Handle orderBy array
            for orderItem in orderBy {
                finalResult = finalResult.orderBy(orderItem)
            }
        }
        if let limit = self.limit {
            finalResult = finalResult.limit(limit)
        }
        if let skip = self.skip {
            finalResult = finalResult.skip(skip)
        }
        return finalResult
    }
    
    /// Adds a GROUP BY clause with an edge property
    func groupBy<E: _KuzuGraphModel, V>(_ edgePath: EdgePath<E, V>) -> Return {
        var newItems = self.items
        let propItem = ReturnItem.property(alias: edgePath.alias, property: edgePath.propertyName)
        if !newItems.contains(where: { item in
            if case .property(let alias, let prop) = item {
                return alias == edgePath.alias && prop == edgePath.propertyName
            }
            return false
        }) {
            newItems.insert(propItem, at: 0)
        }
        // Rebuild using array-based API (no switch needed)
        let result = Return.items(newItems)
        var finalResult = result
        if self.distinct {
            finalResult = finalResult.withDistinct()
        }
        if let orderBy = self.orderBy, !orderBy.isEmpty {
            // Handle orderBy array
            for orderItem in orderBy {
                finalResult = finalResult.orderBy(orderItem)
            }
        }
        if let limit = self.limit {
            finalResult = finalResult.limit(limit)
        }
        if let skip = self.skip {
            finalResult = finalResult.skip(skip)
        }
        return finalResult
    }
    
    /// Adds a HAVING clause (requires aggregation)
    func having(_ predicate: Predicate) -> Return {
        // HAVING is handled as a WHERE clause after aggregation
        // This would need to be added to the Return struct and handled in CypherCompiler
        // For now, we'll document this as a future enhancement
        return self
    }
}

// MARK: - Convenience Extensions

public extension Return {
    /// Returns a count of all results
    static func count() -> Return {
        aggregate(.count("*"), as: "count")
    }
    
    /// Returns a count of a specific node type
    static func count<T: _KuzuGraphModel>(_ type: T.Type, as alias: String = "count") -> Return {
        aggregate(.count(type), as: alias)
    }
    
    /// Returns the maximum value of a property
    static func max<T: _KuzuGraphModel>(_ path: PropertyPath<T>, as alias: String = "max") -> Return {
        aggregate(.max(path), as: alias)
    }
    
    /// Returns the minimum value of a property
    static func min<T: _KuzuGraphModel>(_ path: PropertyPath<T>, as alias: String = "min") -> Return {
        aggregate(.min(path), as: alias)
    }
    
    /// Returns the sum of a property
    static func sum<T: _KuzuGraphModel>(_ path: PropertyPath<T>, as alias: String = "sum") -> Return {
        aggregate(.sum(path), as: alias)
    }
    
    /// Returns the average of a property
    static func avg<T: _KuzuGraphModel>(_ path: PropertyPath<T>, as alias: String = "avg") -> Return {
        aggregate(.avg(path), as: alias)
    }
}