import Foundation

// MARK: - GraphEdgeModel Protocol for edge operations
public protocol GraphEdgeModel: _KuzuGraphModel, Codable {
    static var edgeName: String { get }
    static var _fromType: Any.Type { get }
    static var _toType: Any.Type { get }
}

public extension GraphEdgeModel {
    /// edgeName uses the unified name property from _KuzuGraphModel
    static var edgeName: String {
        name
    }
}