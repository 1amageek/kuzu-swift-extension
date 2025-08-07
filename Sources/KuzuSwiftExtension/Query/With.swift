import Foundation

/// Represents a WITH clause in a Cypher query for shaping results and pipelining
public struct With: QueryComponent {
    let items: [WithItem]
    let predicate: Predicate?
    let orderBy: [OrderByItem]?
    let limit: Int?
    let skip: Int?
    
    private init(
        items: [WithItem],
        predicate: Predicate? = nil,
        orderBy: [OrderByItem]? = nil,
        limit: Int? = nil,
        skip: Int? = nil
    ) {
        self.items = items
        self.predicate = predicate
        self.orderBy = orderBy
        self.limit = limit
        self.skip = skip
    }
    
    // MARK: - Item Types
    
    public enum WithItem {
        case alias(String) // Pass through an alias
        case property(String, String) // alias.property
        case aliased(expression: String, alias: String) // expression AS alias
        case aggregation(Aggregation, alias: String)
        case all // WITH *
    }
    
    // MARK: - Constructors
    
    /// Creates a WITH clause that passes all variables
    public static var all: With {
        With(items: [.all])
    }
    
    /// Creates a WITH clause for specific aliases
    public static func aliases(_ aliases: String...) -> With {
        With(items: aliases.map { .alias($0) })
    }
    
    /// Creates a WITH clause for a single alias
    public static func alias(_ alias: String) -> With {
        With(items: [.alias(alias)])
    }
    
    /// Creates a WITH clause for node properties
    public static func property<T: _KuzuGraphModel>(
        _ path: PropertyPath<T>,
        as alias: String? = nil
    ) -> With {
        let item: WithItem
        if let alias = alias {
            item = .aliased(expression: path.cypherString, alias: alias)
        } else {
            item = .property(path.alias, path.propertyName)
        }
        return With(items: [item])
    }
    
    /// Creates a WITH clause for edge properties
    public static func property<E: _KuzuGraphModel, V>(
        _ edgePath: EdgePath<E, V>,
        as alias: String? = nil
    ) -> With {
        let item: WithItem
        if let alias = alias {
            item = .aliased(expression: edgePath.cypherString, alias: alias)
        } else {
            item = .property(edgePath.alias, edgePath.propertyName)
        }
        return With(items: [item])
    }
    
    /// Creates a WITH clause with an aggregation
    public static func aggregate(_ aggregation: Aggregation, as alias: String) -> With {
        With(items: [.aggregation(aggregation, alias: alias)])
    }
    
    /// Creates a WITH clause with multiple aggregations
    public static func aggregates(_ aggregations: (Aggregation, String)...) -> With {
        let items = aggregations.map { agg, alias in
            WithItem.aggregation(agg, alias: alias)
        }
        return With(items: items)
    }
    
    /// Creates a WITH clause with custom expressions
    public static func expression(_ expression: String, as alias: String) -> With {
        With(items: [.aliased(expression: expression, alias: alias)])
    }
    
    /// Creates a WITH clause with multiple items
    public static func items(_ items: WithItem...) -> With {
        With(items: items)
    }
    
    // MARK: - Modifiers
    
    /// Adds another item to the WITH clause
    public func and(_ item: WithItem) -> With {
        var newItems = self.items
        newItems.append(item)
        return With(
            items: newItems,
            predicate: self.predicate,
            orderBy: self.orderBy,
            limit: self.limit,
            skip: self.skip
        )
    }
    
    /// Adds an alias to pass through
    public func and(_ alias: String) -> With {
        and(.alias(alias))
    }
    
    /// Adds a property to the WITH clause
    public func and<T: _KuzuGraphModel>(
        _ path: PropertyPath<T>,
        as alias: String? = nil
    ) -> With {
        let item: WithItem
        if let alias = alias {
            item = .aliased(expression: path.cypherString, alias: alias)
        } else {
            item = .property(path.alias, path.propertyName)
        }
        return and(item)
    }
    
    /// Adds an aggregation to the WITH clause
    public func and(_ aggregation: Aggregation, as alias: String) -> With {
        and(.aggregation(aggregation, alias: alias))
    }
    
    /// Adds a WHERE clause to filter results
    public func `where`(_ predicate: Predicate) -> With {
        With(
            items: self.items,
            predicate: predicate,
            orderBy: self.orderBy,
            limit: self.limit,
            skip: self.skip
        )
    }
    
    /// Adds ORDER BY to the WITH clause
    public func orderBy(_ items: OrderByItem...) -> With {
        With(
            items: self.items,
            predicate: self.predicate,
            orderBy: items,
            limit: self.limit,
            skip: self.skip
        )
    }
    
    /// Orders by a property path
    public func orderBy<T: _KuzuGraphModel>(
        _ path: PropertyPath<T>,
        ascending: Bool = true
    ) -> With {
        let orderItem = ascending ?
            OrderByItem.ascending(path.cypherString) :
            OrderByItem.descending(path.cypherString)
        return orderBy(orderItem)
    }
    
