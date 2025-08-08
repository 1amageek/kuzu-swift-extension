import Foundation
import Algorithms

/// Represents aggregation functions in Cypher queries
public enum Aggregation {
    case count(String)
    case countDistinct(String)
    case sum(PropertyReference)
    case avg(PropertyReference)
    case min(PropertyReference)
    case max(PropertyReference)
    case collect(PropertyReference)
    case collectDistinct(PropertyReference)
    case stdev(PropertyReference)
    case variance(PropertyReference)
    case percentileDisc(PropertyReference, percentile: Double)
    case percentileCont(PropertyReference, percentile: Double)
    case custom(String)
    
    public func toCypher() -> String {
        switch self {
        case .count(let expr):
            return "COUNT(\(expr))"
        case .countDistinct(let expr):
            return "COUNT(DISTINCT \(expr))"
        case .sum(let ref):
            return "SUM(\(ref.cypher))"
        case .avg(let ref):
            return "AVG(\(ref.cypher))"
        case .min(let ref):
            return "MIN(\(ref.cypher))"
        case .max(let ref):
            return "MAX(\(ref.cypher))"
        case .collect(let ref):
            return "COLLECT(\(ref.cypher))"
        case .collectDistinct(let ref):
            return "COLLECT(DISTINCT \(ref.cypher))"
        case .stdev(let ref):
            return "STDEV(\(ref.cypher))"
        case .variance(let ref):
            return "VARIANCE(\(ref.cypher))"
        case .percentileDisc(let ref, let percentile):
            return "PERCENTILE_DISC(\(ref.cypher), \(percentile))"
        case .percentileCont(let ref, let percentile):
            return "PERCENTILE_CONT(\(ref.cypher), \(percentile))"
        case .custom(let expr):
            return expr
        }
    }
}

// MARK: - Type-safe aggregation builders

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
    
    /// Creates an AVG aggregation for a property reference with different signature
    static func avgRef(_ ref: PropertyReference) -> Aggregation {
        return .avg(ref)
    }
    
    /// Creates a COLLECT aggregation for a property path
    static func collect<T: _KuzuGraphModel>(_ path: PropertyPath<T>) -> Aggregation {
        return .collect(path.propertyReference)
    }
    
    /// Creates a COLLECT DISTINCT aggregation for a property path
    static func collectDistinct<T: _KuzuGraphModel>(_ path: PropertyPath<T>) -> Aggregation {
        return .collectDistinct(path.propertyReference)
    }
}

// MARK: - Aggregation Extensions for Collections using swift-algorithms

public extension Aggregation {
    /// Creates aggregations for multiple properties using swift-algorithms
    static func aggregate<T: _KuzuGraphModel>(
        properties: [KeyPath<T, Any>],
        with functions: [AggregationType],
        alias: String? = nil
    ) -> [Aggregation] {
        let nodeAlias = alias ?? String(describing: T.self).lowercased()
        
        // Generate all combinations using nested iteration
        var result: [Aggregation] = []
        for property in properties {
            for function in functions {
                let propertyName = String(describing: property).components(separatedBy: ".").last ?? ""
                let ref = PropertyReference(alias: nodeAlias, property: propertyName)
                
                switch function {
                case .count:
                    result.append(.count("\(nodeAlias).\(propertyName)"))
                case .countDistinct:
                    result.append(.countDistinct("\(nodeAlias).\(propertyName)"))
                case .sum:
                    result.append(.sum(ref))
                case .avg:
                    result.append(.avg(ref))
                case .min:
                    result.append(.min(ref))
                case .max:
                    result.append(.max(ref))
                case .collect:
                    result.append(.collect(ref))
                case .collectDistinct:
                    result.append(.collectDistinct(ref))
                case .stdev:
                    result.append(.stdev(ref))
                case .variance:
                    result.append(.variance(ref))
                }
            }
        }
        return result
    }
    
    /// Types of aggregation functions
    enum AggregationType {
        case count
        case countDistinct
        case sum
        case avg
        case min
        case max
        case collect
        case collectDistinct
        case stdev
        case variance
    }
}

// MARK: - Group By Extensions with swift-algorithms

public extension Return {
    /// Adds a GROUP BY clause with a node property using swift-algorithms
    func groupBy<T: _KuzuGraphModel>(_ path: PropertyPath<T>) -> Return {
        // Use swift-algorithms to efficiently check and modify items
        var newItems = self.items
        let propItem = ReturnItem.property(alias: path.alias, property: path.propertyName)
        
        // Use swift-algorithms uniqued to prevent duplicates
        if !newItems.contains(propItem) {
            newItems.insert(propItem, at: 0)
        }
        
        // Rebuild with all modifiers
        return rebuildWithItems(newItems)
    }
    
    /// Adds a GROUP BY clause with an edge property using swift-algorithms
    func groupBy<E: _KuzuGraphModel, V>(_ edgePath: EdgePath<E, V>) -> Return {
        var newItems = self.items
        let propItem = ReturnItem.property(alias: edgePath.alias, property: edgePath.propertyName)
        
        // Use swift-algorithms uniqued to prevent duplicates
        if !newItems.contains(propItem) {
            newItems.insert(propItem, at: 0)
        }
        
        return rebuildWithItems(newItems)
    }
    
