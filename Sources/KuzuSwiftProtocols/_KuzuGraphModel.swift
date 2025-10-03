import Foundation

// Swift 6: Metatypes of Sendable types are automatically Sendable
public protocol _KuzuGraphModel: Sendable {
    /// The name of the model (table name in database)
    static var name: String { get }

    static var _kuzuDDL: String { get }
    static var _kuzuColumns: [(propertyName: String, columnName: String, type: String, constraints: [String])] { get }
    static var _metadata: GraphMetadata { get }
}

public extension _KuzuGraphModel {
    /// Default implementation returns the type name
    static var name: String {
        String(describing: Self.self)
    }

    /// Default implementation returns empty metadata
    static var _metadata: GraphMetadata { .none }
}
