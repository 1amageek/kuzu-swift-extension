import XCTest
import Kuzu
@testable import KuzuSwiftExtension

// Test model with UUID
struct UUIDTestModel: Codable {
    let id: UUID
    let name: String
    let createdAt: Date
}

final class KuzuDecoderUUIDTests: XCTestCase {
    var database: Database!
    var connection: Connection!
    
    override func setUp() async throws {
        try await super.setUp()
        database = try Database(":memory:")
        connection = try Connection(database)
        
        // Create test table
        try connection.query("CREATE NODE TABLE test (id STRING, name STRING, createdAt TIMESTAMP, PRIMARY KEY(id))")
    }
    
    override func tearDown() async throws {
        connection = nil
        database = nil
        try await super.tearDown()
    }
    
    func testDecodeUUID() throws {
        // Prepare test data
        let testUUID = UUID()
        let testDate = Date()
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Insert test data
        try connection.query("""
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
        
        XCTAssertEqual(decoded.id.uuidString, testUUID.uuidString)
        XCTAssertEqual(decoded.name, "Test Name")
        // Allow small time difference due to conversion
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, testDate.timeIntervalSince1970, accuracy: 1.0)
    }
    
    func testDecodeMultipleUUIDs() throws {
        // Insert multiple records
        let uuids = (0..<5).map { _ in UUID() }
        
        for (index, uuid) in uuids.enumerated() {
            try connection.query("""
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
        
        XCTAssertEqual(decodedModels.count, 5)
        
        // Verify all UUIDs were decoded correctly
        for (index, model) in decodedModels.enumerated() {
            XCTAssertEqual(model.id, uuids[index])
            XCTAssertEqual(model.name, "Test \(index)")
        }
    }
}