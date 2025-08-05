import Foundation
import Kuzu

/// A decoder that converts Kuzu query results into Swift Codable types
public struct KuzuDecoder: Sendable {
    /// Configuration options for decoding
    public struct Configuration: Sendable {
        public var dateDecodingStrategy: DateDecodingStrategy = .iso8601
        public var dataDecodingStrategy: DataDecodingStrategy = .base64
        public var keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys
        public var userInfo: [CodingUserInfoKey: any Sendable] = [:]
        
        public init() {}
    }
    
    /// Strategy for decoding dates
    public enum DateDecodingStrategy: Sendable {
        case iso8601
        case secondsSince1970
        case millisecondsSince1970
        case custom(@Sendable (Any?) throws -> Date)
    }
    
    /// Strategy for decoding data
    public enum DataDecodingStrategy: Sendable {
        case base64
        case custom(@Sendable (Any?) throws -> Data)
    }
    
    /// Strategy for decoding keys
    public enum KeyDecodingStrategy: Sendable {
        case useDefaultKeys
        case convertFromSnakeCase
        case custom(@Sendable ([CodingKey]) -> CodingKey)
    }
    
    public var configuration: Configuration
    
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }
    
    /// Decodes a single value from the first row of the query result
    public func decode<T: Decodable>(_ type: T.Type, from result: QueryResult) throws -> T {
        guard result.hasNext() else {
            throw ResultMappingError.noResults
        }
        
        guard let flatTuple = try result.getNext() else {
            throw ResultMappingError.noResults
        }
        
        let dictionary = try flatTuple.getAsDictionary()
        
        // If the dictionary has a single key and its value is a dictionary,
        // it's likely a node result (e.g., from "RETURN n")
        if dictionary.count == 1,
           let firstValue = dictionary.values.first {
            // Handle KuzuNode type
            if let nodeProperties = extractNodeProperties(from: firstValue) {
                return try decode(type, from: nodeProperties)
            }
            // Handle plain dictionary
            else if let nodeDict = firstValue as? [String: Any?] {
                return try decode(type, from: nodeDict)
            }
        }
        
        return try decode(type, from: dictionary)
    }
    
    /// Decodes an optional value from the first row of the query result
    public func decodeIfPresent<T: Decodable>(_ type: T.Type, from result: QueryResult) throws -> T? {
        guard result.hasNext() else {
            return nil
        }
        
        guard let flatTuple = try result.getNext() else {
            return nil
        }
        
        let dictionary = try flatTuple.getAsDictionary()
        
        // If the dictionary has a single key and its value is a dictionary,
        // it's likely a node result (e.g., from "RETURN n")
        if dictionary.count == 1,
           let firstValue = dictionary.values.first {
            // Handle KuzuNode type
            if let nodeProperties = extractNodeProperties(from: firstValue) {
                return try decode(type, from: nodeProperties)
            }
            // Handle plain dictionary
            else if let nodeDict = firstValue as? [String: Any?] {
                return try decode(type, from: nodeDict)
            }
        }
        
        return try decode(type, from: dictionary)
    }
    
    /// Decodes all rows into an array of the specified type
    public func decodeArray<T: Decodable>(_ type: T.Type, from result: QueryResult) throws -> [T] {
        var results: [T] = []
        
        while result.hasNext() {
            guard let flatTuple = try result.getNext() else {
                break
            }
            
            let dictionary = try flatTuple.getAsDictionary()
            
            // If the dictionary has a single key and its value is a dictionary,
            // it's likely a node result (e.g., from "RETURN n")
            if dictionary.count == 1,
               let firstValue = dictionary.values.first {
                // Handle KuzuNode type
                if let nodeProperties = extractNodeProperties(from: firstValue) {
                    let decoded = try decode(type, from: nodeProperties)
                    results.append(decoded)
                }
                // Handle plain dictionary
                else if let nodeDict = firstValue as? [String: Any?] {
                    let decoded = try decode(type, from: nodeDict)
                    results.append(decoded)
                }
            } else {
                let decoded = try decode(type, from: dictionary)
                results.append(decoded)
            }
        }
        
        return results
    }
    
    /// Decodes a value from a dictionary
    public func decode<T: Decodable>(_ type: T.Type, from dictionary: [String: Any?]) throws -> T {
        // Clean the dictionary to handle nil values
        let cleanedDict = cleanDictionary(dictionary)
        
        // Use the new Codable-based decoder instead of JSONSerialization
        let decoder = _KuzuDecoder(dictionary: cleanedDict, configuration: configuration)
        
        do {
            return try T(from: decoder)
        } catch let decodingError as DecodingError {
            // Re-wrap DecodingError as ResultMappingError for consistency
            throw ResultMappingError.decodingFailed(
                field: String(describing: type),
                underlyingError: decodingError
            )
        } catch {
            throw ResultMappingError.decodingFailed(
                field: String(describing: type),
                underlyingError: error
            )
        }
    }
    
    /// Extracts properties from a KuzuNode if the value is a node type
    private func extractNodeProperties(from value: Any?) -> [String: Any?]? {
        guard let value = value else { return nil }
        
        // Use Mirror to access properties without importing Kuzu types
        let mirror = Mirror(reflecting: value)
        
        // Check if this is a KuzuNode by looking for properties field
        for child in mirror.children {
            if child.label == "properties",
               let properties = child.value as? [String: Any?] {
                return properties
            }
        }
        
        return nil
    }
    
    /// Cleans a dictionary for JSON serialization
    private func cleanDictionary(_ dictionary: [String: Any?]) -> [String: Any] {
        var cleaned: [String: Any] = [:]
        
        for (key, value) in dictionary {
            if let value = value {
                // Handle special Kuzu types
                if let array = value as? [Any?] {
                    cleaned[key] = array.compactMap { cleanValue($0 as Any) }
                } else if let dict = value as? [String: Any?] {
                    cleaned[key] = cleanDictionary(dict)
                } else {
                    cleaned[key] = cleanValue(value)
                }
            }
        }
        
        return cleaned
    }
    
    /// Cleans a single value for JSON serialization
    private func cleanValue(_ value: Any) -> Any {
        // Handle special cases first
        switch value {
        case let date as Date:
            // Convert dates based on strategy
            switch configuration.dateDecodingStrategy {
            case .iso8601:
                return ISO8601DateFormatter().string(from: date)
            case .secondsSince1970:
                return date.timeIntervalSince1970
            case .millisecondsSince1970:
                return date.timeIntervalSince1970 * 1000
            case .custom:
                return ISO8601DateFormatter().string(from: date)
            }
        case let data as Data:
            // Convert data based on strategy
            switch configuration.dataDecodingStrategy {
            case .base64:
                return data.base64EncodedString()
            case .custom:
                return data.base64EncodedString()
            }
        case let array as [Any]:
            return array.map { cleanValue($0) }
        case let dict as [String: Any]:
            return cleanDictionary(dict as [String: Any?])
        default:
            // Return value as-is for other types
            return value
        }
    }
}

