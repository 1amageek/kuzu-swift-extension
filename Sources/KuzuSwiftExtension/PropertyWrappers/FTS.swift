import Foundation

@propertyWrapper
public struct FTS: Sendable {
    public var wrappedValue: String
    
    public init(wrappedValue: String) {
        self.wrappedValue = wrappedValue
    }
}