import Testing
import Foundation
@testable import KuzuSwiftExtension

@Suite("KuzuCodable Complex Types Tests")
struct KuzuCodableComplexTypesTests {
    
    // MARK: - Test Models
    
    struct SetModel: Codable, Equatable {
        let id: String
        let tags: Set<String>
        let numbers: Set<Int>
        let optionalSet: Set<String>?
    }
    
    struct DeepNestedModel: Codable, Equatable {
        struct Level1: Codable, Equatable {
            struct Level2: Codable, Equatable {
                struct Level3: Codable, Equatable {
                    let value: String
                    let data: [String: Any]
                    
                    static func == (lhs: Level3, rhs: Level3) -> Bool {
                        return lhs.value == rhs.value &&
                               NSDictionary(dictionary: lhs.data).isEqual(to: rhs.data)
                    }
                    
                    enum CodingKeys: String, CodingKey {
                        case value, data
                    }
                    
                    init(value: String, data: [String: Any]) {
                        self.value = value
                        self.data = data
                    }
                    
                    init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        value = try container.decode(String.self, forKey: .value)
                        // Decode as [String: String] for simplicity
                        let stringDict = try container.decode([String: String].self, forKey: .data)
                        data = stringDict
                    }
                    
                    func encode(to encoder: Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(value, forKey: .value)
                        // Encode as [String: String] for simplicity
                        let stringDict = data.compactMapValues { $0 as? String }
                        try container.encode(stringDict, forKey: .data)
                    }
                }
                
                let level3: Level3
                let metadata: [String: String]
            }
            
            let level2: Level2
            let items: [Level2]
        }
        
