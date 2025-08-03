import Foundation

/// Represents a DELETE clause in a Cypher query
public struct Delete: QueryComponent {
    let items: [DeleteItem]
    let detach: Bool
    
    private init(items: [DeleteItem], detach: Bool = false) {
        self.items = items
        self.detach = detach
    }
    
    /// Creates a DELETE clause for one or more items
    public static func items(_ items: DeleteItem...) -> Delete {
        Delete(items: items)
    }
    
    /// Creates a DELETE clause for a single node or relationship
    public static func alias(_ alias: String) -> Delete {
        Delete(items: [.alias(alias)])
    }
    
    /// Creates a DELETE clause for multiple aliases
    public static func aliases(_ aliases: String...) -> Delete {
        Delete(items: aliases.map { .alias($0) })
    }
    
    /// Creates a DETACH DELETE clause (deletes nodes and their relationships)
    public static func detach(_ items: DeleteItem...) -> Delete {
        Delete(items: items, detach: true)
    }
    
    /// Creates a DETACH DELETE clause for a single node
    public static func detachNode(_ alias: String) -> Delete {
        Delete(items: [.alias(alias)], detach: true)
    }
    
    /// Creates a DETACH DELETE clause for multiple nodes
    public static func detachNodes(_ aliases: String...) -> Delete {
        Delete(items: aliases.map { .alias($0) }, detach: true)
    }
    
    /// Adds additional items to delete
    public func and(_ item: DeleteItem) -> Delete {
        Delete(items: items + [item], detach: detach)
    }
    
    /// Adds multiple additional items to delete
    public func and(_ newItems: DeleteItem...) -> Delete {
        Delete(items: items + newItems, detach: detach)
    }
    
    public func toCypher() throws -> CypherFragment {
        let itemStrings = items.map { item in
            switch item {
            case .alias(let alias):
                return alias
            case .property(let prop):
                return prop.cypher
            }
        }
        
        let deleteClause = detach ? "DETACH DELETE" : "DELETE"
        let query = "\(deleteClause) " + itemStrings.joined(separator: ", ")
        
        return CypherFragment(query: query)
    }
}

/// Items that can be deleted
public enum DeleteItem {
    case alias(String)
    case property(PropertyReference)
    
    /// Creates a delete item for a node or relationship alias
    public static func node(_ alias: String) -> DeleteItem {
        .alias(alias)
    }
    
    /// Creates a delete item for a relationship alias
    public static func relationship(_ alias: String) -> DeleteItem {
        .alias(alias)
    }
    
    /// Creates a delete item for a specific property
    public static func property(_ alias: String, _ propertyName: String) -> DeleteItem {
        .property(PropertyReference(alias: alias, property: propertyName))
    }
}

// MARK: - Convenience Extensions

extension String {
    /// Creates a DELETE clause for this alias
    public var delete: Delete {
        Delete.alias(self)
    }
    
    /// Creates a DETACH DELETE clause for this alias
    public var detachDelete: Delete {
        Delete.detachNode(self)
    }
}