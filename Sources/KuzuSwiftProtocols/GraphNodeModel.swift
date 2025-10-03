import Foundation

// MARK: - GraphNodeModel Protocol for node operations
public protocol GraphNodeModel: _KuzuGraphModel, Codable {
    static var modelName: String { get }
}

public extension GraphNodeModel {
    /// modelName uses the unified name property from _KuzuGraphModel
    static var modelName: String {
        name
    }
}
