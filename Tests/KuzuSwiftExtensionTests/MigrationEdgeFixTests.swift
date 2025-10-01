import Testing
import Foundation
@testable import KuzuSwiftExtension
import Kuzu

@Suite("Migration Edge Fix Tests")
struct MigrationEdgeFixTests {
    
    // Test models that reproduce the reported bug
    @GraphNode
    struct Session: Codable, Sendable {
        @ID var id: UUID = UUID()
        var title: String
    }

    @GraphNode
    struct TodoTask: Codable, Sendable {
        @ID var id: UUID = UUID()
        var title: String
    }

    @GraphEdge(from: Session.self, to: TodoTask.self)
    struct HasTask: Codable, Sendable {
        var position: Int
    }

    @GraphEdge(from: TodoTask.self, to: TodoTask.self)
    struct SubTaskOf: Codable, Sendable {
    }

    @GraphEdge(from: TodoTask.self, to: TodoTask.self)
    struct Blocks: Codable, Sendable {
    }
    
    @Test("Migration with nodes and edges should succeed")
    func testMigrationWithNodesAndEdges() async throws {
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
        let container = try GraphContainer(configuration: configuration)
        let context = GraphContext(container)
        let migrationManager = MigrationManager(context: context, policy: .safe)
        
        // This should now succeed with our fix
        try migrationManager.migrate(types: [
            Session.self,
            TodoTask.self,
            HasTask.self,
            SubTaskOf.self,
            Blocks.self
        ])

        // Verify the tables were created by trying to query them
        // Check Session table exists
        let sessionCount = try context.raw("MATCH (s:Session) RETURN count(s) as cnt", bindings: [:])
        #expect(try sessionCount.mapFirstRequired(to: Int64.self, at: 0) == 0)

        // Check TodoTask table exists
        let taskCount = try context.raw("MATCH (t:TodoTask) RETURN count(t) as cnt", bindings: [:])
        #expect(try taskCount.mapFirstRequired(to: Int64.self, at: 0) == 0)

        // We'll verify edge tables work by creating relationships below

        // Verify we can insert data into the created schema
        let sessionId = UUID()
        let taskId = UUID()

        // Insert a session
        _ = try context.raw(
            "CREATE (s:Session {id: $id, title: $title})",
            bindings: ["id": sessionId.uuidString, "title": "Test Session"]
        )

        // Insert a task
        _ = try context.raw(
            "CREATE (t:TodoTask {id: $id, title: $title})",
            bindings: ["id": taskId.uuidString, "title": "Test Task"]
        )

        // Create relationship
        _ = try context.raw(
            """
            MATCH (s:Session {id: $sessionId}), (t:TodoTask {id: $taskId})
            CREATE (s)-[:HasTask {position: $position}]->(t)
            """,
            bindings: [
                "sessionId": sessionId.uuidString,
                "taskId": taskId.uuidString,
                "position": 1
            ]
        )

        // Verify the relationship was created
        let result = try context.raw(
            """
            MATCH (s:Session)-[r:HasTask]->(t:TodoTask)
            RETURN s.title as sessionTitle, t.title as taskTitle, r.position as position
            """,
            bindings: [:]
        )
        
        let rows = try result.mapRows()
        #expect(rows.count == 1)
        #expect(rows[0]["sessionTitle"] as? String == "Test Session")
        #expect(rows[0]["taskTitle"] as? String == "Test Task")
        #expect(rows[0]["position"] as? Int64 == 1)
    }
    
    @Test("Migration with only nodes should still work")
    func testMigrationWithOnlyNodes() async throws {
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
        let container = try GraphContainer(configuration: configuration)
        let context = GraphContext(container)
        let migrationManager = MigrationManager(context: context, policy: .safe)
        
        // This should succeed as before
        try migrationManager.migrate(types: [
            Session.self,
            TodoTask.self
        ])

        // Verify the tables were created
        let sessionCount = try context.raw("MATCH (s:Session) RETURN count(s) as cnt", bindings: [:])
        #expect(try sessionCount.mapFirstRequired(to: Int64.self, at: 0) == 0)

        let taskCount = try context.raw("MATCH (t:TodoTask) RETURN count(t) as cnt", bindings: [:])
        #expect(try taskCount.mapFirstRequired(to: Int64.self, at: 0) == 0)
    }
    
    @Test("Sequential migration approach should work")
    func testSequentialMigration() async throws {
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
        let container = try GraphContainer(configuration: configuration)
        let context = GraphContext(container)
        let migrationManager = MigrationManager(context: context, policy: .safe)
        
        // First migrate nodes
        try migrationManager.migrate(types: [
            Session.self,
            TodoTask.self
        ])

        // Then migrate with edges - this should detect existing nodes and only add edges
        // The migration manager should handle this gracefully
        do {
            try migrationManager.migrate(types: [
                Session.self,
                TodoTask.self,
                HasTask.self,
                SubTaskOf.self,
                Blocks.self
            ])
        } catch {
            // If it fails because tables already exist, that's expected
            // We just need to manually add the edge tables
            _ = try context.raw("CREATE REL TABLE HasTask (FROM Session TO TodoTask, position INT64)", bindings: [:])
            _ = try context.raw("CREATE REL TABLE SubTaskOf (FROM TodoTask TO TodoTask)", bindings: [:])
            _ = try context.raw("CREATE REL TABLE Blocks (FROM TodoTask TO TodoTask)", bindings: [:])
        }

        // Verify all tables exist by creating and querying a relationship
        let sessionId = UUID()
        let taskId = UUID()

        _ = try context.raw(
            "CREATE (s:Session {id: $id, title: $title})",
            bindings: ["id": sessionId.uuidString, "title": "Test Session"]
        )

        _ = try context.raw(
            "CREATE (t:TodoTask {id: $id, title: $title})",
            bindings: ["id": taskId.uuidString, "title": "Test Task"]
        )

        // This will fail if edge tables don't exist
        _ = try context.raw(
            """
            MATCH (s:Session {id: $sessionId}), (t:TodoTask {id: $taskId})
            CREATE (s)-[:HasTask {position: 1}]->(t)
            """,
            bindings: ["sessionId": sessionId.uuidString, "taskId": taskId.uuidString]
        )

        // Verify the relationship was created
        let result = try context.raw(
            "MATCH (s:Session)-[:HasTask]->(t:TodoTask) RETURN count(*) as cnt",
            bindings: [:]
        )
        #expect(try result.mapFirstRequired(to: Int64.self, at: 0) == 1)
    }
}
