import Foundation

public enum TimestampDefault {
    case now
}

@propertyWrapper
public struct Timestamp: Sendable {
    public var wrappedValue: Date
    public let defaultValue: TimestampDefault?
    
    public init(wrappedValue: Date, default defaultValue: TimestampDefault? = nil) {
        self.wrappedValue = wrappedValue
        self.defaultValue = defaultValue
    }
}