import XCTest
import Foundation
@testable import KuzuSwiftExtension

final class ValueConverterTests: XCTestCase {
    
    // MARK: - Basic Type Conversion Tests
    
    func testDateConversion() {
        let date = Date(timeIntervalSince1970: 1234567890)
        let converted = ValueConverter.toKuzuValue(date)
        XCTAssertEqual(converted as? Double, 1234567890.0)
    }
    
    func testUUIDConversion() {
        let uuid = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!
        let converted = ValueConverter.toKuzuValue(uuid)
        XCTAssertEqual(converted as? String, uuid.uuidString)
    }
    
    func testNSNullConversion() {
        let null = NSNull()
        let converted = ValueConverter.toKuzuValue(null)
        XCTAssertNil(converted)
    }
    
    // MARK: - Optional Handling Tests
    
    func testSimpleOptional() {
        let optional: Any = Optional<String>.some("test")
        let converted = ValueConverter.toKuzuValue(optional)
        XCTAssertEqual(converted as? String, "test")
    }
    
    func testNilOptional() {
        let optional: Any = Optional<String>.none as Any
        let converted = ValueConverter.toKuzuValue(optional)
        XCTAssertNil(converted)
    }
    
    func testNestedOptional() {
        // This was causing infinite recursion
        let nested: Any = Optional<Optional<String>>.some(.some("test")) as Any
        let converted = ValueConverter.toKuzuValue(nested)
        XCTAssertEqual(converted as? String, "test")
    }
    
    func testDeeplyNestedOptional() {
        // Triple nested optional
        let tripleNested: Any = Optional<Optional<Optional<String>>>.some(.some(.some("test"))) as Any
        let converted = ValueConverter.toKuzuValue(tripleNested)
        XCTAssertEqual(converted as? String, "test")
    }
    
    func testOptionalWithNSNull() {
        // NSNull wrapped in optional
        let optionalNull: Any = Optional<NSNull>.some(NSNull()) as Any
        let converted = ValueConverter.toKuzuValue(optionalNull)
        XCTAssertNil(converted)
    }
    
    func testOptionalDate() {
        let date = Date(timeIntervalSince1970: 1234567890)
        let optional: Any = Optional<Date>.some(date) as Any
        let converted = ValueConverter.toKuzuValue(optional)
        XCTAssertEqual(converted as? Double, 1234567890.0)
    }
    
    func testOptionalUUID() {
        let uuid = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!
        let optional: Any = Optional<UUID>.some(uuid) as Any
        let converted = ValueConverter.toKuzuValue(optional)
        XCTAssertEqual(converted as? String, uuid.uuidString)
    }
    
    // MARK: - Collection Tests
    
    func testArrayConversion() {
        let array: [Any] = ["test", 123, true]
        let converted = ValueConverter.toKuzuValue(array) as? [Any?]
        XCTAssertNotNil(converted)
        XCTAssertEqual(converted?.count, 3)
        XCTAssertEqual(converted?[0] as? String, "test")
        XCTAssertEqual(converted?[1] as? Int, 123)
        XCTAssertEqual(converted?[2] as? Bool, true)
    }
    
    func testArrayWithOptionals() {
        let array: [Any] = [
            Optional<String>.some("test") as Any,
            Optional<Int>.none as Any,
            Optional<Bool>.some(true) as Any
        ]
        let converted = ValueConverter.toKuzuValue(array) as? [Any?]
        XCTAssertNotNil(converted)
        XCTAssertEqual(converted?.count, 3)
        XCTAssertEqual(converted?[0] as? String, "test")
        XCTAssertNil(converted?[1])
        XCTAssertEqual(converted?[2] as? Bool, true)
    }
    
    func testDictionaryConversion() {
        let dict: [String: Any] = [
            "string": "test",
            "number": 123,
            "bool": true
        ]
        let converted = ValueConverter.toKuzuValue(dict) as? [String: Any?]
        XCTAssertNotNil(converted)
        XCTAssertEqual(converted?["string"] as? String, "test")
        XCTAssertEqual(converted?["number"] as? Int, 123)
        XCTAssertEqual(converted?["bool"] as? Bool, true)
    }
    
    func testDictionaryWithOptionals() {
        let dict: [String: Any] = [
            "some": Optional<String>.some("test") as Any,
            "none": Optional<String>.none as Any,
            "null": NSNull()
        ]
        let converted = ValueConverter.toKuzuValue(dict) as? [String: Any?]
        XCTAssertNotNil(converted)
        XCTAssertEqual(converted?["some"] as? String, "test")
        // Note: Dictionary values can be nil, which is different from the key not existing
        // The key exists but the value is nil
        XCTAssertNotNil(converted?["none"]) // Key exists
        XCTAssertNil(converted?["none"]!) // But value is nil
        XCTAssertNotNil(converted?["null"]) // Key exists
        XCTAssertNil(converted?["null"]!) // But value is nil
    }
    
