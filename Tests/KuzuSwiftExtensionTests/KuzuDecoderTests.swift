import Testing
import Foundation
@testable import KuzuSwiftExtension

@Suite("KuzuDecoder Tests")
struct KuzuDecoderTests {
    
    // MARK: - Test Models
    
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
    
    // MARK: - Basic Type Tests
    
    @Test("Decode basic types")
    func decodeBasicTypes() throws {
        let decoder = KuzuDecoder()
        let data: [String: Any?] = [
            "intValue": 42,
            "int64Value": Int64(9223372036854775807),
            "doubleValue": 3.14159,
            "floatValue": 2.718,
            "boolValue": true,
            "stringValue": "Hello, Swift Testing!"
        ]
        
        let model = try decoder.decode(BasicTestModel.self, from: data)
        
        #expect(model.intValue == 42)
        #expect(model.int64Value == 9223372036854775807)
        #expect(model.doubleValue == 3.14159)
        #expect(abs(model.floatValue - 2.718) < 0.001) // Float precision
        #expect(model.boolValue == true)
        #expect(model.stringValue == "Hello, Swift Testing!")
    }
    
    @Test("Decode optional types")
    func decodeOptionals() throws {
        let decoder = KuzuDecoder()
        
        // Test with all values present
        let dataWithValues: [String: Any?] = [
            "requiredString": "required",
            "optionalString": "optional",
            "optionalInt": 123,
            "optionalBool": false
        ]
        
        let modelWithValues = try decoder.decode(OptionalTestModel.self, from: dataWithValues)
        #expect(modelWithValues.requiredString == "required")
        #expect(modelWithValues.optionalString == "optional")
        #expect(modelWithValues.optionalInt == 123)
        #expect(modelWithValues.optionalBool == false)
        
        // Test with nil optionals
        let dataWithNils: [String: Any?] = [
            "requiredString": "required",
            "optionalString": nil,
            "optionalInt": nil,
            "optionalBool": nil
        ]
        
        let modelWithNils = try decoder.decode(OptionalTestModel.self, from: dataWithNils)
        #expect(modelWithNils.requiredString == "required")
        #expect(modelWithNils.optionalString == nil)
        #expect(modelWithNils.optionalInt == nil)
        #expect(modelWithNils.optionalBool == nil)
    }
    
    @Test("Decode all nil optionals")
    func decodeAllNilOptionals() throws {
        let decoder = KuzuDecoder()
        let data: [String: Any?] = [
            "requiredString": "test"
            // All optional fields omitted
        ]
        
        let model = try decoder.decode(OptionalTestModel.self, from: data)
        #expect(model.requiredString == "test")
        #expect(model.optionalString == nil)
        #expect(model.optionalInt == nil)
        #expect(model.optionalBool == nil)
    }
    
    // MARK: - Numeric Conversion Tests
    
    @Test("Int64 to Int conversion")
    func numericConversionsInt64ToInt() throws {
        let decoder = KuzuDecoder()
        let data: [String: Any?] = ["value": Int64(42)]
        
        struct TestContainer: Codable {
            let value: Int
        }
        
        let result = try decoder.decode(TestContainer.self, from: data)
        #expect(result.value == 42)
    }
    
    @Test("Int to Int64 conversion")
    func numericConversionsIntToInt64() throws {
        let decoder = KuzuDecoder()
        let data: [String: Any?] = ["value": 42]
        
        struct TestContainer: Codable {
            let value: Int64
        }
        
        let result = try decoder.decode(TestContainer.self, from: data)
        #expect(result.value == Int64(42))
    }
    
    @Test("Double to Float conversion")
    func numericConversionsDoubleToFloat() throws {
        let decoder = KuzuDecoder()
        let data: [String: Any?] = ["value": 3.14]
        
        struct TestContainer: Codable {
            let value: Float
        }
        
        let result = try decoder.decode(TestContainer.self, from: data)
        #expect(abs(result.value - 3.14) < 0.001)
    }
    
    // MARK: - Nested Object Tests
    
