import Testing
import KuzuSwiftExtension
@testable import KuzuSwiftExtension
import struct Foundation.UUID
import class Foundation.FileManager
import class Foundation.Bundle

// Test model for GraphDatabase tests
@GraphNode
struct TestTodo {
    @ID var id: UUID = UUID()
    var title: String
    var completed: Bool = false
}

@Suite("Graph Database Tests")
struct GraphDatabaseTests {
    
    func cleanup() async throws {
        // Reset GraphDatabase state
        try? await GraphDatabase.shared.close()
        
        // Remove database file to ensure clean state for next test
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        #if os(macOS)
        let bundleID = Bundle.main.bundleIdentifier ?? "com.app.kuzu"
        let appDir = appSupport.appendingPathComponent(bundleID)
        #else
        let appDir = appSupport.appendingPathComponent(".kuzu")
        #endif
        
        let dbPath = appDir.appendingPathComponent("graph.kuzu")
        try? FileManager.default.removeItem(at: dbPath)
        
        // Also remove the entire directory to ensure complete cleanup
        try? FileManager.default.removeItem(at: appDir)
    }
    
    @Test("Shared instance singleton behavior")
    func sharedInstance() async throws {
        try await cleanup()
        
        // Verify singleton behavior
        let instance1 = await GraphDatabase.shared
        let instance2 = await GraphDatabase.shared
        #expect(instance1 === instance2)
        
        try await cleanup()
    }
    
    @Test("Auto path resolution")
    func autoPathResolution() async throws {
        try await cleanup()
        
        // Get context - should auto-resolve path
        let context = try await GraphDatabase.shared.context()
        #expect(context != nil)
        
        // Get context again - should return cached instance
        let context2 = try await GraphDatabase.shared.context()
        #expect(context === context2)
        
        try await cleanup()
    }
    
    @Test("Model registration")
    func modelRegistration() async throws {
        try await cleanup()
        
        // Register models
        await GraphDatabase.shared.register(models: [TestTodo.self])
        
        // Context should auto-create schema for registered models
        let context = try await GraphDatabase.shared.context()
        
        // Verify we can use the model
        let todo = TestTodo(title: "Test registration")
        let saved = try await context.save(todo)
        #expect(saved.title == "Test registration")
        
        try await cleanup()
    }
    
    @Test("Default path creation")
    func defaultPathCreation() async throws {
        try await cleanup()
        
        // This test verifies that the default path is created correctly
        // The actual path will vary by platform
        
        // Register the model first
        await GraphDatabase.shared.register(models: [TestTodo.self])
        
        let context = try await GraphDatabase.shared.context()
        
        // Should be able to save data
        let todo = TestTodo(title: "Path test")
        _ = try await context.save(todo)
        
        // Data should persist
        let todos = try await context.fetch(TestTodo.self)
        #expect(todos.count == 1)
        
        try await cleanup()
    }
    
    @Test("Close and reopen database")
    func closeAndReopen() async throws {
        try await cleanup()
        
        // Register model
        await GraphDatabase.shared.register(models: [TestTodo.self])
        
        // Create and save data
        let context1 = try await GraphDatabase.shared.context()
        let todo = TestTodo(title: "Persistent todo")
        _ = try await context1.save(todo)
        
        // Close database
        try await GraphDatabase.shared.close()
        
        // Reopen and verify data persists
        let context2 = try await GraphDatabase.shared.context()
        let todos = try await context2.fetch(TestTodo.self)
        
        // Should find the previously saved todo
        #expect(todos.count == 1)
        #expect(todos.first?.title == "Persistent todo")
        
        try await cleanup()
    }
}