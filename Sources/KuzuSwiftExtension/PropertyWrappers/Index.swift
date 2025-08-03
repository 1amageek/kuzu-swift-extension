import Foundation

@propertyWrapper
public struct Index<Value: Codable & Sendable>: Sendable {
    public var wrappedValue: Value
    public let unique: Bool
    
    public init(wrappedValue: Value, unique: Bool = false) {
        self.wrappedValue = wrappedValue
        self.unique = unique
    }
}