// MARK: - QueryResult Extensions for Codable

extension QueryResult {
    /// Decodes the first result to a Codable type
    public func decode<T: Decodable>(_ type: T.Type, decoder: KuzuDecoder = KuzuDecoder()) throws -> T {
        return try decoder.decode(type, from: self)
    }
    
    /// Decodes the first result to an optional Codable type
    public func decodeIfPresent<T: Decodable>(_ type: T.Type, decoder: KuzuDecoder = KuzuDecoder()) throws -> T? {
        return try decoder.decodeIfPresent(type, from: self)
    }
    
    /// Decodes all results to an array of Codable types
    public func decodeArray<T: Decodable>(_ type: T.Type, decoder: KuzuDecoder = KuzuDecoder()) throws -> [T] {
        return try decoder.decodeArray(type, from: self)
    }
    
    /// Decodes the first result with a custom decoder configuration
    public func decode<T: Decodable>(_ type: T.Type, configuration: KuzuDecoder.Configuration) throws -> T {
        let decoder = KuzuDecoder(configuration: configuration)
        return try decoder.decode(type, from: self)
    }
}

// MARK: - Internal Codable-based Decoder Implementation

/// Internal decoder that implements the Decoder protocol
private class _KuzuDecoder: Decoder {
    let dictionary: [String: Any]
    let configuration: KuzuDecoder.Configuration
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] { 
        // Convert Sendable values to Any for Decoder protocol compatibility
        configuration.userInfo.reduce(into: [:]) { result, pair in
            result[pair.key] = pair.value
        }
    }
    
    init(dictionary: [String: Any], configuration: KuzuDecoder.Configuration) {
        self.dictionary = dictionary
        self.configuration = configuration
    }
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        let container = _KuzuKeyedDecodingContainer<Key>(
            dictionary: dictionary,
            configuration: configuration,
            codingPath: codingPath
        )
        return KeyedDecodingContainer(container)
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw DecodingError.typeMismatch(
            [Any].self,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected array but found dictionary"
            )
        )
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        return _KuzuSingleValueDecodingContainer(
            dictionary: dictionary,
            configuration: configuration,
            codingPath: codingPath
        )
    }
}

