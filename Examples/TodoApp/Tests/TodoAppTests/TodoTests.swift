import XCTest
import Foundation
@testable import TodoCore

final class TodoTests: XCTestCase {
    
    func testTodoInitialization() {
        // Test with custom values
        let id = UUID()
        let title = "Test Todo"
        let done = true
        let createdAt = Date()
        
        let todo = Todo(
            id: id,
            title: title,
            done: done,
            createdAt: createdAt
        )
        
        XCTAssertEqual(todo.id, id)
        XCTAssertEqual(todo.title, title)
        XCTAssertEqual(todo.done, done)
        XCTAssertEqual(todo.createdAt, createdAt)
    }
    
    func testTodoDefaultValues() {
        // Test with defaults
        let todo = Todo(title: "Default Test")
        
        XCTAssertNotNil(todo.id)
        XCTAssertEqual(todo.title, "Default Test")
        XCTAssertFalse(todo.done) // Should default to false
        XCTAssertNotNil(todo.createdAt)
        
        // Verify createdAt is recent (within last second)
        let timeDifference = Date().timeIntervalSince(todo.createdAt)
        XCTAssertLessThan(timeDifference, 1.0)
    }
    
    func testTodoCodable() throws {
        // Test encoding and decoding
        let original = Todo(
            title: "Codable Test",
            done: true
        )
        
        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Todo.self, from: data)
        
        // Verify
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.done, original.done)
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, 
                      original.createdAt.timeIntervalSince1970, 
                      accuracy: 0.001)
    }
    
    func testTodoEquality() {
        let id = UUID()
        let createdAt = Date()
        
        let todo1 = Todo(
            id: id,
            title: "Test",
            done: false,
            createdAt: createdAt
        )
        
        let todo2 = Todo(
            id: id,
            title: "Test",
            done: false,
            createdAt: createdAt
        )
        
        let todo3 = Todo(
            id: UUID(), // Different ID
            title: "Test",
            done: false,
            createdAt: createdAt
        )
        
        // Todos with same ID should be considered equal
        XCTAssertEqual(todo1.id, todo2.id)
        XCTAssertNotEqual(todo1.id, todo3.id)
    }
    
    func testTodoPropertyModification() {
        var todo = Todo(title: "Original Title")
        
        // Verify initial state
        XCTAssertEqual(todo.title, "Original Title")
        XCTAssertFalse(todo.done)
        
        // Modify properties
        todo.title = "Updated Title"
        todo.done = true
        
        // Verify changes
        XCTAssertEqual(todo.title, "Updated Title")
        XCTAssertTrue(todo.done)
        
        // ID and createdAt should remain unchanged
        let originalId = todo.id
        let originalCreatedAt = todo.createdAt
        
        todo.title = "Another Update"
        
        XCTAssertEqual(todo.id, originalId)
        XCTAssertEqual(todo.createdAt, originalCreatedAt)
    }
}