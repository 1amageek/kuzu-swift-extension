import Foundation

@propertyWrapper
public struct Vector<T: FloatingPoint & Codable>: Sendable where T: Sendable {
    public var wrappedValue: [T]
    public let dimensions: Int
    
    public init(wrappedValue: [T], dimensions: Int) {
        self.wrappedValue = wrappedValue
        self.dimensions = dimensions
    }
}