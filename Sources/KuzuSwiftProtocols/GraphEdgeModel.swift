import Foundation

// MARK: - GraphEdgeModel Protocol for edge operations
public protocol GraphEdgeModel: _KuzuGraphModel, Codable {
    static var edgeName: String { get }
}

public extension GraphEdgeModel {
    static var edgeName: String {
        String(describing: Self.self)
    }
}