    @Test("Decode nested objects")
    func decodeNestedObjects() throws {
        let decoder = KuzuDecoder()
        let data: [String: Any?] = [
            "id": "test-id",
            "inner": [
                "name": "inner-name",
                "value": 100
            ],
            "innerArray": [
                ["name": "first", "value": 1],
                ["name": "second", "value": 2]
            ]
        ]
        
        let model = try decoder.decode(NestedTestModel.self, from: data)
        
        #expect(model.id == "test-id")
        #expect(model.inner.name == "inner-name")
        #expect(model.inner.value == 100)
        #expect(model.innerArray.count == 2)
        #expect(model.innerArray[0].name == "first")
        #expect(model.innerArray[0].value == 1)
        #expect(model.innerArray[1].name == "second")
        #expect(model.innerArray[1].value == 2)
    }
    
    // MARK: - Date Decoding Tests
    
    @Test("Decode date ISO8601 strategy")
    func decodeDateISO8601Strategy() throws {
        let strategy = KuzuDecoder.DateDecodingStrategy.iso8601
        var decoder = KuzuDecoder()
        decoder.configuration.dateDecodingStrategy = strategy
        
        let testDate = Date(timeIntervalSince1970: 1234567890)
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateValue = formatter.string(from: testDate)
        
        let data: [String: Any?] = [
            "id": "test",
            "createdAt": dateValue,
            "updatedAt": nil
        ]
        
        let model = try decoder.decode(DateTestModel.self, from: data)
        
        // Allow some tolerance for date comparison
        let timeDiff = abs(model.createdAt.timeIntervalSince1970 - testDate.timeIntervalSince1970)
        #expect(timeDiff < 1.0, "Date decoding failed for strategy: \(strategy)")
        #expect(model.updatedAt == nil)
    }
    
    @Test("Decode date seconds since 1970 strategy")
    func decodeDateSecondsStrategy() throws {
        let strategy = KuzuDecoder.DateDecodingStrategy.secondsSince1970
        var decoder = KuzuDecoder()
        decoder.configuration.dateDecodingStrategy = strategy
        
        let testDate = Date(timeIntervalSince1970: 1234567890)
        let dateValue = testDate.timeIntervalSince1970
        
        let data: [String: Any?] = [
            "id": "test",
            "createdAt": dateValue,
            "updatedAt": nil
        ]
        
        let model = try decoder.decode(DateTestModel.self, from: data)
        
        // Allow some tolerance for date comparison
        let timeDiff = abs(model.createdAt.timeIntervalSince1970 - testDate.timeIntervalSince1970)
        #expect(timeDiff < 1.0, "Date decoding failed for strategy: \(strategy)")
        #expect(model.updatedAt == nil)
    }
    
    @Test("Decode date milliseconds since 1970 strategy")
    func decodeDateMillisecondsStrategy() throws {
        let strategy = KuzuDecoder.DateDecodingStrategy.millisecondsSince1970
        var decoder = KuzuDecoder()
        decoder.configuration.dateDecodingStrategy = strategy
        
        let testDate = Date(timeIntervalSince1970: 1234567890)
        let dateValue = testDate.timeIntervalSince1970 * 1000
        
        let data: [String: Any?] = [
            "id": "test",
            "createdAt": dateValue,
            "updatedAt": nil
        ]
        
        let model = try decoder.decode(DateTestModel.self, from: data)
        
        // Allow some tolerance for date comparison
        let timeDiff = abs(model.createdAt.timeIntervalSince1970 - testDate.timeIntervalSince1970)
        #expect(timeDiff < 1.0, "Date decoding failed for strategy: \(strategy)")
        #expect(model.updatedAt == nil)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Type mismatch error")
    func decodeTypeMismatch() throws {
        let decoder = KuzuDecoder()
        let data: [String: Any?] = [
            "intValue": "not an integer", // Wrong type
            "int64Value": Int64(123),
            "doubleValue": 1.0,
            "floatValue": Float(1.0),
            "boolValue": true,
            "stringValue": "test"
        ]
        
        #expect(throws: ResultMappingError.self) {
            try decoder.decode(BasicTestModel.self, from: data)
        }
    }
    
    @Test("Missing required field error")
    func decodeMissingRequiredField() throws {
        let decoder = KuzuDecoder()
        let data: [String: Any?] = [
            // Missing requiredString
            "optionalString": "optional"
        ]
        
        #expect(throws: ResultMappingError.self) {
            try decoder.decode(OptionalTestModel.self, from: data)
        }
    }
}