import Foundation
import Kuzu

/// A decoder that converts Kuzu query results into Swift Codable types
public class KuzuDecoder {
    /// Configuration options for decoding
    public struct Configuration {
        public var dateDecodingStrategy: DateDecodingStrategy = .iso8601
        public var dataDecodingStrategy: DataDecodingStrategy = .base64
        public var keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys
        public var userInfo: [CodingUserInfoKey: Any] = [:]
        
        public init() {}
    }
    
    /// Strategy for decoding dates
    public enum DateDecodingStrategy {
        case iso8601
        case secondsSince1970
        case millisecondsSince1970
        case custom((Any?) throws -> Date)
    }
    
    /// Strategy for decoding data
    public enum DataDecodingStrategy {
        case base64
        case custom((Any?) throws -> Data)
    }
    
    /// Strategy for decoding keys
    public enum KeyDecodingStrategy {
        case useDefaultKeys
        case convertFromSnakeCase
        case custom(([CodingKey]) -> CodingKey)
    }
    
    public var configuration = Configuration()
    
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
            let decoded = try decode(type, from: dictionary)
            results.append(decoded)
        }
        
        return results
    }
    
    /// Decodes a value from a dictionary
    public func decode<T: Decodable>(_ type: T.Type, from dictionary: [String: Any?]) throws -> T {
        // Convert the dictionary to a format suitable for JSONSerialization
        let cleanedDict = cleanDictionary(dictionary)
        
        // Convert to Data for JSONDecoder
        let data = try JSONSerialization.data(withJSONObject: cleanedDict, options: [])
        
        // Create and configure JSONDecoder
        let jsonDecoder = JSONDecoder()
        
        // Apply date decoding strategy
        switch configuration.dateDecodingStrategy {
        case .iso8601:
            jsonDecoder.dateDecodingStrategy = .iso8601
        case .secondsSince1970:
            jsonDecoder.dateDecodingStrategy = .secondsSince1970
        case .millisecondsSince1970:
            jsonDecoder.dateDecodingStrategy = .millisecondsSince1970
        case .custom(let converter):
            jsonDecoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let value = try container.decode(String.self)
                return try converter(value)
            }
        }
        
        // Apply data decoding strategy
        switch configuration.dataDecodingStrategy {
        case .base64:
            jsonDecoder.dataDecodingStrategy = .base64
        case .custom(let converter):
            jsonDecoder.dataDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let value = try container.decode(String.self)
                return try converter(value)
            }
        }
        
        // Apply key decoding strategy
        switch configuration.keyDecodingStrategy {
        case .useDefaultKeys:
            break
        case .convertFromSnakeCase:
            jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        case .custom(let converter):
            jsonDecoder.keyDecodingStrategy = .custom(converter)
        }
        
        // Apply user info
        jsonDecoder.userInfo = configuration.userInfo
        
        // Decode the data
        do {
            return try jsonDecoder.decode(type, from: data)
        } catch {
            throw ResultMappingError.decodingFailed(
                field: String(describing: type),
                underlyingError: error
            )
        }
    }
    
    /// Cleans a dictionary for JSON serialization
    private func cleanDictionary(_ dictionary: [String: Any?]) -> [String: Any] {
        var cleaned: [String: Any] = [:]
        
        for (key, value) in dictionary {
            if let value = value {
                // Handle special Kuzu types
                if let array = value as? [Any?] {
                    cleaned[key] = array.compactMap { cleanValue($0) }
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
        // Convert Kuzu-specific types to JSON-compatible types
        switch value {
        case let int64 as Int64:
            return Int(int64)
        case let int32 as Int32:
            return Int(int32)
        case let float as Float:
            return Double(float)
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
        case let uuid as UUID:
            return uuid.uuidString
        case let array as [Any]:
            return array.map { cleanValue($0) }
        case let dict as [String: Any]:
            return cleanDictionary(dict as [String: Any?])
        default:
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