import XCTest
import Foundation
import KuzuSwiftExtension
import TodoCore

final class TodoCLIIntegrationTests: XCTestCase {
    
    var context: GraphContext!
    
    override func setUp() async throws {
        // Use in-memory database for tests
        let config = GraphConfiguration(
            path: ":memory:",
            options: GraphConfiguration.Options()
        )
        
        context = try await GraphContext(configuration: config)
        
        // Create schema
        try await context.createSchema(for: Todo.self)
    }
    
    override func tearDown() async throws {
        await context.close()
        context = nil
    }
    
    func testAddAndFetchTodo() async throws {
        // Add a todo
        let todo = Todo(title: "Test Todo")
        let saved = try await context.save(todo)
        
        XCTAssertEqual(saved.title, "Test Todo")
        XCTAssertFalse(saved.done)
        
        // Fetch all todos
        let todos = try await context.fetch(Todo.self)
        XCTAssertEqual(todos.count, 1)
        XCTAssertEqual(todos.first?.id, saved.id)
    }
    
    func testToggleTodoCompletion() async throws {
        // Create a todo
        let todo = Todo(title: "Toggle Test", done: false)
        let saved = try await context.save(todo)
        XCTAssertFalse(saved.done)
        
        // Toggle completion
        var updated = saved
        updated.done = true
        let toggled = try await context.save(updated)
        
        XCTAssertTrue(toggled.done)
        XCTAssertEqual(toggled.id, saved.id)
        
        // Verify in database
        let fetched = try await context.fetch(Todo.self)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertTrue(fetched.first?.done ?? false)
    }
    
    func testDeleteTodo() async throws {
        // Create multiple todos
        let todo1 = Todo(title: "Todo 1")
        let todo2 = Todo(title: "Todo 2")
        let todo3 = Todo(title: "Todo 3")
        
        _ = try await context.save(todo1)
        let saved2 = try await context.save(todo2)
        _ = try await context.save(todo3)
        
        // Verify all exist
        var todos = try await context.fetch(Todo.self)
        XCTAssertEqual(todos.count, 3)
        
        // Delete one
        try await context.delete(saved2)
        
        // Verify deletion
        todos = try await context.fetch(Todo.self)
        XCTAssertEqual(todos.count, 2)
        XCTAssertFalse(todos.contains { $0.id == saved2.id })
    }
    
    func testCountTodos() async throws {
        // Create todos with different states
        let todo1 = Todo(title: "Pending 1", done: false)
        let todo2 = Todo(title: "Completed 1", done: true)
        let todo3 = Todo(title: "Pending 2", done: false)
        let todo4 = Todo(title: "Completed 2", done: true)
        let todo5 = Todo(title: "Completed 3", done: true)
        
        _ = try await context.save(todo1)
        _ = try await context.save(todo2)
        _ = try await context.save(todo3)
        _ = try await context.save(todo4)
        _ = try await context.save(todo5)
        
        // Test counts
        let total = try await context.count(Todo.self)
        XCTAssertEqual(total, 5)
        
        let completed = try await context.count(Todo.self, where: "done", equals: true)
        XCTAssertEqual(completed, 3)
        
        let pending = try await context.count(Todo.self, where: "done", equals: false)
        XCTAssertEqual(pending, 2)
    }
    
    func testFetchWithPredicate() async throws {
        // Create todos
        let todo1 = Todo(title: "Buy groceries", done: false)
        let todo2 = Todo(title: "Write report", done: true)
        let todo3 = Todo(title: "Call mom", done: false)
        let todo4 = Todo(title: "Finish project", done: true)
        
        _ = try await context.save(todo1)
        _ = try await context.save(todo2)
        _ = try await context.save(todo3)
        _ = try await context.save(todo4)
        
        // Fetch only completed todos
        let completedTodos = try await context.fetch(Todo.self, where: "done", equals: true)
        XCTAssertEqual(completedTodos.count, 2)
        XCTAssertTrue(completedTodos.allSatisfy { $0.done })
        
        // Fetch only pending todos
        let pendingTodos = try await context.fetch(Todo.self, where: "done", equals: false)
        XCTAssertEqual(pendingTodos.count, 2)
        XCTAssertTrue(pendingTodos.allSatisfy { !$0.done })
    }
    
    func testPersistence() async throws {
        // This test verifies that data persists across context recreations
        // Note: This only works with file-based database, not in-memory
        // For demonstration purposes with in-memory database
        
        // Create and save todos
        let todo1 = Todo(title: "Persistent Todo 1")
        let todo2 = Todo(title: "Persistent Todo 2")
        
        let saved1 = try await context.save(todo1)
        let saved2 = try await context.save(todo2)
        
        // Fetch to verify
        let todos = try await context.fetch(Todo.self)
        XCTAssertEqual(todos.count, 2)
        
        // IDs should be preserved
        XCTAssertTrue(todos.contains { $0.id == saved1.id })
        XCTAssertTrue(todos.contains { $0.id == saved2.id })
    }
    
    func testEmptyDatabase() async throws {
        // Test operations on empty database
        let todos = try await context.fetch(Todo.self)
        XCTAssertEqual(todos.count, 0)
        
        let count = try await context.count(Todo.self)
        XCTAssertEqual(count, 0)
        
        let completedCount = try await context.count(Todo.self, where: "done", equals: true)
        XCTAssertEqual(completedCount, 0)
    }
    
    func testLargeBatchOperations() async throws {
        // Test with larger number of todos
        let todoCount = 100
        
        // Create many todos
        for i in 1...todoCount {
            let todo = Todo(
                title: "Todo #\(i)",
                done: i % 3 == 0 // Every third todo is completed
            )
            _ = try await context.save(todo)
        }
        
        // Verify counts
        let total = try await context.count(Todo.self)
        XCTAssertEqual(total, todoCount)
        
        let completed = try await context.count(Todo.self, where: "done", equals: true)
        XCTAssertEqual(completed, todoCount / 3)
        
        // Fetch all and verify
        let allTodos = try await context.fetch(Todo.self)
        XCTAssertEqual(allTodos.count, todoCount)
    }
}