    func testNestedCollections() {
        let nested: [String: Any] = [
            "array": ["a", "b", "c"],
            "dict": ["x": 1, "y": 2],
            "mixed": [
                "nested_array": [1, 2, 3],
                "nested_optional": Optional<String>.some("test") as Any
            ]
        ]
        let converted = ValueConverter.toKuzuValue(nested) as? [String: Any?]
        XCTAssertNotNil(converted)
        
        let array = converted?["array"] as? [Any?]
        XCTAssertEqual(array?.count, 3)
        
        let dict = converted?["dict"] as? [String: Any?]
        XCTAssertEqual(dict?["x"] as? Int, 1)
        
        let mixed = converted?["mixed"] as? [String: Any?]
        let nestedArray = mixed?["nested_array"] as? [Any?]
        XCTAssertEqual(nestedArray?.count, 3)
        XCTAssertEqual(mixed?["nested_optional"] as? String, "test")
    }
    
    // MARK: - Edge Cases
    
    func testMaxRecursionDepth() {
        // Create a deeply nested structure that would exceed max depth
        var value: Any = "test"
        for _ in 0..<20 {
            value = Optional<Any>.some(value) as Any
        }
        
        // Should not crash and should eventually return a value
        let converted = ValueConverter.toKuzuValue(value)
        XCTAssertNotNil(converted)
    }
    
    func testPassThroughTypes() {
        // Test types that should pass through unchanged
        let int = 42
        let double = 3.14
        let bool = true
        let string = "test"
        
        XCTAssertEqual(ValueConverter.toKuzuValue(int) as? Int, 42)
        XCTAssertEqual(ValueConverter.toKuzuValue(double) as? Double, 3.14)
        XCTAssertEqual(ValueConverter.toKuzuValue(bool) as? Bool, true)
        XCTAssertEqual(ValueConverter.toKuzuValue(string) as? String, "test")
    }
    
    // MARK: - Batch Conversion Tests
    
    func testBatchDictionaryConversion() {
        let values: [String: Any] = [
            "date": Date(timeIntervalSince1970: 1234567890),
            "uuid": UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!,
            "optional": Optional<String>.some("test") as Any,
            "null": NSNull()
        ]
        
        let converted = ValueConverter.toKuzuValues(values)
        XCTAssertEqual(converted["date"] as? Double, 1234567890.0)
        XCTAssertEqual(converted["uuid"] as? String, (values["uuid"] as! UUID).uuidString)
        XCTAssertEqual(converted["optional"] as? String, "test")
        // The key exists but the value is nil
        XCTAssertNotNil(converted["null"]) // Key exists
        XCTAssertNil(converted["null"]!) // But value is nil
    }
    
    func testBatchArrayConversion() {
        let values: [Any] = [
            Date(timeIntervalSince1970: 1234567890),
            UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!,
            Optional<String>.some("test") as Any,
            NSNull()
        ]
        
        let converted = ValueConverter.toKuzuValues(values)
        XCTAssertEqual(converted[0] as? Double, 1234567890.0)
        XCTAssertEqual(converted[1] as? String, (values[1] as! UUID).uuidString)
        XCTAssertEqual(converted[2] as? String, "test")
        XCTAssertNil(converted[3])
    }
    
    // MARK: - From Kuzu Value Tests
    
    func testFromKuzuValueDate() {
        let timestamp = 1234567890.0
        let date = ValueConverter.fromKuzuValue(timestamp, to: Date.self)
        XCTAssertEqual(date?.timeIntervalSince1970, 1234567890.0)
        
        // Test with Int
        let intTimestamp = 1234567890
        let dateFromInt = ValueConverter.fromKuzuValue(intTimestamp, to: Date.self)
        XCTAssertEqual(dateFromInt?.timeIntervalSince1970, 1234567890.0)
        
        // Test with Int64
        let int64Timestamp: Int64 = 1234567890
        let dateFromInt64 = ValueConverter.fromKuzuValue(int64Timestamp, to: Date.self)
        XCTAssertEqual(dateFromInt64?.timeIntervalSince1970, 1234567890.0)
    }
    
    func testFromKuzuValueUUID() {
        let uuidString = "550e8400-e29b-41d4-a716-446655440000"
        let uuid = ValueConverter.fromKuzuValue(uuidString, to: UUID.self)
        XCTAssertEqual(uuid?.uuidString.lowercased(), "550e8400-e29b-41d4-a716-446655440000")
    }
    
    func testFromKuzuValueNumericConversions() {
        // Int to Int64
        let int = 42
        let int64 = ValueConverter.fromKuzuValue(int, to: Int64.self)
        XCTAssertEqual(int64, 42)
        
        // Int64 to Int
        let bigInt: Int64 = 12345
        let smallInt = ValueConverter.fromKuzuValue(bigInt, to: Int.self)
        XCTAssertEqual(smallInt, 12345)
        
        // Int to Double
        let intToDouble = ValueConverter.fromKuzuValue(42, to: Double.self)
        XCTAssertEqual(intToDouble, 42.0)
        
        // Float to Double
        let float: Float = 3.14
        let double = ValueConverter.fromKuzuValue(float, to: Double.self)
        XCTAssertEqual(double!, 3.14, accuracy: 0.001)
    }
    
    func testFromKuzuValueNSNull() {
        let null = NSNull()
        let string = ValueConverter.fromKuzuValue(null, to: String.self)
        XCTAssertNil(string)
        
        let int = ValueConverter.fromKuzuValue(null, to: Int.self)
        XCTAssertNil(int)
    }
}
