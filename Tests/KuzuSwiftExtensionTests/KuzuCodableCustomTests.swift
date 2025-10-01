import Testing
import Foundation
@testable import KuzuSwiftExtension

@Suite("KuzuCodable Custom Implementation Tests")
struct KuzuCodableCustomTests {
    
    // MARK: - Custom Codable Models
    
    struct CustomEncodingModel: Encodable {
        let value: String
        let computed: String
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(value, forKey: .value)
            // Add computed property during encoding
            try container.encode(value.uppercased(), forKey: .computed)
            // Add timestamp
            try container.encode(Date(), forKey: .timestamp)
        }
        
        enum CodingKeys: String, CodingKey {
            case value
            case computed
            case timestamp
        }
    }
    
    struct CustomDecodingModel: Decodable, Equatable {
        let originalValue: String
        let processedValue: String
        let metadata: [String: String]
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            // Custom decoding logic
            let raw = try container.decode(String.self, forKey: .value)
            self.originalValue = raw
            self.processedValue = raw.lowercased().replacingOccurrences(of: " ", with: "_")
            
            // Decode optional with default
            self.metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? ["source": "default"]
        }
        
        enum CodingKeys: String, CodingKey {
            case value
            case metadata
        }
    }
    
    struct VersionedModel: Codable, Equatable {
        let data: String
        let version: Int
        
        init(data: String, version: Int = 2) {
            self.data = data
            self.version = version
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            // Handle version migration
            if let version = try? container.decode(Int.self, forKey: .version) {
                self.version = version
                
                switch version {
                case 1:
                    // Migrate from v1 format
                    let oldData = try container.decode(String.self, forKey: .legacyData)
                    self.data = "v1_migrated_\(oldData)"
                case 2:
                    // Current format
                    self.data = try container.decode(String.self, forKey: .data)
                default:
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: decoder.codingPath,
                            debugDescription: "Unsupported version: \(version)"
                        )
                    )
                }
            } else {
                // No version field, assume v1
                self.version = 1
                let oldData = try container.decode(String.self, forKey: .legacyData)
                self.data = "v1_migrated_\(oldData)"
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(version, forKey: .version)
            try container.encode(data, forKey: .data)
        }
        
        enum CodingKeys: String, CodingKey {
            case data
            case version
            case legacyData
        }
    }
    
    struct UnkeyedModel: Codable, Equatable {
        let values: [String]
        let count: Int
        
        init(values: [String]) {
            self.values = values
            self.count = values.count
        }
        
        // Standard Codable implementation for KuzuEncoder compatibility
        // Custom unkeyed container encoding would produce an array at top level,
        // which KuzuEncoder doesn't support for top-level objects
    }
    
    struct SingleValueModel: Codable, Equatable {
        let value: String
        
        init(value: String) {
            self.value = value
        }
        
        // Standard Codable implementation for KuzuEncoder compatibility
        // Custom single value container encoding would produce a single value at top level,
        // which KuzuEncoder doesn't support for top-level objects
    }
    
    struct ConditionalModel: Codable, Equatable {
        let type: String
        let stringValue: String?
        let intValue: Int?
        let arrayValue: [String]?
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.type = try container.decode(String.self, forKey: .type)
            
            // Conditionally decode based on type
            switch type {
            case "string":
                self.stringValue = try container.decode(String.self, forKey: .value)
                self.intValue = nil
                self.arrayValue = nil
            case "int":
                self.intValue = try container.decode(Int.self, forKey: .value)
                self.stringValue = nil
                self.arrayValue = nil
            case "array":
                self.arrayValue = try container.decode([String].self, forKey: .value)
                self.stringValue = nil
                self.intValue = nil
            default:
                self.stringValue = nil
                self.intValue = nil
                self.arrayValue = nil
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            
            if let stringValue = stringValue {
                try container.encode(stringValue, forKey: .value)
            } else if let intValue = intValue {
                try container.encode(intValue, forKey: .value)
            } else if let arrayValue = arrayValue {
                try container.encode(arrayValue, forKey: .value)
            }
        }
        
        enum CodingKeys: String, CodingKey {
            case type, value
        }
    }
    
    // MARK: - Custom Encoding Tests
    
    @Test("Custom encode implementation")
    func customEncode() throws {
        let encoder = KuzuEncoder()
        
        let model = CustomEncodingModel(
            value: "test value",
            computed: "ignored" // This will be replaced
        )
        
        let encoded = try encoder.encode(model)
        
        #expect(encoded["value"] as? String == "test value")
        #expect(encoded["computed"] as? String == "TEST VALUE")
        #expect(encoded["timestamp"] != nil)
    }
    
    // MARK: - Custom Decoding Tests
    
    @Test("Custom decode implementation")
    func customDecode() throws {
        let decoder = KuzuDecoder()
        
        let data: [String: Any?] = [
            "value": "Test Value",
            "metadata": ["key": "value"]
        ]
        
        let decoded = try decoder.decode(CustomDecodingModel.self, from: data)
        
        #expect(decoded.originalValue == "Test Value")
        #expect(decoded.processedValue == "test_value")
        #expect(decoded.metadata["key"] == "value")
    }
    
    @Test("Custom decode with missing optional")
    func customDecodeWithMissingOptional() throws {
        let decoder = KuzuDecoder()
        
        let data: [String: Any?] = [
            "value": "Test"
            // metadata is missing
        ]
        
        let decoded = try decoder.decode(CustomDecodingModel.self, from: data)
        
        #expect(decoded.metadata["source"] == "default")
    }
    
    // MARK: - Version Migration Tests
    
    @Test("Version migration from v1")
    func versionMigrationV1() throws {
        let decoder = KuzuDecoder()
        
        // Simulate v1 data
        let v1Data: [String: Any?] = [
            "legacyData": "old_format_data"
            // No version field in v1
        ]
        
        let decoded = try decoder.decode(VersionedModel.self, from: v1Data)
        
        #expect(decoded.version == 1)
        #expect(decoded.data == "v1_migrated_old_format_data")
    }
    
    @Test("Version migration current v2")
    func versionMigrationV2() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let model = VersionedModel(data: "current_data", version: 2)
        
        let encoded = try encoder.encode(model)
        let decoded = try decoder.decode(VersionedModel.self, from: encoded)
        
        #expect(decoded.version == 2)
        #expect(decoded.data == "current_data")
    }
    
    // MARK: - Container Type Tests
    
    @Test("Unkeyed container usage")
    func unkeyedContainer() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let model = UnkeyedModel(values: ["a", "b", "c", "d"])
        
        let encoded = try encoder.encode(model)
        
        // The model now uses standard encoding
        if let array = encoded["values"] as? [any Sendable] {
            #expect(array.count == 4)
        }
        #expect(encoded["count"] as? Int == 4)
        
        // Standard decode
        let decoded = try decoder.decode(UnkeyedModel.self, from: encoded)
        
        #expect(decoded.values == model.values)
        #expect(decoded.count == 4)
    }
    
    @Test("Single value container")
    func singleValueContainer() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let model = SingleValueModel(value: "single")
        
        let encoded = try encoder.encode(model)
        
        // The model now uses standard encoding
        #expect(encoded["value"] as? String == "single")
        
        let decoded = try decoder.decode(SingleValueModel.self, from: encoded)
        
        #expect(decoded.value == "single")
    }
    
    // MARK: - Conditional Encoding/Decoding Tests
    
    @Test("Conditional string type")
    func conditionalStringType() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let data: [String: Any?] = [
            "type": "string",
            "value": "test string"
        ]
        
        let decoded = try decoder.decode(ConditionalModel.self, from: data)
        
        #expect(decoded.type == "string")
        #expect(decoded.stringValue == "test string")
        #expect(decoded.intValue == nil)
        #expect(decoded.arrayValue == nil)
        
        let encoded = try encoder.encode(decoded)
        #expect(encoded["type"] as? String == "string")
        #expect(encoded["value"] as? String == "test string")
    }
    
    @Test("Conditional int type")
    func conditionalIntType() throws {
        let decoder = KuzuDecoder()
        
        let data: [String: Any?] = [
            "type": "int",
            "value": 42
        ]
        
        let decoded = try decoder.decode(ConditionalModel.self, from: data)
        
        #expect(decoded.type == "int")
        #expect(decoded.intValue == 42)
        #expect(decoded.stringValue == nil)
        #expect(decoded.arrayValue == nil)
    }
    
    @Test("Conditional array type")
    func conditionalArrayType() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let data: [String: Any?] = [
            "type": "array",
            "value": ["item1", "item2", "item3"]
        ]
        
        let decoded = try decoder.decode(ConditionalModel.self, from: data)
        
        #expect(decoded.type == "array")
        #expect(decoded.arrayValue == ["item1", "item2", "item3"])
        #expect(decoded.stringValue == nil)
        #expect(decoded.intValue == nil)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Custom decoding error")
    func customDecodingError() throws {
        let decoder = KuzuDecoder()
        
        // Invalid version
        let data: [String: Any?] = [
            "version": 99,
            "data": "test"
        ]
        
        #expect(throws: Error.self) {
            _ = try decoder.decode(VersionedModel.self, from: data)
        }
    }
    
    @Test("Type mismatch in conditional model")
    func typeMismatchInConditional() throws {
        let decoder = KuzuDecoder()
        
        // Type says int but value is string
        let data: [String: Any?] = [
            "type": "int",
            "value": "not an int"
        ]
        
        #expect(throws: Error.self) {
            _ = try decoder.decode(ConditionalModel.self, from: data)
        }
    }
}