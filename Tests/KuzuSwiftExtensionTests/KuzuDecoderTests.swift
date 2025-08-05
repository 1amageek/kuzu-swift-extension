import XCTest
import Kuzu
@testable import KuzuSwiftExtension

// Test models
struct BasicTestModel: Codable, Equatable {
    let intValue: Int
    let int64Value: Int64
    let doubleValue: Double
    let floatValue: Float
    let boolValue: Bool
    let stringValue: String
}

struct OptionalTestModel: Codable, Equatable {
    let requiredString: String
    let optionalString: String?
    let optionalInt: Int?
    let optionalBool: Bool?
}

struct NestedTestModel: Codable, Equatable {
    struct Inner: Codable, Equatable {
        let name: String
        let value: Int
    }
    
    let id: String
    let inner: Inner
    let innerArray: [Inner]
}

struct DateTestModel: Codable, Equatable {
    let id: String
    let createdAt: Date
    let updatedAt: Date?
}

struct DataTestModel: Codable, Equatable {
    let id: String
    let binaryData: Data
}

final class KuzuDecoderTests: XCTestCase {
    var decoder: KuzuDecoder!
    
    override func setUp() {
        super.setUp()
        decoder = KuzuDecoder()
    }
    
    // MARK: - Basic Type Tests
    
    func testDecodeBasicTypes() throws {
        let dictionary: [String: Any?] = [
            "intValue": 42,
            "int64Value": Int64(9223372036854775807),
            "doubleValue": 3.14159,
            "floatValue": Float(2.718),
            "boolValue": true,
            "stringValue": "Hello, Kuzu!"
        ]
        
        let result = try decoder.decode(BasicTestModel.self, from: dictionary)
        
        XCTAssertEqual(result.intValue, 42)
        XCTAssertEqual(result.int64Value, 9223372036854775807)
        XCTAssertEqual(result.doubleValue, 3.14159, accuracy: 0.00001)
        XCTAssertEqual(result.floatValue, 2.718, accuracy: 0.001)
        XCTAssertEqual(result.boolValue, true)
        XCTAssertEqual(result.stringValue, "Hello, Kuzu!")
    }
    
    // MARK: - Optional Tests
    
    func testDecodeOptionals() throws {
        let dictionary: [String: Any?] = [
            "requiredString": "Required",
            "optionalString": "Optional",
            "optionalInt": 123,
            "optionalBool": nil
        ]
        
        let result = try decoder.decode(OptionalTestModel.self, from: dictionary)
        
        XCTAssertEqual(result.requiredString, "Required")
        XCTAssertEqual(result.optionalString, "Optional")
        XCTAssertEqual(result.optionalInt, 123)
        XCTAssertNil(result.optionalBool)
    }
    
    func testDecodeAllNilOptionals() throws {
        let dictionary: [String: Any?] = [
            "requiredString": "Required",
            "optionalString": nil,
            "optionalInt": nil,
            "optionalBool": nil
        ]
        
        let result = try decoder.decode(OptionalTestModel.self, from: dictionary)
        
        XCTAssertEqual(result.requiredString, "Required")
        XCTAssertNil(result.optionalString)
        XCTAssertNil(result.optionalInt)
        XCTAssertNil(result.optionalBool)
    }
    
    // MARK: - Nested Object Tests
    
    func testDecodeNestedObjects() throws {
        let dictionary: [String: Any?] = [
            "id": "test-123",
            "inner": [
                "name": "Inner Object",
                "value": 999
            ],
            "innerArray": [
                ["name": "First", "value": 1],
                ["name": "Second", "value": 2],
                ["name": "Third", "value": 3]
            ]
        ]
        
        let result = try decoder.decode(NestedTestModel.self, from: dictionary)
        
        XCTAssertEqual(result.id, "test-123")
        XCTAssertEqual(result.inner.name, "Inner Object")
        XCTAssertEqual(result.inner.value, 999)
        XCTAssertEqual(result.innerArray.count, 3)
        XCTAssertEqual(result.innerArray[0].name, "First")
        XCTAssertEqual(result.innerArray[1].value, 2)
    }
    
    // MARK: - Date Decoding Tests
    
    func testDecodeDateISO8601() throws {
        let dateString = "2024-01-15T10:30:00.123Z"
        let dictionary: [String: Any?] = [
            "id": "date-test",
            "createdAt": dateString,
            "updatedAt": nil
        ]
        
        decoder.configuration.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(DateTestModel.self, from: dictionary)
        
        XCTAssertEqual(result.id, "date-test")
        XCTAssertNotNil(result.createdAt)
        XCTAssertNil(result.updatedAt)
        
        // Verify the date was parsed correctly
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expectedDate = formatter.date(from: dateString)!
        XCTAssertEqual(result.createdAt.timeIntervalSince1970, expectedDate.timeIntervalSince1970, accuracy: 0.001)
    }
    
    func testDecodeDateSecondsSince1970() throws {
        let timestamp: Double = 1705315800 // 2024-01-15 10:30:00 UTC
        let dictionary: [String: Any?] = [
            "id": "timestamp-test",
            "createdAt": timestamp,
            "updatedAt": nil
        ]
        
        decoder.configuration.dateDecodingStrategy = .secondsSince1970
        let result = try decoder.decode(DateTestModel.self, from: dictionary)
        
        XCTAssertEqual(result.createdAt.timeIntervalSince1970, timestamp, accuracy: 0.001)
    }
    
