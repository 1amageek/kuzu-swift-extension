import Foundation

/// An encoder that converts Swift Codable types into Kuzu-compatible values
public struct KuzuEncoder: Sendable {
    /// Configuration options for encoding
    public struct Configuration: Sendable {
        public var dateEncodingStrategy: DateEncodingStrategy = .iso8601
        public var dataEncodingStrategy: DataEncodingStrategy = .base64
        public var keyEncodingStrategy: KeyEncodingStrategy = .useDefaultKeys
        public var userInfo: [CodingUserInfoKey: any Sendable] = [:]
        
        public init() {}
    }
    
    /// Strategy for encoding dates
    public enum DateEncodingStrategy: Sendable {
        case iso8601
        case secondsSince1970
        case millisecondsSince1970
        case custom(@Sendable (Date) throws -> any Sendable)
    }
    
    /// Strategy for encoding data
    public enum DataEncodingStrategy: Sendable {
        case base64
        case custom(@Sendable (Data) throws -> any Sendable)
    }
    
    /// Strategy for encoding keys
    public enum KeyEncodingStrategy: Sendable {
        case useDefaultKeys
        case convertToSnakeCase
        case custom(@Sendable (String) -> String)
    }
    
    public var configuration: Configuration
    
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }
    
    /// Encodes a Codable value to a dictionary
    public func encode<T: Encodable>(_ value: T) throws -> [String: any Sendable] {
        let encoder = _KuzuEncoder(configuration: configuration)
        try value.encode(to: encoder)
        
        guard let container = encoder.container else {
            return [:]
        }
        
        guard let dictionary = container as? [String: any Sendable] else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Top-level \(T.self) did not encode to a dictionary."
                )
            )
        }
        
        return dictionary
    }
    
    /// Encodes an array of Codable values
    public func encodeArray<T: Encodable>(_ values: [T]) throws -> [[String: any Sendable]] {
        return try values.map { try encode($0) }
    }
    
    /// Encodes parameters for Kuzu queries
    public func encodeParameters(_ parameters: [String: any Sendable]) throws -> [String: Any?] {
        var result: [String: Any?] = [:]
        
        for (key, value) in parameters {
            result[key] = encodeValue(value)
        }
        
        return result
    }
    
    private func encodeValue(_ value: any Sendable) -> Any? {
        // Handle nil/NSNull
        if value is NSNull {
            return nil
        }
        
        // Handle arrays and dictionaries recursively
        if let array = value as? [any Sendable] {
            return array.map { encodeValue($0) }
        }
        
        if let dict = value as? [String: any Sendable] {
            return dict.mapValues { encodeValue($0) }
        }
        
        // All other values pass through
        return value
    }
}

// MARK: - Internal Encoder Implementation

private class _KuzuEncoder: Encoder {
    let configuration: KuzuEncoder.Configuration
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] { 
        // Convert Sendable values to Any for Encoder protocol compatibility
        configuration.userInfo.reduce(into: [:]) { result, pair in
            result[pair.key] = pair.value
        }
    }
    
    var container: (any Sendable)?
    
    init(configuration: KuzuEncoder.Configuration) {
        self.configuration = configuration
    }
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        let container = _KuzuKeyedEncodingContainer<Key>(
            configuration: configuration,
            codingPath: codingPath
        )
        self.container = container.storage
        return KeyedEncodingContainer(container)
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        let container = _KuzuUnkeyedEncodingContainer(
            configuration: configuration,
            codingPath: codingPath
        )
        self.container = container.storage
        return container
    }
    
    func singleValueContainer() -> SingleValueEncodingContainer {
        let container = _KuzuSingleValueEncodingContainer(
            configuration: configuration,
            codingPath: codingPath
        )
        return container
    }
}

// MARK: - KeyedEncodingContainer Implementation

