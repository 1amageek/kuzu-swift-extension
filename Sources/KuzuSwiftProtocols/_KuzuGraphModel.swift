import Foundation

// Swift 6: Metatypes of Sendable types are automatically Sendable
public protocol _KuzuGraphModel: Sendable, SendableMetatype {
    static var _kuzuDDL: String { get }
    static var _kuzuColumns: [(name: String, type: String, constraints: [String])] { get }
}
