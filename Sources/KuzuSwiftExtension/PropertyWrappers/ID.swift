import Foundation

@propertyWrapper
public struct ID<Value: Codable & Sendable>: Sendable {
    public var wrappedValue: Value
    
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}