private struct _KuzuKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let configuration: KuzuEncoder.Configuration
    var codingPath: [CodingKey]
    var storage: [String: any Sendable] = [:]
    
    mutating func encodeNil(forKey key: Key) throws {
        storage[keyString(for: key)] = NSNull()
    }
    
    mutating func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
        let keyString = self.keyString(for: key)
        
        // Handle Date with strategy
        if let date = value as? Date {
            storage[keyString] = try encodeDate(date)
            return
        }
        
        // Handle Data with strategy
        if let data = value as? Data {
            storage[keyString] = try encodeData(data)
            return
        }
        
        // Handle primitive types directly
        switch value {
        case let string as String:
            storage[keyString] = string
        case let int as Int:
            storage[keyString] = int
        case let int8 as Int8:
            storage[keyString] = int8
        case let int16 as Int16:
            storage[keyString] = int16
        case let int32 as Int32:
            storage[keyString] = int32
        case let int64 as Int64:
            storage[keyString] = int64
        case let uint as UInt:
            storage[keyString] = uint
        case let uint8 as UInt8:
            storage[keyString] = uint8
        case let uint16 as UInt16:
            storage[keyString] = uint16
        case let uint32 as UInt32:
            storage[keyString] = uint32
        case let uint64 as UInt64:
            storage[keyString] = uint64
        case let float as Float:
            storage[keyString] = float
        case let double as Double:
            storage[keyString] = double
        case let bool as Bool:
            storage[keyString] = bool
        case let uuid as UUID:
            storage[keyString] = uuid.uuidString
        case let url as URL:
            storage[keyString] = url.absoluteString
        default:
            // For complex Encodable types
            let encoder = _KuzuEncoder(configuration: configuration)
            encoder.codingPath = codingPath + [key]
            try value.encode(to: encoder)
            
            if let container = encoder.container {
                storage[keyString] = container
            }
        }
    }
    
    private func encodeDate(_ date: Date) throws -> any Sendable {
        switch configuration.dateEncodingStrategy {
        case .iso8601:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter.string(from: date)
        case .secondsSince1970:
            return date.timeIntervalSince1970
        case .millisecondsSince1970:
            return date.timeIntervalSince1970 * 1000
        case .custom(let converter):
            return try converter(date)
        }
    }
    
    private func encodeData(_ data: Data) throws -> any Sendable {
        switch configuration.dataEncodingStrategy {
        case .base64:
            return data.base64EncodedString()
        case .custom(let converter):
            return try converter(data)
        }
    }
    
    private func keyString(for key: Key) -> String {
        switch configuration.keyEncodingStrategy {
        case .useDefaultKeys:
            return key.stringValue
        case .convertToSnakeCase:
            return convertToSnakeCase(key.stringValue)
        case .custom(let converter):
            return converter(key.stringValue)
        }
    }
    
    private func convertToSnakeCase(_ string: String) -> String {
        guard !string.isEmpty else { return string }
        
        var result = ""
        var previousWasUppercase = false
        
        for (index, character) in string.enumerated() {
            if character.isUppercase {
                if index > 0 && !previousWasUppercase {
                    result += "_"
                }
                result += character.lowercased()
                previousWasUppercase = true
            } else {
                result += String(character)
                previousWasUppercase = false
            }
        }
        
        return result
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        let container = _KuzuKeyedEncodingContainer<NestedKey>(
            configuration: configuration,
            codingPath: codingPath + [key]
        )
        storage[keyString(for: key)] = container.storage
        return KeyedEncodingContainer(container)
    }
    
    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        let container = _KuzuUnkeyedEncodingContainer(
            configuration: configuration,
            codingPath: codingPath + [key]
        )
        storage[keyString(for: key)] = container.storage
        return container
    }
    
    mutating func superEncoder() -> Encoder {
        let encoder = _KuzuEncoder(configuration: configuration)
        encoder.codingPath = codingPath
        return encoder
    }
    
    mutating func superEncoder(forKey key: Key) -> Encoder {
        let encoder = _KuzuEncoder(configuration: configuration)
        encoder.codingPath = codingPath + [key]
        return encoder
    }
}

// MARK: - UnkeyedEncodingContainer Implementation