// MARK: - KeyedDecodingContainer Implementation

private struct _KuzuKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let dictionary: [String: Any]
    let configuration: KuzuDecoder.Configuration
    var codingPath: [CodingKey]
    var allKeys: [Key] {
        dictionary.keys.compactMap { Key(stringValue: $0) }
    }
    
    func contains(_ key: Key) -> Bool {
        dictionary.keys.contains(key.stringValue)
    }
    
    func decodeNil(forKey key: Key) throws -> Bool {
        guard let value = dictionary[key.stringValue] else { return true }
        return value is NSNull
    }
    
    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
        guard let value = dictionary[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "No value associated with key \(key.stringValue)"
                )
            )
        }
        
        return try decodeValue(value, as: type, for: key)
    }
    
    private func decodeValue<T>(_ value: Any, as type: T.Type, for key: CodingKey) throws -> T where T: Decodable {
        // Handle special types first
        if let convertedValue = try convertSpecialTypes(value, to: type) {
            return convertedValue
        }
        
        // Handle basic types
        if let typedValue = value as? T {
            return typedValue
        }
        
        // Handle arrays
        if let array = value as? [Any] {
            let decoder = _KuzuArrayDecoder(array: array, configuration: configuration)
            decoder.codingPath = codingPath + [key]
            return try T(from: decoder)
        }
        
        // Handle nested Decodable types
        if let dict = value as? [String: Any] {
            let decoder = _KuzuDecoder(dictionary: dict, configuration: configuration)
            decoder.codingPath = codingPath + [key]
            return try T(from: decoder)
        }
        
        throw DecodingError.typeMismatch(
            type,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected \(type) but found \(Swift.type(of: value))"
            )
        )
    }
    
    private func convertSpecialTypes<T>(_ value: Any, to type: T.Type) throws -> T? {
        // UUID conversion
        if type == UUID.self {
            if let uuidString = value as? String,
               let uuid = UUID(uuidString: uuidString) {
                return uuid as? T
            }
        }
        
        // Date conversion
        if type == Date.self {
            if let date = try? convertToDate(value) {
                return date as? T
            }
        }
        
        // Data conversion
        if type == Data.self {
            if let data = try? convertToData(value) {
                return data as? T
            }
        }
        
        // Try type-specific conversions
        switch (value, type) {
        case (let double as Double, is Date.Type):
            return Date(timeIntervalSince1970: double) as? T
        case (let int as Int, is Date.Type):
            return Date(timeIntervalSince1970: Double(int)) as? T
        case (let int64 as Int64, is Date.Type):
            return Date(timeIntervalSince1970: Double(int64)) as? T
        case (let string as String, is UUID.Type):
            return UUID(uuidString: string) as? T
        case (let int as Int, is Int64.Type):
            return Int64(int) as? T
        case (let int64 as Int64, is Int.Type):
            return Int(int64) as? T
        case (let int as Int, is Double.Type):
            return Double(int) as? T
        case (let float as Float, is Double.Type):
            return Double(float) as? T
        default:
            return nil
        }
    }
    
    private func convertToDate(_ value: Any) throws -> Date {
        switch configuration.dateDecodingStrategy {
        case .iso8601:
            if let dateString = value as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: dateString) {
                    return date
                }
                // Try without fractional seconds
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }
        case .secondsSince1970:
            if let timestamp = value as? Double {
                return Date(timeIntervalSince1970: timestamp)
            } else if let timestamp = value as? Int {
                return Date(timeIntervalSince1970: Double(timestamp))
            }
        case .millisecondsSince1970:
            if let timestamp = value as? Double {
                return Date(timeIntervalSince1970: timestamp / 1000)
            } else if let timestamp = value as? Int {
                return Date(timeIntervalSince1970: Double(timestamp) / 1000)
            }
        case .custom(let converter):
            return try converter(value)
        }
        
        throw DecodingError.typeMismatch(
            Date.self,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Cannot convert \(value) to Date"
            )
        )
    }
    
    private func convertToData(_ value: Any) throws -> Data {
        switch configuration.dataDecodingStrategy {
        case .base64:
            if let base64String = value as? String {
                if let data = Data(base64Encoded: base64String) {
                    return data
                }
            }
        case .custom(let converter):
            return try converter(value)
        }
        
        throw DecodingError.typeMismatch(
            Data.self,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Cannot convert \(value) to Data"
            )
        )
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        guard let dict = dictionary[key.stringValue] as? [String: Any] else {
            throw DecodingError.typeMismatch(
                [String: Any].self,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "Expected dictionary for nested container"
                )
            )
        }
        
        let container = _KuzuKeyedDecodingContainer<NestedKey>(
            dictionary: dict,
            configuration: configuration,
            codingPath: codingPath + [key]
        )
        return KeyedDecodingContainer(container)
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        guard let array = dictionary[key.stringValue] as? [Any] else {
            throw DecodingError.typeMismatch(
                [Any].self,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "Expected array for unkeyed container"
                )
            )
        }
        
        return _KuzuUnkeyedDecodingContainer(
            array: array,
            configuration: configuration,
            codingPath: codingPath + [key]
        )
    }
    
    func superDecoder() throws -> Decoder {
        let decoder = _KuzuDecoder(dictionary: dictionary, configuration: configuration)
        decoder.codingPath = codingPath
        return decoder
    }
    
    func superDecoder(forKey key: Key) throws -> Decoder {
        guard let dict = dictionary[key.stringValue] as? [String: Any] else {
            throw DecodingError.typeMismatch(
                [String: Any].self,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "Expected dictionary for super decoder"
                )
            )
        }
        
        let decoder = _KuzuDecoder(dictionary: dict, configuration: configuration)
        decoder.codingPath = codingPath + [key]
        return decoder
    }
}

