import Foundation

public struct Query<T> {
    let components: [QueryComponent]
    let returnType: T.Type
    
    init(components: [QueryComponent], returnType: T.Type) {
        self.components = components
        self.returnType = returnType
    }
}

public enum QueryComponent {
    case match(MatchClause)
    case create(CreateClause)
    case merge(MergeClause)
    case set(SetClause)
    case delete(DeleteClause)
    case `return`(ReturnClause)
    case `where`(WhereClause)
    case orderBy(OrderByClause)
    case limit(Int)
    case skip(Int)
}

public struct MatchClause {
    let variable: String
    let type: any _KuzuGraphModel.Type
    var predicates: [WhereCondition]
    
    init(variable: String? = nil, type: any _KuzuGraphModel.Type, predicates: [WhereCondition] = []) {
        self.variable = variable ?? type._kuzuTableName.lowercased()
        self.type = type
        self.predicates = predicates
    }
}

public struct CreateClause {
    let variable: String
    let type: any _KuzuGraphModel.Type
    let properties: [String: Any]
    
    init(variable: String? = nil, type: any _KuzuGraphModel.Type, properties: [String: Any] = [:]) {
        self.variable = variable ?? type._kuzuTableName.lowercased()
        self.type = type
        self.properties = properties
    }
}

public struct MergeClause {
    let variable: String
    let type: any _KuzuGraphModel.Type
    let matchProperties: [String: Any]
    let onCreateProperties: [String: Any]
    let onMatchProperties: [String: Any]
}

public struct SetClause {
    let variable: String
    let property: String
    let value: Any
}

public struct DeleteClause {
    let variable: String
    let detach: Bool
}

public struct ReturnClause {
    let items: [ReturnItem]
}

public enum ReturnItem {
    case variable(String)
    case property(variable: String, property: String)
    case alias(expression: String, alias: String)
    case count(String)
    case all
}

public struct WhereClause {
    let conditions: [WhereCondition]
}

public struct WhereCondition {
    let keyPath: AnyKeyPath
    let predicate: Any
}

public struct OrderByClause {
    let items: [OrderByItem]
}

public struct OrderByItem {
    let variable: String
    let property: String?
    let direction: OrderDirection
}

public enum OrderDirection {
    case ascending
    case descending
}