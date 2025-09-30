import Testing
@testable import KuzuSwiftExtension
import struct Foundation.UUID

@GraphNode
struct DecodeTestUser: Codable, Sendable {
    @ID var id: UUID = UUID()
    var name: String
    var age: Int
    
    init(name: String, age: Int) {
        self.id = UUID()
        self.name = name
        self.age = age
    }
}

@Suite("Decode Debug Tests")
struct DecodeDebugTest {
    
    @Test("Debug decode issue")
    func debugDecode() async throws {
        let config = GraphConfiguration(databasePath: ":memory:")
        let context = try await GraphContext(configuration: config)
        
        // Create schema
        try await context.createSchema(for: [DecodeTestUser.self])
        
        // Insert users
        let users = [
            DecodeTestUser(name: "Young", age: 20),
            DecodeTestUser(name: "Adult", age: 30),
            DecodeTestUser(name: "Senior", age: 60)
        ]
        
        for user in users {
            _ = try await context.save(user)
        }
        
        // Query and decode
        print("Querying users...")
        let result = try await context.raw("MATCH (u:DecodeTestUser) WHERE u.age > 25 RETURN u ORDER BY u.name")
        
        print("Column names: \(result.getColumnNames())")
        
        // Manual iteration to debug
        var count = 0
        while result.hasNext() {
            guard let flatTuple = try result.getNext() else { break }
            print("Row \(count):")
            
            if let value = try flatTuple.getValue(0) {
                print("  Raw value type: \(type(of: value))")
                print("  Raw value: \(value)")
                
                if let dict = value as? [String: Any?] {
                    print("  Dictionary keys: \(dict.keys)")
                    for (key, val) in dict {
                        print("    \(key): \(String(describing: val)) (type: \(type(of: val)))")
                    }
                }
            }
            count += 1
        }
        
        print("Total rows: \(count)")
        
        // Now try decode
        let result2 = try await context.raw("MATCH (u:DecodeTestUser) WHERE u.age > 25 RETURN u ORDER BY u.name")
        let decoded = try result2.decodeArray(DecodeTestUser.self)
        print("Decoded count: \(decoded.count)")
        for user in decoded {
            print("  User: \(user.name), age: \(user.age)")
        }
        
        await context.close()
    }
}