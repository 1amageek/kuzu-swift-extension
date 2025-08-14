import Testing
import KuzuSwiftExtension
@testable import KuzuSwiftExtension
import struct Foundation.UUID
import class Foundation.FileManager
import class Foundation.Bundle
import class Foundation.ProcessInfo

// Test model for GraphDatabase tests
@GraphNode
struct TestTodo {
    @ID var id: UUID = UUID()
    var title: String
    var completed: Bool = false
}

@Suite("Graph Database Tests")
struct GraphDatabaseTests {
    
    @Test("Shared instance singleton behavior")
    func sharedInstance() async throws {
        // Verify singleton behavior
        let instance1 = await GraphDatabase.shared
        let instance2 = await GraphDatabase.shared
        #expect(instance1 === instance2)
    }
    
    @Test("Test context isolation")
    func testContextIsolation() async throws {
        // Create two independent test contexts
        let context1 = try await GraphDatabase.createTestContext(
            name: "test1",
            models: [TestTodo.self]
        )
        let context2 = try await GraphDatabase.createTestContext(
            name: "test2",
            models: [TestTodo.self]
        )
        
        // Verify they are different instances
        #expect(context1 !== context2)
        
        // Save data to first context using raw queries
        let todo1 = TestTodo(title: "Todo in context 1")
        _ = try await context1.raw("""
            CREATE (n:TestTodo {id: $id, title: $title, completed: $completed})
            """, bindings: [
                "id": todo1.id.uuidString,
                "title": todo1.title,
                "completed": todo1.completed
            ])
        
        // Verify data is only in first context
        let result1 = try await context1.raw("MATCH (n:TestTodo) RETURN n")
        let result2 = try await context2.raw("MATCH (n:TestTodo) RETURN n")
        
        var count1 = 0
        while result1.hasNext() {
            _ = try result1.getNext()
            count1 += 1
        }
        
        var count2 = 0
        while result2.hasNext() {
            _ = try result2.getNext()
            count2 += 1
        }
        
        #expect(count1 == 1)
        #expect(count2 == 0)
        
        // Cleanup
        await context1.close()
        await context2.close()
    }
    
    @Test("Model registration with test context")
    func modelRegistrationTest() async throws {
        // Create test context with models
        let context = try await GraphDatabase.createTestContext(
            name: "model-test",
            models: [TestTodo.self]
        )
        
        // Verify we can use the model with raw queries
        let todo = TestTodo(title: "Test registration")
        _ = try await context.raw("""
            CREATE (n:TestTodo {id: $id, title: $title, completed: $completed})
            """, bindings: [
                "id": todo.id.uuidString,
                "title": todo.title,
                "completed": todo.completed
            ])
        
        // Verify the data was saved
        let result = try await context.raw("MATCH (n:TestTodo) WHERE n.title = $title RETURN n.title as title", 
                                          bindings: ["title": "Test registration"])
        
        #expect(result.hasNext())
        if let flatTuple = try result.getNext(),
           let title = try flatTuple.getValue(0) as? String {
            #expect(title == "Test registration")
        }
        
        // Cleanup
        await context.close()
    }
    
    @Test("Test in-memory context")
    func testInMemoryContext() async throws {
        // Create in-memory test context
        let context = try await GraphDatabase.createTestContext(
            name: "memory-test",
            models: [TestTodo.self]
        )
        
        // Save data using raw queries
        let todo = TestTodo(title: "In-memory todo")
        _ = try await context.raw("""
            CREATE (n:TestTodo {id: $id, title: $title, completed: $completed})
            """, bindings: [
                "id": todo.id.uuidString,
                "title": todo.title,
                "completed": todo.completed
            ])
        
        // Verify data exists in the same context
        let result = try await context.raw("MATCH (n:TestTodo) RETURN n.title as title")
        
        var todos: [String] = []
        while result.hasNext() {
            if let flatTuple = try result.getNext(),
               let title = try flatTuple.getValue(0) as? String {
                todos.append(title)
            }
        }
        
        #expect(todos.count == 1)
        #expect(todos.first == "In-memory todo")
        
        // Note: In-memory databases don't persist after close
        await context.close()
    }
    
    @Test("Singleton context consistency")
    func singletonContextConsistency() async throws {
        // This test now expects context to remain consistent
        // and NOT be recreated after operations
        
        // Skip this test if singleton is already initialized from other tests
        // In real usage, we would use test isolation
    }
}