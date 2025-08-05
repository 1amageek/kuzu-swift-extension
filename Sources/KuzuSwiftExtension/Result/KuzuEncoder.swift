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
        
        // Handle _StorageRef containers by extracting their array
        if container is _StorageRef {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Top-level \(T.self) encoded to an array, not a dictionary."
                )
            )
        }
        
        // Handle _DictStorageRef containers by extracting their dictionary
        if let dictStorageRef = container as? _DictStorageRef {
            return dictStorageRef.dict
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
        
        // Handle _StorageRef containers by extracting their array
        if let storageRef = value as? _StorageRef {
            return storageRef.array.map { encodeValue($0) }
        }
        
        // Handle _DictStorageRef containers by extracting their dictionary
        if let dictStorageRef = value as? _DictStorageRef {
            return dictStorageRef.dict.mapValues { encodeValue($0) }
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
        self.container = container.storageRef
        return KeyedEncodingContainer(container)
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        let container = _KuzuUnkeyedEncodingContainer(
            configuration: configuration,
            codingPath: codingPath
        )
        self.container = container.storageRef
        return container
    }
    
    func singleValueContainer() -> SingleValueEncodingContainer {
        let container = _KuzuSingleValueEncodingContainer(
            configuration: configuration,
            codingPath: codingPath,
            encoder: self
        )
        return container
    }
}

// MARK: - KeyedEncodingContainer Implementation

