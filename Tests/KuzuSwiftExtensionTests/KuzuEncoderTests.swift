import XCTest
import Foundation
@testable import KuzuSwiftExtension

final class KuzuEncoderTests: XCTestCase {
    
    var encoder = KuzuEncoder()
    
    // MARK: - Basic Type Conversion Tests
    
    func testDateConversion() throws {
        let date = Date(timeIntervalSince1970: 1234567890)
        let encoded = try encoder.encode(TestModel(date: date))
        // KuzuEncoder converts Date to ISO-8601 string for Kuzu TIMESTAMP
        let dateString = encoded["date"] as? String
        XCTAssertNotNil(dateString)
        XCTAssertTrue(dateString!.contains("2009-02-13"))
        XCTAssertTrue(dateString!.contains("23:31:30"))
    }
    
    func testUUIDConversion() throws {
        let uuid = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!
        let encoded = try encoder.encode(TestModel(uuid: uuid))
        XCTAssertEqual(encoded["uuid"] as? String, uuid.uuidString)
    }
    
    func testOptionalHandling() throws {
        let model1 = TestModel(optionalString: "test")
        let encoded1 = try encoder.encode(model1)
        XCTAssertEqual(encoded1["optionalString"] as? String, "test")
        
        let model2 = TestModel(optionalString: nil)
        let encoded2 = try encoder.encode(model2)
        XCTAssertTrue(encoded2["optionalString"] is NSNull)
    }
    
    // MARK: - Collection Tests
    
    func testArrayEncoding() throws {
        let model = TestModel(array: ["a", "b", "c"])
        let encoded = try encoder.encode(model)
        let array = encoded["array"] as? [any Sendable]
        let stringArray = array?.compactMap { $0 as? String }
        XCTAssertEqual(stringArray, ["a", "b", "c"])
    }
    
    func testDictionaryEncoding() throws {
        let model = TestModel(dictionary: ["key1": "value1", "key2": "value2"])
        let encoded = try encoder.encode(model)
        let dict = encoded["dictionary"] as? [String: any Sendable]
        let stringDict = dict?.compactMapValues { $0 as? String }
        XCTAssertEqual(stringDict?["key1"], "value1")
        XCTAssertEqual(stringDict?["key2"], "value2")
    }
    
    // MARK: - Nested Model Tests
    
    func testNestedModelEncoding() throws {
        let nested = NestedModel(id: 123, name: "nested")
        let model = TestModel(nested: nested)
        let encoded = try encoder.encode(model)
        let nestedDict = encoded["nested"] as? [String: any Sendable]
        XCTAssertEqual(nestedDict?["id"] as? Int, 123)
        XCTAssertEqual(nestedDict?["name"] as? String, "nested")
    }
    
    // MARK: - Encoding Strategy Tests
    
    func testDateEncodingStrategies() throws {
        let date = Date(timeIntervalSince1970: 1234567890)
        
        // ISO8601 (default)
        encoder.configuration.dateEncodingStrategy = .iso8601
        let iso8601Encoded = try encoder.encode(TestModel(date: date))
        let iso8601String = iso8601Encoded["date"] as? String
        XCTAssertTrue(iso8601String!.contains("2009-02-13"))
        
        // Seconds since 1970
        encoder.configuration.dateEncodingStrategy = .secondsSince1970
        let secondsEncoded = try encoder.encode(TestModel(date: date))
        XCTAssertEqual(secondsEncoded["date"] as? Double, 1234567890.0)
        
        // Milliseconds since 1970
        encoder.configuration.dateEncodingStrategy = .millisecondsSince1970
        let millisecondsEncoded = try encoder.encode(TestModel(date: date))
        XCTAssertEqual(millisecondsEncoded["date"] as? Double, 1234567890000.0)
    }
    
    func testDataEncodingStrategy() throws {
        let data = "Hello, World!".data(using: .utf8)!
        
        // Base64 (default)
        encoder.configuration.dataEncodingStrategy = .base64
        let base64Encoded = try encoder.encode(TestModel(data: data))
        XCTAssertEqual(base64Encoded["data"] as? String, data.base64EncodedString())
    }
    
    func testKeyEncodingStrategy() throws {
        let model = TestModel(camelCaseKey: "value")
        
        // Default keys
        encoder.configuration.keyEncodingStrategy = .useDefaultKeys
        let defaultEncoded = try encoder.encode(model)
        XCTAssertNotNil(defaultEncoded["camelCaseKey"])
        
        // Snake case
        encoder.configuration.keyEncodingStrategy = .convertToSnakeCase
        let snakeCaseEncoded = try encoder.encode(model)
        XCTAssertNotNil(snakeCaseEncoded["camel_case_key"])
    }
    
    // MARK: - Parameter Encoding Tests
    
    func testEncodeParameters() throws {
        let params: [String: any Sendable] = [
            "string": "test",
            "number": 42,
            "bool": true,
            "null": NSNull(),
            "array": [1, 2, 3],
            "dict": ["key": "value"]
        ]
        
        let encoded = try encoder.encodeParameters(params)
        XCTAssertEqual(encoded["string"] as? String, "test")
        XCTAssertEqual(encoded["number"] as? Int, 42)
        XCTAssertEqual(encoded["bool"] as? Bool, true)
        XCTAssertNil(encoded["null"]!)
        let intArray = encoded["array"] as? [any Sendable]
        XCTAssertEqual(intArray?.compactMap { $0 as? Int }, [1, 2, 3])
        let dict = encoded["dict"] as? [String: any Sendable]
        let stringValue = dict?["key"] as? String
        XCTAssertEqual(stringValue, "value")
    }
    
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
}