    /// Orders by an edge property
    public func orderBy<E: _KuzuGraphModel, V>(
        _ edgePath: EdgePath<E, V>,
        ascending: Bool = true
    ) -> With {
        let orderItem = ascending ?
            OrderByItem.ascending(edgePath.cypherString) :
            OrderByItem.descending(edgePath.cypherString)
        return orderBy(orderItem)
    }
    
    /// Limits the number of results
    public func limit(_ count: Int) -> With {
        With(
            items: self.items,
            predicate: self.predicate,
            orderBy: self.orderBy,
            limit: count,
            skip: self.skip
        )
    }
    
    /// Skips a number of results
    public func skip(_ count: Int) -> With {
        With(
            items: self.items,
            predicate: self.predicate,
            orderBy: self.orderBy,
            limit: self.limit,
            skip: count
        )
    }
    
    // MARK: - GROUP BY Support
    
    /// Adds implicit GROUP BY by including non-aggregated columns
    public func groupBy<T: _KuzuGraphModel>(_ path: PropertyPath<T>) -> With {
        let item = WithItem.property(path.alias, path.propertyName)
        // Add at the beginning to ensure it's included for grouping
        var newItems = [item]
        newItems.append(contentsOf: self.items.filter { existingItem in
            // Avoid duplicates
            if case .property(let alias, let prop) = existingItem {
                return !(alias == path.alias && prop == path.propertyName)
            }
            return true
        })
        return With(
            items: newItems,
            predicate: self.predicate,
            orderBy: self.orderBy,
            limit: self.limit,
            skip: self.skip
        )
    }
    
    /// Adds implicit GROUP BY for edge properties
    public func groupBy<E: _KuzuGraphModel, V>(_ edgePath: EdgePath<E, V>) -> With {
        let item = WithItem.property(edgePath.alias, edgePath.propertyName)
        var newItems = [item]
        newItems.append(contentsOf: self.items.filter { existingItem in
            if case .property(let alias, let prop) = existingItem {
                return !(alias == edgePath.alias && prop == edgePath.propertyName)
            }
            return true
        })
        return With(
            items: newItems,
            predicate: self.predicate,
            orderBy: self.orderBy,
            limit: self.limit,
            skip: self.skip
        )
    }
    
    // MARK: - Cypher Compilation
    
    public func toCypher() throws -> CypherFragment {
        var query = "WITH "
        var parameters: [String: any Sendable] = [:]
        
        // Compile items
        let itemStrings = items.map { item -> String in
            switch item {
            case .all:
                return "*"
            case .alias(let alias):
                return alias
            case .property(let alias, let property):
                return "\(alias).\(property)"
            case .aliased(let expression, let alias):
                return "\(expression) AS \(alias)"
            case .aggregation(let agg, let alias):
                return "\(agg.toCypher()) AS \(alias)"
            }
        }
        
        query += itemStrings.joined(separator: ", ")
        
        // Add WHERE clause if present
        if let predicate = predicate {
            let predicateCypher = try predicate.toCypher()
            query += " WHERE \(predicateCypher.query)"
            parameters.merge(predicateCypher.parameters) { _, new in new }
        }
        
        // Add ORDER BY if present
        if let orderBy = orderBy, !orderBy.isEmpty {
            let orderStrings = orderBy.map { item in
                "\(item.expression) \(item.ascending ? "ASC" : "DESC")"
            }
            query += " ORDER BY \(orderStrings.joined(separator: ", "))"
        }
        
        // Add SKIP if present
        if let skip = skip {
            query += " SKIP \(skip)"
        }
        
        // Add LIMIT if present
        if let limit = limit {
            query += " LIMIT \(limit)"
        }
        
        return CypherFragment(query: query, parameters: parameters)
    }
}

// MARK: - Convenience Extensions

public extension With {
    /// Creates a WITH clause for counting results
    static func count(as alias: String = "count") -> With {
        aggregate(.count("*"), as: alias)
    }
    
    /// Creates a WITH clause for distinct values
    static func distinct<T: _KuzuGraphModel>(
        _ type: T.Type,
        alias: String? = nil
    ) -> With {
        let nodeAlias = alias ?? String(describing: type).lowercased()
        return With(items: [.alias(nodeAlias)])
    }
    
    /// Creates a WITH clause for collecting values
    static func collect<T: _KuzuGraphModel>(
        _ path: PropertyPath<T>,
        as alias: String
    ) -> With {
        aggregate(.collect(path), as: alias)
    }
    
    /// Creates a WITH clause for collecting distinct values
    static func collectDistinct<T: _KuzuGraphModel>(
        _ path: PropertyPath<T>,
        as alias: String
    ) -> With {
        aggregate(.collectDistinct(path), as: alias)
    }
}

// MARK: - WITH for Subqueries

public extension With {
    /// Creates a WITH clause suitable for subquery chaining
    static func chain(_ aliases: String...) -> With {
        With(items: aliases.map { .alias($0) })
    }
    
    /// Creates a WITH clause that projects specific columns for the next stage
    static func project(_ projections: (String, String)...) -> With {
        let items = projections.map { expr, alias in
            WithItem.aliased(expression: expr, alias: alias)
        }
        return With(items: items)
    }
}