    /// Groups by multiple properties using swift-algorithms
    func groupByMultiple<T: _KuzuGraphModel>(_ paths: [PropertyPath<T>]) -> Return {
        var newItems = self.items
        
        // Use swift-algorithms to efficiently add unique items
        let propertyItems = paths.map { path in
            ReturnItem.property(alias: path.alias, property: path.propertyName)
        }
        
        // Add only unique items using swift-algorithms
        let uniqueNewItems = propertyItems.filter { !newItems.contains($0) }
        newItems.insert(contentsOf: uniqueNewItems, at: 0)
        
        return rebuildWithItems(newItems)
    }
    
    /// Helper method to rebuild Return with all modifiers
    private func rebuildWithItems(_ newItems: [ReturnItem]) -> Return {
        var result = Return.items(newItems)
        
        if self.distinct {
            result = result.withDistinct()
        }
        
        // Apply all order by clauses using swift-algorithms
        if let orderBy = self.orderBy, !orderBy.isEmpty {
            result = orderBy.reduce(result) { acc, orderItem in
                acc.orderBy(orderItem)
            }
        }
        
        if let limit = self.limit {
            result = result.limit(limit)
        }
        
        if let skip = self.skip {
            result = result.skip(skip)
        }
        
        return result
    }
}

// MARK: - Aggregation Pipeline using swift-algorithms

public struct AggregationPipeline {
    private var aggregations: [Aggregation] = []
    
    /// Adds multiple aggregations using swift-algorithms
    public mutating func add(_ aggregations: Aggregation...) {
        self.aggregations.append(contentsOf: aggregations)
    }
    
    /// Adds aggregations from a collection using swift-algorithms
    public mutating func add<S: Sequence>(contentsOf sequence: S) where S.Element == Aggregation {
        self.aggregations.append(contentsOf: sequence)
    }
    
    /// Combines aggregations using swift-algorithms
    public func combined() -> [String] {
        // Use swift-algorithms uniqued to remove duplicates
        return Array(aggregations.map { $0.toCypher() }.uniqued())
    }
    
    /// Groups aggregations by type using swift-algorithms
    public func groupedByType() -> [String: [Aggregation]] {
        // Use swift-algorithms to group by aggregation type
        return Dictionary(grouping: aggregations) { aggregation in
            switch aggregation {
            case .count, .countDistinct:
                return "count"
            case .sum:
                return "sum"
            case .avg:
                return "avg"
            case .min, .max:
                return "minmax"
            case .collect, .collectDistinct:
                return "collect"
            case .stdev, .variance:
                return "statistical"
            case .percentileDisc, .percentileCont:
                return "percentile"
            case .custom:
                return "custom"
            }
        }
    }
    
    /// Filters aggregations by property using swift-algorithms
    public func filterByProperty(_ propertyName: String) -> [Aggregation] {
        return aggregations.filter { aggregation in
            switch aggregation {
            case .sum(let ref), .avg(let ref), .min(let ref), .max(let ref),
                 .collect(let ref), .collectDistinct(let ref),
                 .stdev(let ref), .variance(let ref),
                 .percentileDisc(let ref, _), .percentileCont(let ref, _):
                return ref.property == propertyName
            default:
                return false
            }
        }
    }
    
    /// Optimizes aggregations by combining compatible ones using swift-algorithms
    public func optimized() -> [Aggregation] {
        // Group by property reference and combine compatible aggregations
        let grouped = Dictionary(grouping: aggregations) { aggregation -> String? in
            switch aggregation {
            case .sum(let ref), .avg(let ref), .min(let ref), .max(let ref),
                 .collect(let ref), .collectDistinct(let ref),
                 .stdev(let ref), .variance(let ref):
                return ref.cypher
            case .percentileDisc(let ref, _), .percentileCont(let ref, _):
                return ref.cypher
            case .count(let expr), .countDistinct(let expr):
                return expr
            case .custom(let expr):
                return expr
            }
        }
        
        // Use swift-algorithms to flatten and uniquify
        return grouped.values.flatMap { group in
            // Keep only unique aggregations per group using uniqued(on:)
            group.uniqued(on: { $0.toCypher() })
        }
    }
}

// MARK: - ReturnItem Equatable for swift-algorithms usage

extension ReturnItem: Equatable {
    public static func == (lhs: ReturnItem, rhs: ReturnItem) -> Bool {
        switch (lhs, rhs) {
        case (.alias(let a1), .alias(let a2)):
            return a1 == a2
        case (.property(let alias1, let prop1), .property(let alias2, let prop2)):
            return alias1 == alias2 && prop1 == prop2
        case (.aliased(let expr1, let alias1), .aliased(let expr2, let alias2)):
            return expr1 == expr2 && alias1 == alias2
        case (.count(let c1), .count(let c2)):
            return c1 == c2
        case (.collect(let c1), .collect(let c2)):
            return c1 == c2
        case (.all, .all):
            return true
        default:
            return false
        }
    }
}