private struct _KuzuUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    let configuration: KuzuEncoder.Configuration
    var codingPath: [CodingKey]
    var count: Int { storage.count }
    var storage: [any Sendable] = []
    
    mutating func encodeNil() throws {
        storage.append(NSNull())
    }
    
    mutating func encode<T>(_ value: T) throws where T: Encodable {
        // Handle Date with strategy
        if let date = value as? Date {
            storage.append(try encodeDate(date))
            return
        }
        
        // Handle Data with strategy
        if let data = value as? Data {
            storage.append(try encodeData(data))
            return
        }
        
        // Handle primitive types directly
        switch value {
        case let string as String:
            storage.append(string)
        case let int as Int:
            storage.append(int)
        case let int8 as Int8:
            storage.append(int8)
        case let int16 as Int16:
            storage.append(int16)
        case let int32 as Int32:
            storage.append(int32)
        case let int64 as Int64:
            storage.append(int64)
        case let uint as UInt:
            storage.append(uint)
        case let uint8 as UInt8:
            storage.append(uint8)
        case let uint16 as UInt16:
            storage.append(uint16)
        case let uint32 as UInt32:
            storage.append(uint32)
        case let uint64 as UInt64:
            storage.append(uint64)
        case let float as Float:
            storage.append(float)
        case let double as Double:
            storage.append(double)
        case let bool as Bool:
            storage.append(bool)
        case let uuid as UUID:
            storage.append(uuid.uuidString)
        case let url as URL:
            storage.append(url.absoluteString)
        default:
            // For complex Encodable types
            let encoder = _KuzuEncoder(configuration: configuration)
            encoder.codingPath = codingPath + [_KuzuKey(index: count)]
            try value.encode(to: encoder)
            
            if let container = encoder.container {
                storage.append(container)
            }
        }
    }
    
    private func encodeDate(_ date: Date) throws -> any Sendable {
        switch configuration.dateEncodingStrategy {
        case .iso8601:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter.string(from: date)
        case .secondsSince1970:
            return date.timeIntervalSince1970
        case .millisecondsSince1970:
            return date.timeIntervalSince1970 * 1000
        case .custom(let converter):
            return try converter(date)
        }
    }
    
    private func encodeData(_ data: Data) throws -> any Sendable {
        switch configuration.dataEncodingStrategy {
        case .base64:
            return data.base64EncodedString()
        case .custom(let converter):
            return try converter(data)
        }
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        let container = _KuzuKeyedEncodingContainer<NestedKey>(
            configuration: configuration,
            codingPath: codingPath + [_KuzuKey(index: count)]
        )
        storage.append(container.storage)
        return KeyedEncodingContainer(container)
    }
    
    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let container = _KuzuUnkeyedEncodingContainer(
            configuration: configuration,
            codingPath: codingPath + [_KuzuKey(index: count)]
        )
        storage.append(container.storage)
        return container
    }
    
    mutating func superEncoder() -> Encoder {
        let encoder = _KuzuEncoder(configuration: configuration)
        encoder.codingPath = codingPath
        return encoder
    }
}

// MARK: - SingleValueEncodingContainer Implementation

private struct _KuzuSingleValueEncodingContainer: SingleValueEncodingContainer {
    let configuration: KuzuEncoder.Configuration
    var codingPath: [CodingKey]
    var storage: (any Sendable)?
    
    mutating func encodeNil() throws {
        storage = NSNull()
    }
    
    mutating func encode<T>(_ value: T) throws where T: Encodable {
        // Handle Date with strategy
        if let date = value as? Date {
            storage = try encodeDate(date)
            return
        }
        
        // Handle Data with strategy
        if let data = value as? Data {
            storage = try encodeData(data)
            return
        }
        
        // Handle primitive types directly
        switch value {
        case let string as String:
            storage = string
        case let int as Int:
            storage = int
        case let int8 as Int8:
            storage = int8
        case let int16 as Int16:
            storage = int16
        case let int32 as Int32:
            storage = int32
        case let int64 as Int64:
            storage = int64
        case let uint as UInt:
            storage = uint
        case let uint8 as UInt8:
            storage = uint8
        case let uint16 as UInt16:
            storage = uint16
        case let uint32 as UInt32:
            storage = uint32
        case let uint64 as UInt64:
            storage = uint64
        case let float as Float:
            storage = float
        case let double as Double:
            storage = double
        case let bool as Bool:
            storage = bool
        case let uuid as UUID:
            storage = uuid.uuidString
        case let url as URL:
            storage = url.absoluteString
        default:
            // For complex Encodable types
            let encoder = _KuzuEncoder(configuration: configuration)
            encoder.codingPath = codingPath
            try value.encode(to: encoder)
            storage = encoder.container
        }
    }
    
    private func encodeDate(_ date: Date) throws -> any Sendable {
        switch configuration.dateEncodingStrategy {
        case .iso8601:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter.string(from: date)
        case .secondsSince1970:
            return date.timeIntervalSince1970
        case .millisecondsSince1970:
            return date.timeIntervalSince1970 * 1000
        case .custom(let converter):
            return try converter(date)
        }
    }
    
    private func encodeData(_ data: Data) throws -> any Sendable {
        switch configuration.dataEncodingStrategy {
        case .base64:
            return data.base64EncodedString()
        case .custom(let converter):
            return try converter(data)
        }
    }
}

// MARK: - Helper Types

private struct _KuzuKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init(intValue: Int) {
        self.stringValue = "Index \(intValue)"
        self.intValue = intValue
    }
    
    init(index: Int) {
        self.stringValue = "Index \(index)"
        self.intValue = index
    }
}
