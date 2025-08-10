import Testing
import Foundation
@testable import KuzuSwiftExtension

@Suite("KuzuEncoder Tests")
struct KuzuEncoderTests {
    
    // MARK: - Test Models
    
    struct TestModel: Codable {
        var date: Date?
        var uuid: UUID?
        var optionalString: String?
        var array: [String]?
        var dictionary: [String: String]?
        var nested: NestedModel?
        var data: Data?
        var camelCaseKey: String?
        
        init(date: Date? = nil, uuid: UUID? = nil, optionalString: String? = nil,
             array: [String]? = nil, dictionary: [String: String]? = nil,
             nested: NestedModel? = nil, data: Data? = nil, camelCaseKey: String? = nil) {
            self.date = date
            self.uuid = uuid
            self.optionalString = optionalString
            self.array = array
            self.dictionary = dictionary
            self.nested = nested
            self.data = data
            self.camelCaseKey = camelCaseKey
        }
    }
    
    struct NestedModel: Codable {
        let id: Int
        let name: String
    }
    
    // MARK: - Basic Type Conversion Tests
    
    @Test("Date conversion to ISO-8601 (default)")
    func dateConversion() throws {
        let encoder = KuzuEncoder()
        let date = Date(timeIntervalSince1970: 1234567890)
        let encoded = try encoder.encode(TestModel(date: date))
        
        // Default strategy is ISO-8601 for Kuzu TIMESTAMP
        let dateString = encoded["date"] as? String
        #expect(dateString != nil)
        #expect(dateString?.contains("2009-02-13") == true)
    }
    
    @Test("UUID conversion to string")
    func uuidConversion() throws {
        let encoder = KuzuEncoder()
        let uuid = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!
        let encoded = try encoder.encode(TestModel(uuid: uuid))
        
        #expect(encoded["uuid"] as? String == uuid.uuidString)
    }
    
    @Test("Optional string handling")
    func optionalHandling() throws {
        let encoder = KuzuEncoder()
        
        // Test with value
        let model1 = TestModel(optionalString: "test")
        let encoded1 = try encoder.encode(model1)
        #expect(encoded1["optionalString"] as? String == "test")
        
        // Test with nil (should be omitted by default Codable behavior)
        let model2 = TestModel(optionalString: nil)
        let encoded2 = try encoder.encode(model2)
        #expect(encoded2["optionalString"] == nil)
    }
    
    // MARK: - Collection Tests
    
    @Test("Array encoding")
    func arrayEncoding() throws {
        let encoder = KuzuEncoder()
        let model = TestModel(array: ["a", "b", "c"])
        let encoded = try encoder.encode(model)
        
        let array = encoded["array"] as? [any Sendable]
        let stringArray = array?.compactMap { $0 as? String }
        #expect(stringArray == ["a", "b", "c"])
    }
    
    @Test("Dictionary encoding")
    func dictionaryEncoding() throws {
        let encoder = KuzuEncoder()
        let model = TestModel(dictionary: ["key1": "value1", "key2": "value2"])
        let encoded = try encoder.encode(model)
        
        let dict = encoded["dictionary"] as? [String: any Sendable]
        let stringDict = dict?.compactMapValues { $0 as? String }
        #expect(stringDict?["key1"] == "value1")
        #expect(stringDict?["key2"] == "value2")
    }
    
    // MARK: - Nested Model Tests
    
    @Test("Nested model encoding")
    func nestedModelEncoding() throws {
        let encoder = KuzuEncoder()
        let nested = NestedModel(id: 123, name: "nested")
        let model = TestModel(nested: nested)
        let encoded = try encoder.encode(model)
        
        let nestedDict = encoded["nested"] as? [String: any Sendable]
        #expect(nestedDict?["id"] as? Int == 123)
        #expect(nestedDict?["name"] as? String == "nested")
    }
    
    // MARK: - Encoding Strategy Tests
    
    @Test("Date encoding strategies", arguments: [
        (KuzuEncoder.DateEncodingStrategy.microsecondsSince1970, "microseconds"),
        (KuzuEncoder.DateEncodingStrategy.iso8601, "iso8601"),
        (KuzuEncoder.DateEncodingStrategy.secondsSince1970, "seconds"),
        (KuzuEncoder.DateEncodingStrategy.millisecondsSince1970, "milliseconds")
    ])
    func dateEncodingStrategies(strategy: KuzuEncoder.DateEncodingStrategy, name: String) throws {
        var encoder = KuzuEncoder()
        let date = Date(timeIntervalSince1970: 1234567890)
        encoder.configuration.dateEncodingStrategy = strategy
        
        let encoded = try encoder.encode(TestModel(date: date))
        
        switch strategy {
        case .microsecondsSince1970:
            #expect(encoded["date"] as? Int64 == 1234567890000000)
        case .iso8601:
            let dateString = encoded["date"] as? String
            #expect(dateString?.contains("2009-02-13") == true)
        case .secondsSince1970:
            #expect(encoded["date"] as? Double == 1234567890.0)
        case .millisecondsSince1970:
            #expect(encoded["date"] as? Double == 1234567890000.0)
        case .custom:
            // Skip custom strategy test
            break
        }
    }
    
    @Test("Data encoding strategy - Base64")
    func dataEncodingStrategy() throws {
        var encoder = KuzuEncoder()
        let data = "Hello, World!".data(using: .utf8)!
        encoder.configuration.dataEncodingStrategy = .base64
        
        let encoded = try encoder.encode(TestModel(data: data))
        #expect(encoded["data"] as? String == data.base64EncodedString())
    }
    
    @Test("Key encoding strategies", arguments: [
        (KuzuEncoder.KeyEncodingStrategy.useDefaultKeys, "camelCaseKey"),
        (KuzuEncoder.KeyEncodingStrategy.convertToSnakeCase, "camel_case_key")
    ])
    func keyEncodingStrategy(strategy: KuzuEncoder.KeyEncodingStrategy, expectedKey: String) throws {
        var encoder = KuzuEncoder()
        let model = TestModel(camelCaseKey: "value")
        encoder.configuration.keyEncodingStrategy = strategy
        
        let encoded = try encoder.encode(model)
        #expect(encoded[expectedKey] != nil)
    }
    
    // MARK: - Parameter Encoding Tests
    
    @Test("Parameter encoding")
    func encodeParameters() throws {
        let encoder = KuzuEncoder()
        let params: [String: any Sendable] = [
            "string": "test",
            "number": 42,
            "bool": true,
            "array": [1, 2, 3],
            "dict": ["key": "value"]
        ]
        
        let encoded = try encoder.encodeParameters(params)
        
        #expect(encoded["string"] as? String == "test")
        #expect(encoded["number"] as? Int == 42)
        #expect(encoded["bool"] as? Bool == true)
        
        let intArray = encoded["array"] as? [any Sendable]
        #expect(intArray?.compactMap { $0 as? Int } == [1, 2, 3])
        
        let dict = encoded["dict"] as? [String: any Sendable]
        let stringValue = dict?["key"] as? String
        #expect(stringValue == "value")
    }
}