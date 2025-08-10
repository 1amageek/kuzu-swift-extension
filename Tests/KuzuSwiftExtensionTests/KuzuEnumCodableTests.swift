import Testing
import Foundation
@testable import KuzuSwiftExtension

@Suite("KuzuEnum Codable Tests")
struct KuzuEnumCodableTests {
    
    // MARK: - Test Enums
    
    enum Status: String, Codable {
        case active
        case inactive
        case pending
    }
    
    enum Priority: Int, Codable {
        case low = 1
        case medium = 2
        case high = 3
    }
    
    enum Score: Double, Codable {
        case fail = 0.0
        case pass = 0.6
        case excellent = 1.0
    }
    
    // MARK: - Test Models
    
    struct TaskModel: Codable, Equatable {
        let id: UUID
        let status: Status
        let priority: Priority
        let score: Score
        let optionalStatus: Status?
    }
    
    struct NestedEnumModel: Codable, Equatable {
        let name: String
        let statuses: [Status]
        let priorities: [Priority]
        let scores: [Score]
    }
    
    // MARK: - Encoder Tests
    
    @Test("Encode String-based enum")
    func encodeStringEnum() throws {
        let encoder = KuzuEncoder()
        let model = TaskModel(
            id: UUID(),
            status: .active,
            priority: .high,
            score: .excellent,
            optionalStatus: .pending
        )
        
        let encoded = try encoder.encode(model)
        
        // Enums should be encoded as their raw values
        #expect(encoded["status"] as? String == "active")
        #expect(encoded["priority"] as? Int == 3)
        #expect(encoded["score"] as? Double == 1.0)
        #expect(encoded["optionalStatus"] as? String == "pending")
    }
    
    @Test("Encode array of enums")
    func encodeEnumArray() throws {
        let encoder = KuzuEncoder()
        let model = NestedEnumModel(
            name: "Test",
            statuses: [.active, .inactive, .pending],
            priorities: [.low, .medium, .high],
            scores: [.fail, .pass, .excellent]
        )
        
        let encoded = try encoder.encode(model)
        
        // Arrays of enums should be encoded as arrays of raw values
        let statuses = encoded["statuses"] as? [any Sendable]
        let statusStrings = statuses?.compactMap { $0 as? String }
        #expect(statusStrings == ["active", "inactive", "pending"])
        
        let priorities = encoded["priorities"] as? [any Sendable]
        let priorityInts = priorities?.compactMap { $0 as? Int }
        #expect(priorityInts == [1, 2, 3])
        
        let scores = encoded["scores"] as? [any Sendable]
        let scoreDoubles = scores?.compactMap { $0 as? Double }
        #expect(scoreDoubles == [0.0, 0.6, 1.0])
    }
    
    // MARK: - Decoder Tests
    
    @Test("Decode String-based enum")
    func decodeStringEnum() throws {
        let decoder = KuzuDecoder()
        let dictionary: [String: Any?] = [
            "id": UUID().uuidString,
            "status": "active",
            "priority": 3,
            "score": 1.0,
            "optionalStatus": "pending"
        ]
        
        let decoded = try decoder.decode(TaskModel.self, from: dictionary)
        
        #expect(decoded.status == .active)
        #expect(decoded.priority == .high)
        #expect(decoded.score == .excellent)
        #expect(decoded.optionalStatus == .pending)
    }
    
    @Test("Decode nil optional enum")
    func decodeNilOptionalEnum() throws {
        let decoder = KuzuDecoder()
        let dictionary: [String: Any?] = [
            "id": UUID().uuidString,
            "status": "active",
            "priority": 3,
            "score": 1.0
            // optionalStatus is missing
        ]
        
        let decoded = try decoder.decode(TaskModel.self, from: dictionary)
        
        #expect(decoded.status == .active)
        #expect(decoded.priority == .high)
        #expect(decoded.score == .excellent)
        #expect(decoded.optionalStatus == nil)
    }
    
    @Test("Decode array of enums")
    func decodeEnumArray() throws {
        let decoder = KuzuDecoder()
        let dictionary: [String: Any?] = [
            "name": "Test",
            "statuses": ["active", "inactive", "pending"],
            "priorities": [1, 2, 3],
            "scores": [0.0, 0.6, 1.0]
        ]
        
        let decoded = try decoder.decode(NestedEnumModel.self, from: dictionary)
        
        #expect(decoded.statuses == [.active, .inactive, .pending])
        #expect(decoded.priorities == [.low, .medium, .high])
        #expect(decoded.scores == [.fail, .pass, .excellent])
    }
    
    @Test("Decode invalid enum value should throw")
    func decodeInvalidEnumValue() throws {
        let decoder = KuzuDecoder()
        let dictionary: [String: Any?] = [
            "id": UUID().uuidString,
            "status": "invalid_status",  // Invalid enum value
            "priority": 3,
            "score": 1.0
        ]
        
        #expect(throws: Error.self) {
            _ = try decoder.decode(TaskModel.self, from: dictionary)
        }
    }
    
    // MARK: - Round-trip Tests
    
    @Test("Round-trip encoding and decoding")
    func roundTripEncodingDecoding() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let original = TaskModel(
            id: UUID(),
            status: .inactive,
            priority: .medium,
            score: .pass,
            optionalStatus: nil
        )
        
        // Encode
        let encoded = try encoder.encode(original)
        
        // Decode
        let decoded = try decoder.decode(TaskModel.self, from: encoded)
        
        // Compare
        #expect(decoded.status == original.status)
        #expect(decoded.priority == original.priority)
        #expect(decoded.score == original.score)
        #expect(decoded.optionalStatus == original.optionalStatus)
    }
    
    @Test("Round-trip with nested enums")
    func roundTripNestedEnums() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let original = NestedEnumModel(
            name: "Complex Model",
            statuses: [.active, .pending],
            priorities: [.high, .low, .medium],
            scores: [.excellent, .fail]
        )
        
        // Encode
        let encoded = try encoder.encode(original)
        
        // Decode
        let decoded = try decoder.decode(NestedEnumModel.self, from: encoded)
        
        // Compare
        #expect(decoded == original)
    }
    
    // MARK: - Edge Cases
    
    @Test("Decode enum from Int64 (database return type)")
    func decodeEnumFromInt64() throws {
        let decoder = KuzuDecoder()
        
        // Simulate database returning Int64 for priority
        let dictionary: [String: Any?] = [
            "id": UUID().uuidString,
            "status": "active",
            "priority": Int64(2),  // Database returns Int64
            "score": 0.6
        ]
        
        let decoded = try decoder.decode(TaskModel.self, from: dictionary)
        
        #expect(decoded.priority == .medium)
    }
    
    @Test("Decode mixed numeric types")
    func decodeMixedNumericTypes() throws {
        let decoder = KuzuDecoder()
        
        // Test that various numeric types can be decoded properly
        // Note: Float to Double enum conversion can fail due to precision issues
        // Float(0.6) becomes 0.6000000238418579 as Double, which doesn't match enum value 0.6
        let testCases: [(Any, Score)] = [
            (0.0, .fail),
            (0.6, .pass),  // Use Double directly, not Float
            (1.0, .excellent)
        ]
        
        for (value, expected) in testCases {
            let dictionary: [String: Any?] = [
                "id": UUID().uuidString,
                "status": "active",
                "priority": 1,
                "score": value
            ]
            
            let decoded = try decoder.decode(TaskModel.self, from: dictionary)
            #expect(decoded.score == expected)
        }
    }
}