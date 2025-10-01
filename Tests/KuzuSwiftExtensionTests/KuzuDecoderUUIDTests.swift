import Testing
import Kuzu
@testable import KuzuSwiftExtension
import struct Foundation.UUID
import struct Foundation.Date
import class Foundation.ISO8601DateFormatter

// Test model with UUID
struct UUIDTestModel: Codable {
    let id: UUID
    let name: String
    let createdAt: Date
}

@Suite("KuzuDecoder UUID Tests")
struct KuzuDecoderUUIDTests {
    
    func createDatabaseAndConnection() throws -> (Database, Connection) {
        let database = try Database(":memory:")
        let connection = try Connection(database)
        
        // Create test table
        _ = try connection.query("CREATE NODE TABLE test (id STRING, name STRING, createdAt TIMESTAMP, PRIMARY KEY(id))")
        
        return (database, connection)
    }
    
    @Test("Decode UUID")
    func decodeUUID() throws {
        let (database, connection) = try createDatabaseAndConnection()
        
        // Prepare test data
        let testUUID = UUID()
        let testDate = Date()
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Insert test data
        _ = try connection.query("""
            CREATE (t:test {
                id: '\(testUUID.uuidString)',
                name: 'Test Name',
                createdAt: timestamp('\(iso8601.string(from: testDate))')
            })
        """)
        
        // Query and decode
        let result = try connection.query("MATCH (t:test) RETURN t")
        let decoder = KuzuDecoder()
        
        // Use KuzuDecoder's decode method directly - it handles node extraction automatically
        let decoded = try decoder.decode(UUIDTestModel.self, from: result)
        
        #expect(decoded.id.uuidString == testUUID.uuidString)
        #expect(decoded.name == "Test Name")
        // Allow small time difference due to conversion
        #expect(abs(decoded.createdAt.timeIntervalSince1970 - testDate.timeIntervalSince1970) < 1.0)
    }
    
    @Test("Decode multiple UUIDs")
    func decodeMultipleUUIDs() throws {
        let (_, connection) = try createDatabaseAndConnection()
        
        // Insert multiple records
        let uuids = (0..<5).map { _ in UUID() }
        
        for (index, uuid) in uuids.enumerated() {
            _ = try connection.query("""
                CREATE (t:test {
                    id: '\(uuid.uuidString)',
                    name: 'Test \(index)',
                    createdAt: timestamp('2024-01-0\(index + 1)T12:00:00.000Z')
                })
            """)
        }
        
        // Query all and decode
        let result = try connection.query("MATCH (t:test) RETURN t ORDER BY t.name")
        let decoder = KuzuDecoder()
        
        // Use KuzuDecoder's decodeArray method directly - it handles node extraction automatically
        let decodedModels = try decoder.decodeArray(UUIDTestModel.self, from: result)
        
        #expect(decodedModels.count == 5)
        
        // Verify all UUIDs were decoded correctly
        for (index, model) in decodedModels.enumerated() {
            #expect(model.id == uuids[index])
            #expect(model.name == "Test \(index)")
        }
    }
}