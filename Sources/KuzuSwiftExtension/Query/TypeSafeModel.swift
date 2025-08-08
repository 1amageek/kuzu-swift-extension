import Foundation

/// Protocol for type-safe model references
public protocol TypeSafeModelReference {
    var cypherTypeName: String { get }
    var defaultAlias: String { get }
}

/// Concrete implementation for model types
public struct ModelReference<T: _KuzuGraphModel>: TypeSafeModelReference {
    public let modelType: T.Type
    
    public init(_ type: T.Type) {
        self.modelType = type
    }
    
    public var cypherTypeName: String {
        // Extract the type name without module prefix
        let fullName = String(describing: modelType)
        return fullName.components(separatedBy: ".").last ?? fullName
    }
    
    public var defaultAlias: String {
        return cypherTypeName.lowercased()
    }
}

/// Factory function for cleaner syntax
public func model<T: _KuzuGraphModel>(_ type: T.Type) -> ModelReference<T> {
    return ModelReference(type)
}

/// Type-safe edge reference
public struct EdgeReference<T: _KuzuGraphModel> {
    public let edgeType: T.Type
    
    public init(_ type: T.Type) {
        self.edgeType = type
    }
    
    public var cypherTypeName: String {
        let fullName = String(describing: edgeType)
        return fullName.components(separatedBy: ".").last ?? fullName
    }
    
    public var defaultAlias: String {
        return cypherTypeName.lowercased()
    }
}

/// Factory function for edge references
public func edge<T: _KuzuGraphModel>(_ type: T.Type) -> EdgeReference<T> {
    return EdgeReference(type)
}

/// Type-safe node pattern for Match queries
public struct TypeSafeNodePattern {
    public let type: any _KuzuGraphModel.Type
    public let alias: String
    public let predicate: Predicate?
    
    public init<T: _KuzuGraphModel>(
        _ type: T.Type,
        as alias: String? = nil,
        where predicate: Predicate? = nil
    ) {
        self.type = type
        let typeName = String(describing: type).components(separatedBy: ".").last ?? String(describing: type)
        self.alias = alias ?? typeName.lowercased()
        self.predicate = predicate
    }
    
    public var typeName: String {
        String(describing: type).components(separatedBy: ".").last ?? String(describing: type)
    }
}

/// Type-safe edge pattern for Match queries
public struct TypeSafeEdgePattern {
    public let type: any _KuzuGraphModel.Type
    public let from: String
    public let to: String
    public let alias: String?
    public let predicate: Predicate?
    
    public init<T: _KuzuGraphModel>(
        _ type: T.Type,
        from: String,
        to: String,
        as alias: String? = nil,
        where predicate: Predicate? = nil
    ) {
        self.type = type
        self.from = from
        self.to = to
        self.alias = alias
        self.predicate = predicate
    }
    
    public var typeName: String {
        String(describing: type).components(separatedBy: ".").last ?? String(describing: type)
    }
}