// MARK: - SingleValueDecodingContainer Implementation

private struct _KuzuSingleValueDecodingContainer: SingleValueDecodingContainer {
    let dictionary: [String: Any]
    let configuration: KuzuDecoder.Configuration
    var codingPath: [CodingKey]
    
    func decodeNil() -> Bool {
        dictionary.isEmpty || dictionary.values.allSatisfy { $0 is NSNull }
    }
    
    func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        // If dictionary has single value, decode that
        if dictionary.count == 1, let value = dictionary.values.first {
            return try decodeValue(value, as: type)
        }
        
        // Otherwise, decode the whole dictionary as the type
        let decoder = _KuzuDecoder(dictionary: dictionary, configuration: configuration)
        decoder.codingPath = codingPath
        return try T(from: decoder)
    }
    
    private func decodeValue<T>(_ value: Any, as type: T.Type) throws -> T where T: Decodable {
        // Handle special types
        if type == UUID.self {
            if let uuidString = value as? String,
               let uuid = UUID(uuidString: uuidString) {
                return uuid as! T
            }
        }
        
        if type == Date.self {
            if let date = try? convertToDate(value) {
                return date as! T
            }
        }
        
        if type == Data.self {
            if let data = try? convertToData(value) {
                return data as! T
            }
        }
        
        // Handle basic types
        if let typedValue = value as? T {
            return typedValue
        }
        
        // Try type-specific conversions
        switch (value, type) {
        case (let double as Double, is Date.Type):
            if let date = Date(timeIntervalSince1970: double) as? T {
                return date
            }
        case (let int as Int, is Date.Type):
            if let date = Date(timeIntervalSince1970: Double(int)) as? T {
                return date
            }
        case (let int64 as Int64, is Date.Type):
            if let date = Date(timeIntervalSince1970: Double(int64)) as? T {
                return date
            }
        case (let string as String, is UUID.Type):
            if let uuid = UUID(uuidString: string) as? T {
                return uuid
            }
        case (let int as Int, is Int64.Type):
            if let value = Int64(int) as? T {
                return value
            }
        case (let int64 as Int64, is Int.Type):
            if let value = Int(int64) as? T {
                return value
            }
        case (let int as Int, is Double.Type):
            if let value = Double(int) as? T {
                return value
            }
        case (let float as Float, is Double.Type):
            if let value = Double(float) as? T {
                return value
            }
        default:
            break
        }
        
        throw DecodingError.typeMismatch(
            type,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Cannot convert \(value) to \(type)"
            )
        )
    }
    
    private func convertToDate(_ value: Any) throws -> Date {
        switch configuration.dateDecodingStrategy {
        case .iso8601:
            if let dateString = value as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: dateString) {
                    return date
                }
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }
        case .secondsSince1970:
            if let timestamp = value as? Double {
                return Date(timeIntervalSince1970: timestamp)
            } else if let timestamp = value as? Int {
                return Date(timeIntervalSince1970: Double(timestamp))
            }
        case .millisecondsSince1970:
            if let timestamp = value as? Double {
                return Date(timeIntervalSince1970: timestamp / 1000)
            } else if let timestamp = value as? Int {
                return Date(timeIntervalSince1970: Double(timestamp) / 1000)
            }
        case .custom(let converter):
            return try converter(value)
        }
        
        throw DecodingError.typeMismatch(
            Date.self,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Cannot convert \(value) to Date"
            )
        )
    }
    
    private func convertToData(_ value: Any) throws -> Data {
        switch configuration.dataDecodingStrategy {
        case .base64:
            if let base64String = value as? String,
               let data = Data(base64Encoded: base64String) {
                return data
            }
        case .custom(let converter):
            return try converter(value)
        }
        
        throw DecodingError.typeMismatch(
            Data.self,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Cannot convert \(value) to Data"
            )
        )
    }
}

