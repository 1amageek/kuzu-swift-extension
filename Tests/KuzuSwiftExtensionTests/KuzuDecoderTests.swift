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

    @Test("Decode optional types with values")
    func decodeOptionalsWithValues() throws {
        let decoder = KuzuDecoder()

        let dataWithValues: [String: Any?] = [
            "requiredString": "required",
            "optionalString": "optional",
            "optionalInt": 123,
            "optionalBool": false
        ]

        let model = try decoder.decode(OptionalTestModel.self, from: dataWithValues)
        #expect(model.requiredString == "required")
        #expect(model.optionalString == "optional")
        #expect(model.optionalInt == 123)
        #expect(model.optionalBool == false)
    }

    @Test("Decode optional types with nil values")
    func decodeOptionalsWithNilValues() throws {
        let decoder = KuzuDecoder()

        let dataWithNils: [String: Any?] = [
            "requiredString": "required",
            "optionalString": nil,
            "optionalInt": nil,
            "optionalBool": nil
        ]

        let model = try decoder.decode(OptionalTestModel.self, from: dataWithNils)
        #expect(model.requiredString == "required")
        #expect(model.optionalString == nil)
        #expect(model.optionalInt == nil)
        #expect(model.optionalBool == nil)
    }

    @Test("Decode all nil optionals with missing keys")
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

    @Test("Double to Float conversion with precision")
    func numericConversionsDoubleToFloat() throws {
        let decoder = KuzuDecoder()
        let data: [String: Any?] = ["value": 3.14]

        struct TestContainer: Codable {
            let value: Float
        }

        let result = try decoder.decode(TestContainer.self, from: data)
        #expect(abs(result.value - 3.14) < 0.001)
    }

    @Test("Large Int64 values")
    func largeInt64Values() throws {
        let decoder = KuzuDecoder()

        struct TestContainer: Codable {
            let largePositive: Int64
            let largeNegative: Int64
        }

        let data: [String: Any?] = [
            "largePositive": Int64.max - 1000,
            "largeNegative": Int64.min + 1000
        ]

        let result = try decoder.decode(TestContainer.self, from: data)
        #expect(result.largePositive == Int64.max - 1000)
        #expect(result.largeNegative == Int64.min + 1000)
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

    // MARK: - Date Decoding Tests (Strict Precision)

    @Test("Decode date with ISO8601 strategy - strict precision")
    func decodeDateISO8601Strategy() throws {
        let strategy = KuzuDecoder.DateDecodingStrategy.iso8601
        var decoder = KuzuDecoder()
        decoder.configuration.dateDecodingStrategy = strategy

        // Use a precise timestamp
        let testDate = Date(timeIntervalSince1970: 1234567890.123)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateValue = formatter.string(from: testDate)

        let data: [String: Any?] = [
            "id": "test",
            "createdAt": dateValue,
            "updatedAt": nil
        ]

        let model = try decoder.decode(DateTestModel.self, from: data)

        // Strict precision: allow only 1ms tolerance for ISO8601
        let timeDiff = abs(model.createdAt.timeIntervalSince1970 - testDate.timeIntervalSince1970)
        #expect(timeDiff < 0.001, "Date decoding precision error: \(timeDiff)s (expected <0.001s)")
        #expect(model.updatedAt == nil)
    }

    @Test("Decode date with seconds strategy - strict precision")
    func decodeDateSecondsStrategy() throws {
        let strategy = KuzuDecoder.DateDecodingStrategy.secondsSince1970
        var decoder = KuzuDecoder()
        decoder.configuration.dateDecodingStrategy = strategy

        let testDate = Date(timeIntervalSince1970: 1234567890.0)
        let dateValue = testDate.timeIntervalSince1970

        let data: [String: Any?] = [
            "id": "test",
            "createdAt": dateValue,
            "updatedAt": nil
        ]

        let model = try decoder.decode(DateTestModel.self, from: data)

        // Strict precision: seconds strategy should be exact
        let timeDiff = abs(model.createdAt.timeIntervalSince1970 - testDate.timeIntervalSince1970)
        #expect(timeDiff < 0.001, "Date decoding precision error: \(timeDiff)s (expected <0.001s)")
        #expect(model.updatedAt == nil)
    }

    @Test("Decode date with milliseconds strategy - strict precision")
    func decodeDateMillisecondsStrategy() throws {
        let strategy = KuzuDecoder.DateDecodingStrategy.millisecondsSince1970
        var decoder = KuzuDecoder()
        decoder.configuration.dateDecodingStrategy = strategy

        let testDate = Date(timeIntervalSince1970: 1234567890.123)
        let dateValue = testDate.timeIntervalSince1970 * 1000

        let data: [String: Any?] = [
            "id": "test",
            "createdAt": dateValue,
            "updatedAt": nil
        ]

        let model = try decoder.decode(DateTestModel.self, from: data)

        // Strict precision: milliseconds should be accurate to 0.001s
        let timeDiff = abs(model.createdAt.timeIntervalSince1970 - testDate.timeIntervalSince1970)
        #expect(timeDiff < 0.001, "Date decoding precision error: \(timeDiff)s (expected <0.001s)")
        #expect(model.updatedAt == nil)
    }

    @Test("Date strategy comparison - verify precision differences")
    func dateStrategyPrecisionComparison() throws {
        let testDate = Date(timeIntervalSince1970: 1234567890.123456)

        // ISO8601 strategy
        var decoder1 = KuzuDecoder()
        decoder1.configuration.dateDecodingStrategy = .iso8601

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso8601Value = formatter.string(from: testDate)

        let data1: [String: Any?] = [
            "id": "test",
            "createdAt": iso8601Value,
            "updatedAt": nil
        ]

        let model1 = try decoder1.decode(DateTestModel.self, from: data1)
        let diff1 = abs(model1.createdAt.timeIntervalSince1970 - testDate.timeIntervalSince1970)

        // Milliseconds strategy
        var decoder2 = KuzuDecoder()
        decoder2.configuration.dateDecodingStrategy = .millisecondsSince1970

        let msValue = testDate.timeIntervalSince1970 * 1000

        let data2: [String: Any?] = [
            "id": "test",
            "createdAt": msValue,
            "updatedAt": nil
        ]

        let model2 = try decoder2.decode(DateTestModel.self, from: data2)
        let diff2 = abs(model2.createdAt.timeIntervalSince1970 - testDate.timeIntervalSince1970)

        // Both should be within millisecond precision
        #expect(diff1 < 0.001, "ISO8601 precision: \(diff1)s")
        #expect(diff2 < 0.001, "Milliseconds precision: \(diff2)s")
    }

    @Test("Date round-trip precision")
    func dateRoundTripPrecision() throws {
        var decoder = KuzuDecoder()
        decoder.configuration.dateDecodingStrategy = .millisecondsSince1970

        // Test multiple timestamps to ensure consistency
        let timestamps: [TimeInterval] = [
            0.0,
            1234567890.123,
            1609459200.456, // 2021-01-01
            Date().timeIntervalSince1970
        ]

        for timestamp in timestamps {
            let msValue = timestamp * 1000

            let data: [String: Any?] = [
                "id": "test",
                "createdAt": msValue,
                "updatedAt": nil
            ]

            let model = try decoder.decode(DateTestModel.self, from: data)
            let diff = abs(model.createdAt.timeIntervalSince1970 - timestamp)

            #expect(diff < 0.001, "Timestamp \(timestamp) precision error: \(diff)s")
        }
    }

    // MARK: - Error Handling Tests

    @Test("Type mismatch error - string as integer")
    func decodeTypeMismatchStringAsInt() throws {
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

    @Test("Type mismatch error - integer as boolean")
    func decodeTypeMismatchIntAsBool() throws {
        let decoder = KuzuDecoder()
        let data: [String: Any?] = [
            "intValue": 42,
            "int64Value": Int64(123),
            "doubleValue": 1.0,
            "floatValue": Float(1.0),
            "boolValue": 1, // Integer instead of boolean
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

    @Test("Null value for required field")
    func decodeNullValueForRequiredField() throws {
        let decoder = KuzuDecoder()
        let data: [String: Any?] = [
            "requiredString": nil, // nil for required field
            "optionalString": "optional"
        ]

        #expect(throws: ResultMappingError.self) {
            try decoder.decode(OptionalTestModel.self, from: data)
        }
    }

    @Test("Invalid nested structure")
    func decodeInvalidNestedStructure() throws {
        let decoder = KuzuDecoder()
        let data: [String: Any?] = [
            "id": "test-id",
            "inner": "not a dictionary", // Should be dictionary
            "innerArray": []
        ]

        #expect(throws: ResultMappingError.self) {
            try decoder.decode(NestedTestModel.self, from: data)
        }
    }

    // MARK: - Edge Cases

    @Test("Empty string decoding")
    func decodeEmptyString() throws {
        let decoder = KuzuDecoder()

        struct TestContainer: Codable {
            let emptyValue: String
            let nonEmptyValue: String
        }

        let data: [String: Any?] = [
            "emptyValue": "",
            "nonEmptyValue": "content"
        ]

        let result = try decoder.decode(TestContainer.self, from: data)
        #expect(result.emptyValue == "")
        #expect(result.nonEmptyValue == "content")
    }

    @Test("Zero values decoding")
    func decodeZeroValues() throws {
        let decoder = KuzuDecoder()

        struct TestContainer: Codable {
            let zeroInt: Int
            let zeroDouble: Double
            let zeroBool: Bool
        }

        let data: [String: Any?] = [
            "zeroInt": 0,
            "zeroDouble": 0.0,
            "zeroBool": false
        ]

        let result = try decoder.decode(TestContainer.self, from: data)
        #expect(result.zeroInt == 0)
        #expect(result.zeroDouble == 0.0)
        #expect(result.zeroBool == false)
    }

    @Test("Empty collections decoding")
    func decodeEmptyCollections() throws {
        let decoder = KuzuDecoder()

        struct TestContainer: Codable {
            let emptyArray: [String]
            let emptyDict: [String: String]
        }

        let data: [String: Any?] = [
            "emptyArray": [],
            "emptyDict": [:]
        ]

        let result = try decoder.decode(TestContainer.self, from: data)
        #expect(result.emptyArray.isEmpty)
        #expect(result.emptyDict.isEmpty)
    }
}