    func testDecodeDateMillisecondsSince1970() throws {
        let timestampMillis: Double = 1705315800000 // 2024-01-15 10:30:00 UTC in milliseconds
        let dictionary: [String: Any?] = [
            "id": "millis-test",
            "createdAt": timestampMillis,
            "updatedAt": nil
        ]
        
        decoder.configuration.dateDecodingStrategy = .millisecondsSince1970
        let result = try decoder.decode(DateTestModel.self, from: dictionary)
        
        XCTAssertEqual(result.createdAt.timeIntervalSince1970, timestampMillis / 1000, accuracy: 0.001)
    }
    
    func testDecodeDateCustomStrategy() throws {
        let customDateString = "2024-01-15"
        let dictionary: [String: Any?] = [
            "id": "custom-date",
            "createdAt": customDateString,
            "updatedAt": nil
        ]
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        decoder.configuration.dateDecodingStrategy = .custom { value in
            guard let string = value as? String else {
                throw DecodingError.typeMismatch(
                    Date.self,
                    DecodingError.Context(codingPath: [], debugDescription: "Expected string for date")
                )
            }
            guard let date = dateFormatter.date(from: string) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: [], debugDescription: "Invalid date format")
                )
            }
            return date
        }
        
        let result = try decoder.decode(DateTestModel.self, from: dictionary)
        
        let expectedDate = dateFormatter.date(from: customDateString)!
        XCTAssertEqual(result.createdAt, expectedDate)
    }
    
    // MARK: - Data Decoding Tests
    
    func testDecodeDataBase64() throws {
        let testString = "Hello, Kuzu!"
        let base64String = testString.data(using: .utf8)!.base64EncodedString()
        
        let dictionary: [String: Any?] = [
            "id": "data-test",
            "binaryData": base64String
        ]
        
        decoder.configuration.dataDecodingStrategy = .base64
        let result = try decoder.decode(DataTestModel.self, from: dictionary)
        
        XCTAssertEqual(result.id, "data-test")
        XCTAssertEqual(String(data: result.binaryData, encoding: .utf8), testString)
    }
    
    func testDecodeDataCustomStrategy() throws {
        let hexString = "48656c6c6f2c204b757a7521" // "Hello, Kuzu!" in hex
        
        let dictionary: [String: Any?] = [
            "id": "hex-data",
            "binaryData": hexString
        ]
        
        decoder.configuration.dataDecodingStrategy = .custom { value in
            guard let hex = value as? String else {
                throw DecodingError.typeMismatch(
                    Data.self,
                    DecodingError.Context(codingPath: [], debugDescription: "Expected hex string")
                )
            }
            
            var data = Data()
            var index = hex.startIndex
            while index < hex.endIndex {
                let nextIndex = hex.index(index, offsetBy: 2)
                let bytes = hex[index..<nextIndex]
                if let byte = UInt8(bytes, radix: 16) {
                    data.append(byte)
                }
                index = nextIndex
            }
            return data
        }
        
        let result = try decoder.decode(DataTestModel.self, from: dictionary)
        
        XCTAssertEqual(String(data: result.binaryData, encoding: .utf8), "Hello, Kuzu!")
    }
    
    // MARK: - Error Tests
    
    func testDecodeMissingRequiredField() throws {
        let dictionary: [String: Any?] = [
            "intValue": 42
            // Missing other required fields
        ]
        
        XCTAssertThrowsError(try decoder.decode(BasicTestModel.self, from: dictionary)) { error in
            guard case ResultMappingError.decodingFailed = error else {
                XCTFail("Expected ResultMappingError.decodingFailed")
                return
            }
        }
    }
    
    func testDecodeTypeMismatch() throws {
        let dictionary: [String: Any?] = [
            "intValue": "not an int", // Type mismatch
            "int64Value": Int64(123),
            "doubleValue": 3.14,
            "floatValue": Float(2.718),
            "boolValue": true,
            "stringValue": "Test"
        ]
        
        XCTAssertThrowsError(try decoder.decode(BasicTestModel.self, from: dictionary)) { error in
            guard case ResultMappingError.decodingFailed = error else {
                XCTFail("Expected ResultMappingError.decodingFailed")
                return
            }
        }
    }
    
    // MARK: - Numeric Conversion Tests
    
    func testNumericConversions() throws {
        // Test various numeric type conversions
        let dictionary: [String: Any?] = [
            "intValue": Int64(42),      // Int64 -> Int
            "int64Value": 123,           // Int -> Int64
            "doubleValue": Float(3.14),  // Float -> Double
            "floatValue": 2.718,         // Double -> Float
            "boolValue": true,
            "stringValue": "Test"
        ]
        
        let result = try decoder.decode(BasicTestModel.self, from: dictionary)
        
        XCTAssertEqual(result.intValue, 42)
        XCTAssertEqual(result.int64Value, 123)
        XCTAssertEqual(result.doubleValue, 3.14, accuracy: 0.01)
        XCTAssertEqual(result.floatValue, 2.718, accuracy: 0.001)
    }
}