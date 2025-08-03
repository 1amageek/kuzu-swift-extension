import Foundation

@_spi(Graph)
public protocol _KuzuGraphModel: Sendable {
    static var _kuzuDDL: [String] { get }
    static var _kuzuColumns: [ColumnMeta] { get }
    static var _kuzuTableName: String { get }
}

public struct ColumnMeta: Sendable {
    public let name: String
    public let kuzuType: String
    public let modifiers: [String]
    
    public init(name: String, kuzuType: String, modifiers: [String] = []) {
        self.name = name
        self.kuzuType = kuzuType
        self.modifiers = modifiers
    }
}

public protocol GraphNodeProtocol: _KuzuGraphModel {}

public protocol GraphEdgeProtocol: _KuzuGraphModel {
    associatedtype From: GraphNodeProtocol
    associatedtype To: GraphNodeProtocol
}