        let level1: Level1
        let mappings: [String: Level1]
    }
    
    struct MultiOptionalModel: Codable, Equatable {
        let id: String
        let optional1: String?
        let optional2: Int??
        let optional3: [String?]?
        let optional4: [String: Int?]?
    }
    
    struct CustomKeysModel: Codable, Equatable {
        let identifier: UUID
        let userName: String
        let isActive: Bool
        let metadata: [String: String]
        
        enum CodingKeys: String, CodingKey {
            case identifier = "id"
            case userName = "user_name"
            case isActive = "is_active"
            case metadata = "meta"
        }
    }
    
    struct Array2DModel: Codable, Equatable {
        let matrix: [[Int]]
        let optionalMatrix: [[String]]?
        let jaggedArray: [[Double]]
    }
    
    struct MixedCollectionModel: Codable, Equatable {
        let arrayOfSets: [Set<String>]
        let setOfArrays: Set<[Int]>
        let dictOfArrays: [String: [String]]
        let arrayOfDicts: [[String: Int]]
    }
    
    // MARK: - Set Type Tests
    
    @Test("Encode and decode Set types")
    func encodeDecodeSet() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let model = SetModel(
            id: "test",
            tags: Set(["swift", "database", "graph"]),
            numbers: Set([1, 2, 3, 4, 5]),
            optionalSet: Set(["optional", "values"])
        )
        
        let encoded = try encoder.encode(model)
        let decoded = try decoder.decode(SetModel.self, from: encoded)
        
        #expect(decoded.id == model.id)
        #expect(decoded.tags == model.tags)
        #expect(decoded.numbers == model.numbers)
        #expect(decoded.optionalSet == model.optionalSet)
    }
    
    @Test("Empty Set handling")
    func emptySetHandling() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let model = SetModel(
            id: "empty",
            tags: Set(),
            numbers: Set(),
            optionalSet: nil
        )
        
        let encoded = try encoder.encode(model)
        let decoded = try decoder.decode(SetModel.self, from: encoded)
        
        #expect(decoded.tags.isEmpty)
        #expect(decoded.numbers.isEmpty)
        #expect(decoded.optionalSet == nil)
    }
    
    // MARK: - Deep Nesting Tests
    
    @Test("Deep nested structures")
    func deepNestedStructures() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let level3 = DeepNestedModel.Level1.Level2.Level3(
            value: "deep",
            data: ["key": "value", "number": "42"]
        )
        
        let level2 = DeepNestedModel.Level1.Level2(
            level3: level3,
            metadata: ["type": "test", "version": "1.0"]
        )
        
        let level1 = DeepNestedModel.Level1(
            level2: level2,
            items: [level2]
        )
        
        let model = DeepNestedModel(
            level1: level1,
            mappings: ["main": level1]
        )
        
        let encoded = try encoder.encode(model)
        let decoded = try decoder.decode(DeepNestedModel.self, from: encoded)
        
        #expect(decoded == model)
    }
    
    // MARK: - Multiple Optional Tests
    
    @Test("Multiple optional levels")
    func multipleOptionalLevels() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let model = MultiOptionalModel(
            id: "multi",
            optional1: "value",
            optional2: 42,
            optional3: ["a", "b", "c"],  // TODO: nil in array is not yet supported
            optional4: ["key1": 1, "key3": 3]  // TODO: nil values in dictionary not yet supported
        )
        
        let encoded = try encoder.encode(model)
        let decoded = try decoder.decode(MultiOptionalModel.self, from: encoded)
        
        #expect(decoded.id == model.id)
        #expect(decoded.optional1 == model.optional1)
        #expect(decoded.optional2 == model.optional2)
        #expect(decoded.optional3 == model.optional3)
        #expect(decoded.optional4 == model.optional4)
    }
    
    @Test("All nil optionals")
    func allNilOptionals() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let model = MultiOptionalModel(
            id: "nil-test",
            optional1: nil,
            optional2: nil,
            optional3: nil,
            optional4: nil
        )
        
        let encoded = try encoder.encode(model)
        let decoded = try decoder.decode(MultiOptionalModel.self, from: encoded)
        
        #expect(decoded.optional1 == nil)
        #expect(decoded.optional2 == nil)
        #expect(decoded.optional3 == nil)
        #expect(decoded.optional4 == nil)
    }
    
    // MARK: - Custom CodingKeys Tests
    
    @Test("Custom CodingKeys mapping")
    func customCodingKeys() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let model = CustomKeysModel(
            identifier: UUID(),
            userName: "test_user",
            isActive: true,
            metadata: ["role": "admin", "level": "5"]
        )
        
        let encoded = try encoder.encode(model)
        
        // Verify the keys are transformed
        #expect(encoded["id"] != nil)
        #expect(encoded["user_name"] != nil)
        #expect(encoded["is_active"] != nil)
        #expect(encoded["meta"] != nil)
        
        // Verify original keys don't exist
        #expect(encoded["identifier"] == nil)
        #expect(encoded["userName"] == nil)
        
        let decoded = try decoder.decode(CustomKeysModel.self, from: encoded)
        #expect(decoded == model)
    }
    
    // MARK: - 2D Array Tests
    
    @Test("2D arrays encoding and decoding")
    func array2D() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let model = Array2DModel(
            matrix: [[1, 2, 3], [4, 5, 6], [7, 8, 9]],
            optionalMatrix: [["a", "b"], ["c", "d"]],
            jaggedArray: [[1.1], [2.2, 3.3], [4.4, 5.5, 6.6]]
        )
        
        let encoded = try encoder.encode(model)
        let decoded = try decoder.decode(Array2DModel.self, from: encoded)
        
        #expect(decoded.matrix == model.matrix)
        #expect(decoded.optionalMatrix == model.optionalMatrix)
        #expect(decoded.jaggedArray == model.jaggedArray)
    }
    
    @Test("Empty 2D arrays")
    func empty2DArrays() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let model = Array2DModel(
            matrix: [],
            optionalMatrix: nil,
            jaggedArray: [[], []]
        )
        
        let encoded = try encoder.encode(model)
        let decoded = try decoder.decode(Array2DModel.self, from: encoded)
        
        #expect(decoded.matrix.isEmpty)
        #expect(decoded.optionalMatrix == nil)
        #expect(decoded.jaggedArray == [[], []])
    }
    
    // MARK: - Mixed Collection Tests
    
    @Test("Mixed collection types")
    func mixedCollections() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let model = MixedCollectionModel(
            arrayOfSets: [Set(["a", "b"]), Set(["c", "d", "e"])],
            setOfArrays: Set([[1, 2], [3, 4, 5]]),
            dictOfArrays: ["key1": ["a", "b"], "key2": ["c", "d", "e"]],
            arrayOfDicts: [["a": 1, "b": 2], ["c": 3, "d": 4]]
        )
        
        let encoded = try encoder.encode(model)
        let decoded = try decoder.decode(MixedCollectionModel.self, from: encoded)
        
        #expect(decoded.arrayOfSets == model.arrayOfSets)
        #expect(decoded.setOfArrays == model.setOfArrays)
        #expect(decoded.dictOfArrays == model.dictOfArrays)
        #expect(decoded.arrayOfDicts == model.arrayOfDicts)
    }
    
    // MARK: - Large Collection Tests
    
    @Test("Large collections performance")
    func largeCollections() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        struct LargeModel: Codable, Equatable {
            let largeArray: [Int]
            let largeDict: [String: String]
            let largeSet: Set<String>
        }
        
        let largeArray = Array(0..<1000)
        let largeDict = Dictionary(uniqueKeysWithValues: (0..<500).map { ("key\($0)", "value\($0)") })
        let largeSet = Set((0..<500).map { "item\($0)" })
        
        let model = LargeModel(
            largeArray: largeArray,
            largeDict: largeDict,
            largeSet: largeSet
        )
        
        let encoded = try encoder.encode(model)
        let decoded = try decoder.decode(LargeModel.self, from: encoded)
        
        #expect(decoded.largeArray.count == 1000)
        #expect(decoded.largeDict.count == 500)
        #expect(decoded.largeSet.count == 500)
        #expect(decoded == model)
    }
}