import Testing
import KuzuSwiftExtension
@testable import KuzuSwiftExtension
import struct Foundation.UUID
import struct Foundation.Date

// Test models to reproduce the reported issue
@GraphNode
struct Session {
    @ID var id: UUID = UUID()
    var title: String
    var createdAt: Date = Date()
}

@GraphNode  
struct TodoTask {
    @ID var id: UUID = UUID()
    var sessionId: UUID
    var description: String
    var completed: Bool = false
}

@Suite("Schema Duplication Fix Tests")
struct SchemaDuplicationFixTests {
    
    @Test("No duplicate table error when creating schema multiple times")
    func testNoDuplicateTableError() throws {
        // Create test context with automatic migration
        let container = try GraphContainer(
            for: Session.self, TodoTask.self,
            configuration: GraphConfiguration(
                databasePath: ":memory:",
                migrationMode: .automatic
            )
        )
        let context = GraphContext(container)
        
        // Try to create schemas again - should not error
        try context.createSchemaIfNotExists(for: Session.self)
        try context.createSchemaIfNotExists(for: TodoTask.self)
        
        // Verify we can save data
        let session = Session(title: "Test Session")
        context.insert(session)

        let task = TodoTask(sessionId: session.id, description: "Test TodoTask")
        context.insert(task)

        try context.save()
        
        // Verify data was saved
        let sessions = try context.fetch(Session.self)
        #expect(sessions.count == 1)

        let tasks = try context.fetch(TodoTask.self)
        #expect(tasks.count == 1)
        
    }
    
    @Test("Multiple test contexts are isolated")
    func testMultipleContextsIsolation() throws {
        // Simulate the user's scenario with SessionManager and TodoTaskManager
        // Each using their own context but same models
        
        // First context (SessionManager.shared)
        let sessionContainer = try GraphContainer(
            for: Session.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let sessionContext = GraphContext(sessionContainer)

        // Second context (TodoTaskManager.shared)
        let taskContainer = try GraphContainer(
            for: TodoTask.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let taskContext = GraphContext(taskContainer)
        
        // Both should work without conflicts
        let session = Session(title: "Session in first context")
        sessionContext.insert(session)
        try sessionContext.save()

        let task = TodoTask(sessionId: session.id, description: "TodoTask in second context")
        taskContext.insert(task)
        try taskContext.save()

        // Verify isolation
        let sessionsInFirst = try sessionContext.fetch(Session.self)
        #expect(sessionsInFirst.count == 1)

        let tasksInSecond = try taskContext.fetch(TodoTask.self)
        #expect(tasksInSecond.count == 1)
    }
    
    @Test("SwiftData-style API works correctly")
    func testSwiftDataStyleAPI() throws {
        // Use the new SwiftData-style container API
        let container = try GraphContainer(
            for: Session.self, TodoTask.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)
        
        // Schema should be automatically created
        let session = Session(title: "SwiftData Style")
        context.insert(session)
        try context.save()
        
        // Fetch should work
        let sessions = try context.fetch(Session.self)
        #expect(sessions.count == 1)
        #expect(sessions.first?.title == "SwiftData Style")
        
    }
    
    @Test("Automatic migration mode skips existing tables")
    func testAutomaticMigrationSkipsExisting() throws {
        let container = try GraphContainer(
            for: Session.self,
            configuration: GraphConfiguration(
                databasePath: ":memory:",
                migrationMode: .automatic
            )
        )
        let context = GraphContext(container)
        
        // Save initial data
        let session1 = Session(title: "First")
        context.insert(session1)
        try context.save()
        
        // Try to create schema again with automatic mode
        try context.createSchemasIfNotExist(for: [Session.self])
        
        // Original data should still exist
        let sessions = try context.fetch(Session.self)
        #expect(sessions.count == 1)

        // Can still add more data
        let session2 = Session(title: "Second")
        context.insert(session2)
        try context.save()

        let allSessions = try context.fetch(Session.self)
        #expect(allSessions.count == 2)
        
    }
    
    @Test("MigrationManager safely handles existing tables")
    func testMigrationManagerSafeTableCreation() throws {
        let container = try GraphContainer(
            configuration: GraphConfiguration(
                databasePath: ":memory:",
                migrationMode: .none  // Manual control
            )
        )
        let context = GraphContext(container)
        
        // Create schema manually
        try context.createSchema(for: Session.self)
        
        // Use MigrationManager to migrate - should handle existing table
        let migrationManager = MigrationManager(
            context: context,
            policy: .safe
        )
        
        // This should not error even though Session already exists
        try migrationManager.migrateIfNeeded(types: [Session.self, TodoTask.self])
        
        // Verify both tables work
        let session = Session(title: "Test")
        context.insert(session)
        try context.save()

        let task = TodoTask(sessionId: session.id, description: "Test TodoTask")
        context.insert(task)
        try context.save()
        
    }
    
    @Test("Test context always uses automatic migration")
    func testTestContextAutomaticMigration() throws {
        // In-memory containers should always use automatic migration
        let container1 = try GraphContainer(
            for: Session.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context1 = GraphContext(container1)

        // Create same models in another test context - should not conflict
        let container2 = try GraphContainer(
            for: Session.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context2 = GraphContext(container2)
        
        // Both contexts should work independently
        let session1 = Session(title: "Context 1")
        context1.insert(session1)
        try context1.save()

        let session2 = Session(title: "Context 2")
        context2.insert(session2)
        try context2.save()

        // Verify isolation
        let sessions1 = try context1.fetch(Session.self)
        let sessions2 = try context2.fetch(Session.self)

        #expect(sessions1.count == 1)
        #expect(sessions2.count == 1)
        #expect(sessions1.first?.title == "Context 1")
        #expect(sessions2.first?.title == "Context 2")
    }
}

// Extension removed - using actual implementation from GraphModel.swift