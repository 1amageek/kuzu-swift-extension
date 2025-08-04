import Foundation

public protocol _KuzuGraphModel {
    static var _kuzuDDL: String { get }
    static var _kuzuColumns: [(name: String, type: String, constraints: [String])] { get }
}