// MARK: - UnkeyedDecodingContainer Implementation

private struct _KuzuUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    let array: [Any]
    let configuration: KuzuDecoder.Configuration
    var codingPath: [CodingKey]
    var count: Int? { array.count }
    var isAtEnd: Bool { currentIndex >= array.count }
    private(set) var currentIndex: Int = 0
    
    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(
                Any?.self,
                DecodingError.Context(
                    codingPath: codingPath + [IndexKey(intValue: currentIndex)],
                    debugDescription: "Unkeyed container is at end"
                )
            )
        }
        
        if array[currentIndex] is NSNull {
            currentIndex += 1
            return true
        }
        
        return false
    }
    
    mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(
                type,
                DecodingError.Context(
                    codingPath: codingPath + [IndexKey(intValue: currentIndex)],
                    debugDescription: "Unkeyed container is at end"
                )
            )
        }
        
        let value = array[currentIndex]
        currentIndex += 1
        
        return try decodeValue(value, as: type)
    }
    
    private func decodeValue<T>(_ value: Any, as type: T.Type) throws -> T where T: Decodable {
        // Handle special types
        if type == UUID.self {
            if let uuidString = value as? String,
               let uuid = UUID(uuidString: uuidString) {
                return uuid as! T
            }
        }
        
        // Handle basic types
        if let typedValue = value as? T {
            return typedValue
        }
        
        // Handle nested Decodable types
        if let dict = value as? [String: Any] {
            let decoder = _KuzuDecoder(dictionary: dict, configuration: configuration)
            decoder.codingPath = codingPath + [IndexKey(intValue: currentIndex - 1)]
            return try T(from: decoder)
        }
        
        // Try type-specific conversions
        switch (value, type) {
        case (let double as Double, is Date.Type):
            if let date = Date(timeIntervalSince1970: double) as? T {
                return date
            }
        case (let int as Int, is Date.Type):
            if let date = Date(timeIntervalSince1970: Double(int)) as? T {
                return date
            }
        case (let int64 as Int64, is Date.Type):
            if let date = Date(timeIntervalSince1970: Double(int64)) as? T {
                return date
            }
        case (let string as String, is UUID.Type):
            if let uuid = UUID(uuidString: string) as? T {
                return uuid
            }
        case (let int as Int, is Int64.Type):
            if let value = Int64(int) as? T {
                return value
            }
        case (let int64 as Int64, is Int.Type):
            if let value = Int(int64) as? T {
                return value
            }
        case (let int as Int, is Double.Type):
            if let value = Double(int) as? T {
                return value
            }
        case (let float as Float, is Double.Type):
            if let value = Double(float) as? T {
                return value
            }
        default:
            break
        }
        
        throw DecodingError.typeMismatch(
            type,
            DecodingError.Context(
                codingPath: codingPath + [IndexKey(intValue: currentIndex - 1)],
                debugDescription: "Cannot convert \(value) to \(type)"
            )
        )
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(
                KeyedDecodingContainer<NestedKey>.self,
                DecodingError.Context(
                    codingPath: codingPath + [IndexKey(intValue: currentIndex)],
                    debugDescription: "Unkeyed container is at end"
                )
            )
        }
        
        guard let dict = array[currentIndex] as? [String: Any] else {
            throw DecodingError.typeMismatch(
                [String: Any].self,
                DecodingError.Context(
                    codingPath: codingPath + [IndexKey(intValue: currentIndex)],
                    debugDescription: "Expected dictionary"
                )
            )
        }
        
        currentIndex += 1
        
        let container = _KuzuKeyedDecodingContainer<NestedKey>(
            dictionary: dict,
            configuration: configuration,
            codingPath: codingPath + [IndexKey(intValue: currentIndex - 1)]
        )
        return KeyedDecodingContainer(container)
    }
    
    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(
                UnkeyedDecodingContainer.self,
                DecodingError.Context(
                    codingPath: codingPath + [IndexKey(intValue: currentIndex)],
                    debugDescription: "Unkeyed container is at end"
                )
            )
        }
        
        guard let nestedArray = array[currentIndex] as? [Any] else {
            throw DecodingError.typeMismatch(
                [Any].self,
                DecodingError.Context(
                    codingPath: codingPath + [IndexKey(intValue: currentIndex)],
                    debugDescription: "Expected array"
                )
            )
        }
        
        currentIndex += 1
        
        return _KuzuUnkeyedDecodingContainer(
            array: nestedArray,
            configuration: configuration,
            codingPath: codingPath + [IndexKey(intValue: currentIndex - 1)]
        )
    }
    
    mutating func superDecoder() throws -> Decoder {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(
                Decoder.self,
                DecodingError.Context(
                    codingPath: codingPath + [IndexKey(intValue: currentIndex)],
                    debugDescription: "Unkeyed container is at end"
                )
            )
        }
        
        guard let dict = array[currentIndex] as? [String: Any] else {
            throw DecodingError.typeMismatch(
                [String: Any].self,
                DecodingError.Context(
                    codingPath: codingPath + [IndexKey(intValue: currentIndex)],
                    debugDescription: "Expected dictionary"
                )
            )
        }
        
        currentIndex += 1
        
        let decoder = _KuzuDecoder(dictionary: dict, configuration: configuration)
        decoder.codingPath = codingPath + [IndexKey(intValue: currentIndex - 1)]
        return decoder
    }
}

// Helper struct for array indices
private struct IndexKey: CodingKey {
    let intValue: Int?
    let stringValue: String
    
    init(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "\(intValue)"
    }
    
    init?(stringValue: String) {
        return nil
    }
}

// MARK: - Array Decoder Implementation

/// Internal decoder specifically for arrays
private class _KuzuArrayDecoder: Decoder {
    let array: [Any]
    let configuration: KuzuDecoder.Configuration
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] { 
        // Convert Sendable values to Any for Decoder protocol compatibility
        configuration.userInfo.reduce(into: [:]) { result, pair in
            result[pair.key] = pair.value
        }
    }
    
    init(array: [Any], configuration: KuzuDecoder.Configuration) {
        self.array = array
        self.configuration = configuration
    }
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        throw DecodingError.typeMismatch(
            [String: Any].self,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected dictionary but found array"
            )
        )
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        return _KuzuUnkeyedDecodingContainer(
            array: array,
            configuration: configuration,
            codingPath: codingPath
        )
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        throw DecodingError.typeMismatch(
            Any.self,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Cannot decode array as single value"
            )
        )
    }
}