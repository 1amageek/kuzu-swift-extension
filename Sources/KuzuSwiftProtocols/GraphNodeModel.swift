import Foundation

// MARK: - GraphNodeModel Protocol for node operations
public protocol GraphNodeModel: _KuzuGraphModel, Codable {
    static var modelName: String { get }
}

public extension GraphNodeModel {
    static var modelName: String {
        String(describing: Self.self)
    }
}
