import Foundation

// MARK: - Set

public struct Set {
    internal let clause: SetClause
    
    public init<T: _KuzuGraphModel, Value>(
        _ variable: String,
        _ keyPath: KeyPath<T, Value>,
        to value: Value
    ) where Value: Encodable {
        let property = Self.propertyName(from: keyPath)
        self.clause = SetClause(variable: variable, property: property, value: value)
    }
    
    public init(variable: String, property: String, value: Any) {
        self.clause = SetClause(variable: variable, property: property, value: value)
    }
    
    private static func propertyName<T, Value>(from keyPath: KeyPath<T, Value>) -> String {
        // This is a simplified version - in production, we'd use runtime introspection
        // or macro-generated metadata to get the actual property name
        return String(describing: keyPath).components(separatedBy: ".").last ?? "unknown"
    }
}

// MARK: - Delete

public struct Delete {
    internal let clause: DeleteClause
    
    public init(_ variable: String, detach: Bool = false) {
        self.clause = DeleteClause(variable: variable, detach: detach)
    }
}

// MARK: - Return

public struct Return {
    internal let clause: ReturnClause
    
    public init(_ items: ReturnItem...) {
        self.clause = ReturnClause(items: items)
    }
    
    public init(_ items: [ReturnItem]) {
        self.clause = ReturnClause(items: items)
    }
    
    public static func variable(_ name: String) -> Return {
        Return(.variable(name))
    }
    
    public static func property(_ variable: String, _ property: String) -> Return {
        Return(.property(variable: variable, property: property))
    }
    
    public static func count(_ variable: String) -> Return {
        Return(.count(variable))
    }
    
    public static var all: Return {
        Return(.all)
    }
}

// MARK: - Where

public struct Where {
    internal let clause: WhereClause
    
    public init(_ conditions: WhereCondition...) {
        self.clause = WhereClause(conditions: conditions)
    }
    
    public init(_ conditions: [WhereCondition]) {
        self.clause = WhereClause(conditions: conditions)
    }
}

// MARK: - OrderBy

public struct OrderBy {
    internal let clause: OrderByClause
    
    public init(_ items: OrderByItem...) {
        self.clause = OrderByClause(items: items)
    }
    
    public init(_ items: [OrderByItem]) {
        self.clause = OrderByClause(items: items)
    }
    
    public static func ascending(_ variable: String, _ property: String? = nil) -> OrderBy {
        OrderBy(OrderByItem(variable: variable, property: property, direction: .ascending))
    }
    
    public static func descending(_ variable: String, _ property: String? = nil) -> OrderBy {
        OrderBy(OrderByItem(variable: variable, property: property, direction: .descending))
    }
}

// MARK: - Limit & Skip

public struct Limit {
    internal let count: Int
    
    public init(_ count: Int) {
        self.count = count
    }
}

public struct Skip {
    internal let count: Int
    
    public init(_ count: Int) {
        self.count = count
    }
}