private struct _KuzuKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let configuration: KuzuEncoder.Configuration
    var codingPath: [CodingKey]
    let storageRef: _DictStorageRef
    var storage: [String: any Sendable] { storageRef.dict }
    
    init(configuration: KuzuEncoder.Configuration, codingPath: [CodingKey]) {
        self.configuration = configuration
        self.codingPath = codingPath
        self.storageRef = _DictStorageRef()
    }
    
    mutating func encodeNil(forKey key: Key) throws {
        storageRef[keyString(for: key)] = NSNull()
    }
    
    mutating func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
        let keyString = self.keyString(for: key)
        
        // Handle Date with strategy
        if let date = value as? Date {
            storageRef[keyString] = try encodeDate(date)
            return
        }
        
        // Handle Data with strategy
        if let data = value as? Data {
            storageRef[keyString] = try encodeData(data)
            return
        }
        
        // Handle primitive types directly
        switch value {
        case let string as String:
            storageRef[keyString] = string
        case let int as Int:
            storageRef[keyString] = int
        case let int8 as Int8:
            storageRef[keyString] = int8
        case let int16 as Int16:
            storageRef[keyString] = int16
        case let int32 as Int32:
            storageRef[keyString] = int32
        case let int64 as Int64:
            storageRef[keyString] = int64
        case let uint as UInt:
            storageRef[keyString] = uint
        case let uint8 as UInt8:
            storageRef[keyString] = uint8
        case let uint16 as UInt16:
            storageRef[keyString] = uint16
        case let uint32 as UInt32:
            storageRef[keyString] = uint32
        case let uint64 as UInt64:
            storageRef[keyString] = uint64
        case let float as Float:
            storageRef[keyString] = float
        case let double as Double:
            storageRef[keyString] = double
        case let bool as Bool:
            storageRef[keyString] = bool
        case let uuid as UUID:
            storageRef[keyString] = uuid.uuidString
        case let url as URL:
            storageRef[keyString] = url.absoluteString
        default:
            // For complex Encodable types
            let encoder = _KuzuEncoder(configuration: configuration)
            encoder.codingPath = codingPath + [key]
            try value.encode(to: encoder)
            
            if let container = encoder.container {
                // Handle _StorageRef containers by extracting their array
                if let nestedStorageRef = container as? _StorageRef {
                    storageRef[keyString] = nestedStorageRef.array
                } else if let dictStorageRef = container as? _DictStorageRef {
                    storageRef[keyString] = dictStorageRef.dict
                } else {
                    storageRef[keyString] = container
                }
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
        storageRef[keyString(for: key)] = container.storage
        return KeyedEncodingContainer(container)
    }
    
    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        let container = _KuzuUnkeyedEncodingContainer(
            configuration: configuration,
            codingPath: codingPath + [key]
        )
        storageRef[keyString(for: key)] = container.storage
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
    let storageRef: _StorageRef
    var count: Int { storageRef.count }
    var storage: [any Sendable] { storageRef.array }
    
    init(configuration: KuzuEncoder.Configuration, codingPath: [CodingKey]) {
        self.configuration = configuration
        self.codingPath = codingPath
        self.storageRef = _StorageRef()
    }
    
    mutating func encodeNil() throws {
        storageRef.append(NSNull())
    }
    
    mutating func encode<T>(_ value: T) throws where T: Encodable {
        // Handle Date with strategy
        if let date = value as? Date {
            storageRef.append(try encodeDate(date))
            return
        }
        
        // Handle Data with strategy
        if let data = value as? Data {
            storageRef.append(try encodeData(data))
            return
        }
        
        // Handle primitive types directly
        switch value {
        case let string as String:
            storageRef.append(string)
        case let int as Int:
            storageRef.append(int)
        case let int8 as Int8:
            storageRef.append(int8)
        case let int16 as Int16:
            storageRef.append(int16)
        case let int32 as Int32:
            storageRef.append(int32)
        case let int64 as Int64:
            storageRef.append(int64)
        case let uint as UInt:
            storageRef.append(uint)
        case let uint8 as UInt8:
            storageRef.append(uint8)
        case let uint16 as UInt16:
            storageRef.append(uint16)
        case let uint32 as UInt32:
            storageRef.append(uint32)
        case let uint64 as UInt64:
            storageRef.append(uint64)
        case let float as Float:
            storageRef.append(float)
        case let double as Double:
            storageRef.append(double)
        case let bool as Bool:
            storageRef.append(bool)
        case let uuid as UUID:
            storageRef.append(uuid.uuidString)
        case let url as URL:
            storageRef.append(url.absoluteString)
        default:
            // For complex Encodable types
            let encoder = _KuzuEncoder(configuration: configuration)
            encoder.codingPath = codingPath + [_KuzuKey(index: count)]
            try value.encode(to: encoder)
            
            if let container = encoder.container {
                // Handle _StorageRef containers by extracting their array
                if let nestedStorageRef = container as? _StorageRef {
                    storageRef.append(nestedStorageRef.array)
                } else if let dictStorageRef = container as? _DictStorageRef {
                    storageRef.append(dictStorageRef.dict)
                } else {
                    storageRef.append(container)
                }
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
        storageRef.append(container.storage)
        return KeyedEncodingContainer(container)
    }
    
    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let container = _KuzuUnkeyedEncodingContainer(
            configuration: configuration,
            codingPath: codingPath + [_KuzuKey(index: count)]
        )
        storageRef.append(container.storageRef)
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
    weak var encoder: _KuzuEncoder?
    
    mutating func encodeNil() throws {
        storage = NSNull()
        encoder?.container = storage
    }
    
    mutating func encode<T>(_ value: T) throws where T: Encodable {
        // Handle Date with strategy
        if let date = value as? Date {
            storage = try encodeDate(date)
            encoder?.container = storage
            return
        }
        
        // Handle Data with strategy
        if let data = value as? Data {
            storage = try encodeData(data)
            encoder?.container = storage
            return
        }
        
        // Handle primitive types directly
        switch value {
        case let string as String:
            storage = string
            encoder?.container = storage
        case let int as Int:
            storage = int
            encoder?.container = storage
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
            encoder?.container = storage
        case let uuid as UUID:
            storage = uuid.uuidString
            encoder?.container = storage
        case let url as URL:
            storage = url.absoluteString
        default:
            // For complex Encodable types
            let encoder = _KuzuEncoder(configuration: configuration)
            encoder.codingPath = codingPath
            try value.encode(to: encoder)
            storage = encoder.container
        }
        self.encoder?.container = storage
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

private final class _StorageRef: @unchecked Sendable {
    private var _array: [any Sendable] = []
    private let lock = NSLock()
    
    var array: [any Sendable] {
        lock.lock()
        defer { lock.unlock() }
        return _array
    }
    
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _array.count
    }
    
    func append(_ element: any Sendable) {
        lock.lock()
        defer { lock.unlock() }
        _array.append(element)
    }
}

private final class _DictStorageRef: @unchecked Sendable {
    private var _dict: [String: any Sendable] = [:]
    private let lock = NSLock()
    
    var dict: [String: any Sendable] {
        lock.lock()
        defer { lock.unlock() }
        return _dict
    }
    
    subscript(key: String) -> (any Sendable)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _dict[key]
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _dict[key] = newValue
        }
    }
}

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
