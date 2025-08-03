import Foundation

public struct Return: QueryComponent {
    let items: [ReturnItem]
    let distinct: Bool
    let orderBy: [OrderByItem]?
    let limit: Int?
    let skip: Int?
    
    private init(
        items: [ReturnItem],
        distinct: Bool = false,
        orderBy: [OrderByItem]? = nil,
        limit: Int? = nil,
        skip: Int? = nil
    ) {
        self.items = items
        self.distinct = distinct
        self.orderBy = orderBy
        self.limit = limit
        self.skip = skip
    }
    
    public static func items(_ items: ReturnItem...) -> Return {
        Return(items: items)
    }
    
    public static func all() -> Return {
        Return(items: [.all])
    }
    
    public func withDistinct() -> Return {
        Return(
            items: items,
            distinct: true,
            orderBy: orderBy,
            limit: limit,
            skip: skip
        )
    }
    
    public func orderBy(_ items: OrderByItem...) -> Return {
        Return(
            items: self.items,
            distinct: distinct,
            orderBy: items,
            limit: limit,
            skip: skip
        )
    }
    
    public func limit(_ count: Int) -> Return {
        Return(
            items: items,
            distinct: distinct,
            orderBy: orderBy,
            limit: count,
            skip: skip
        )
    }
    
    public func skip(_ count: Int) -> Return {
        Return(
            items: items,
            distinct: distinct,
            orderBy: orderBy,
            limit: limit,
            skip: count
        )
    }
    
    public func toCypher() throws -> CypherFragment {
        var query = "RETURN"
        
        if distinct {
            query += " DISTINCT"
        }
        
        let itemStrings = items.map { item in
            switch item {
            case .all:
                return "*"
            case .alias(let alias):
                return alias
            case .property(let alias, let property):
                return "\(alias).\(property)"
            case .aliased(let expression, let alias):
                return "\(expression) AS \(alias)"
            case .count(let alias):
                return "COUNT(\(alias ?? "*"))"
            case .collect(let expression):
                return "COLLECT(\(expression))"
            }
        }
        
        query += " " + itemStrings.joined(separator: ", ")
        
        if let orderBy = orderBy {
            let orderStrings = orderBy.map { item in
                let direction = item.ascending ? "ASC" : "DESC"
                return "\(item.expression) \(direction)"
            }
            query += " ORDER BY " + orderStrings.joined(separator: ", ")
        }
        
        if let skip = skip {
            query += " SKIP \(skip)"
        }
        
        if let limit = limit {
            query += " LIMIT \(limit)"
        }
        
        return CypherFragment(query: query)
    }
}

public enum ReturnItem {
    case all
    case alias(String)
    case property(alias: String, property: String)
    case aliased(expression: String, alias: String)
    case count(String?)
    case collect(String)
    
    public static func node(_ alias: String) -> ReturnItem {
        .alias(alias)
    }
    
    public static func property<T, V>(_ keyPath: KeyPath<T, V>, on alias: String) -> ReturnItem {
        let property = String(describing: keyPath).components(separatedBy: ".").last ?? ""
        return .property(alias: alias, property: property)
    }
}

public struct OrderByItem {
    let expression: String
    let ascending: Bool
    
    public static func ascending(_ expression: String) -> OrderByItem {
        OrderByItem(expression: expression, ascending: true)
    }
    
    public static func descending(_ expression: String) -> OrderByItem {
        OrderByItem(expression: expression, ascending: false)
    }
}