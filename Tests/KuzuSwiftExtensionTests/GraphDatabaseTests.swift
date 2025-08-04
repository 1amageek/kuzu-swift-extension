import XCTest
import KuzuSwiftExtension
@testable import KuzuSwiftExtension

// Test model for GraphDatabase tests
@GraphNode
struct TestTodo {
    @ID var id: UUID = UUID()
    var title: String
    var completed: Bool = false
}

final class GraphDatabaseTests: XCTestCase {
    
    override func tearDown() async throws {
        // Reset GraphDatabase state
        try? await GraphDatabase.shared.close()
        try await super.tearDown()
    }
    
    func testSharedInstance() async throws {
        // Verify singleton behavior
        let instance1 = await GraphDatabase.shared
        let instance2 = await GraphDatabase.shared
        XCTAssertTrue(instance1 === instance2)
    }
    
    func testAutoPathResolution() async throws {
        // Get context - should auto-resolve path
        let context = try await GraphDatabase.shared.context()
        XCTAssertNotNil(context)
        
        // Get context again - should return cached instance
        let context2 = try await GraphDatabase.shared.context()
        XCTAssertTrue(context === context2)
    }
    
    func testModelRegistration() async throws {
        // Register models
        await GraphDatabase.shared.register(models: [TestTodo.self])
        
        // Context should auto-create schema for registered models
        let context = try await GraphDatabase.shared.context()
        
        // Verify we can use the model
        let todo = TestTodo(title: "Test registration")
        let saved = try await context.save(todo)
        XCTAssertEqual(saved.title, "Test registration")
    }
    
    func testDefaultPathCreation() async throws {
        // This test verifies that the default path is created correctly
        // The actual path will vary by platform
        let context = try await GraphDatabase.shared.context()
        
        // Should be able to save data
        let todo = TestTodo(title: "Path test")
        _ = try await context.save(todo)
        
        // Data should persist
        let todos = try await context.fetch(TestTodo.self)
        XCTAssertEqual(todos.count, 1)
    }
    
    func testCloseAndReopen() async throws {
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
        XCTAssertEqual(todos.count, 1)
        XCTAssertEqual(todos.first?.title, "Persistent todo")
    }
}