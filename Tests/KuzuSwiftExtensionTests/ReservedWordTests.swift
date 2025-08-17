import Testing
import Foundation
@testable import KuzuSwiftExtension
import Kuzu

@Suite("Reserved Word Tests")
struct ReservedWordTests {
    
    // Models with reserved words as property names
    @GraphNode
    struct OrderModel: Codable, Sendable {
        @ID var id: UUID = UUID()
        var group: String       // "group" is a reserved word
        var order: Int         // "order" is a reserved word  
        var limit: Double      // "limit" is a reserved word
        var count: Int         // "count" is a reserved word
    }
    
    @GraphNode
    struct SelectModel: Codable, Sendable {
        @ID var id: UUID = UUID()
        var select: String     // "select" is a reserved word
        var from: String       // "from" is a reserved word
        var table: String      // "table" is a reserved word (changed from "where" which is a Swift keyword)
    }
    
    @GraphEdge(from: OrderModel.self, to: SelectModel.self)
    struct JoinRelation: Codable, Sendable {
        var by: String         // "by" is a reserved word
        var exists: Bool       // "exists" is a reserved word
    }
    
    @Test("Models with reserved word properties should generate escaped DDL")
    func testReservedWordEscaping() async throws {
        // Get the generated DDL
        let orderDDL = OrderModel._kuzuDDL
        let selectDDL = SelectModel._kuzuDDL
        let joinDDL = JoinRelation._kuzuDDL
        
        // Verify that reserved words are escaped with backticks
        #expect(orderDDL.contains("`group`"))
        #expect(orderDDL.contains("`order`"))
        #expect(orderDDL.contains("`limit`"))
        #expect(orderDDL.contains("`count`"))
        
        #expect(selectDDL.contains("`select`"))
        #expect(selectDDL.contains("`from`"))
        #expect(selectDDL.contains("`table`"))
        
        #expect(joinDDL.contains("`by`"))
        #expect(joinDDL.contains("`exists`"))
    }
    
    @Test("Schema with reserved words should be created successfully")
    func testReservedWordSchemaCreation() async throws {
        // Create in-memory database
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let configuration = GraphConfiguration(
            databasePath: tempDir.path
        )
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create context and migration manager
        let context = try await GraphContext(configuration: configuration)
        let migrationManager = MigrationManager(context: context, policy: .safe)
        
        // This should succeed even with reserved word properties
        try await migrationManager.migrate(types: [
            OrderModel.self,
            SelectModel.self,
            JoinRelation.self
        ])
        
        // Verify we can insert data
        let orderId = UUID()
        let selectId = UUID()
        
        // Create nodes with only the ID first
        _ = try await context.raw(
            "CREATE (o:OrderModel {id: $id})",
            bindings: ["id": orderId.uuidString]
        )
        
        _ = try await context.raw(
            "CREATE (s:SelectModel {id: $id})",
            bindings: ["id": selectId.uuidString]
        )
        
        // Note: Reserved word properties in DDL are escaped with backticks
        // But in practice, it's better to avoid reserved words as property names
        // This test verifies that the DDL generation works correctly
        
        // Create relationship between nodes
        _ = try await context.raw(
            """
            MATCH (o:OrderModel {id: $orderId}), (s:SelectModel {id: $selectId})
            CREATE (o)-[:JoinRelation]->(s)
            """,
            bindings: [
                "orderId": orderId.uuidString,
                "selectId": selectId.uuidString
            ]
        )
        
        // Verify the relationship was created
        let result = try await context.raw(
            """
            MATCH (o:OrderModel)-[:JoinRelation]->(s:SelectModel)
            RETURN count(*) as cnt
            """,
            bindings: [:]
        )
        
        let rows = try result.mapRows()
        #expect(rows.count == 1)
        #expect(rows[0]["cnt"] as? Int64 == 1)
    }
    
    // Define model at struct level for testing mixed fields
    @GraphNode
    struct MixedModel: Codable, Sendable {
        @ID var id: UUID = UUID()
        var normalField: String
        var order: Int         // reserved
        var anotherField: Double
        var group: String      // reserved
    }
    
    @Test("Mixed reserved and normal words should work correctly")
    func testMixedReservedAndNormalWords() {
        let ddl = MixedModel._kuzuDDL
        
        // Normal fields should not be escaped
        #expect(ddl.contains("normalField") && !ddl.contains("`normalField`"))
        #expect(ddl.contains("anotherField") && !ddl.contains("`anotherField`"))
        
        // Reserved words should be escaped
        #expect(ddl.contains("`order`"))
        #expect(ddl.contains("`group`"))
    }
}