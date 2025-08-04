import Foundation
import KuzuSwiftExtension
import TodoCore

// シンプルなコマンドラインTodoアプリ
@main
struct TodoCLI {
    static func main() async {
        do {
            // グラフデータベースを初期化（自動でパスが設定される）
            print("📊 Initializing graph database...")
            GraphDatabase.shared.register(models: [Todo.self])
            let graph = try await GraphDatabase.shared.context()
            
            print("✅ Database initialized successfully!\n")
            
            // メインループ
            var running = true
            while running {
                print("""
                ====================================
                Todo Graph Database Example
                ====================================
                1. Add new todo
                2. List all todos
                3. Toggle todo completion
                4. Delete todo
                5. Count todos
                6. Exit
                
                Enter choice (1-6): 
                """, terminator: "")
                
                guard let input = readLine(), let choice = Int(input) else {
                    print("Invalid input. Please try again.\n")
                    continue
                }
                
                do {
                    switch choice {
                    case 1:
                        try await addTodo(graph: graph)
                    case 2:
                        try await listTodos(graph: graph)
                    case 3:
                        try await toggleTodo(graph: graph)
                    case 4:
                        try await deleteTodo(graph: graph)
                    case 5:
                        try await countTodos(graph: graph)
                    case 6:
                        running = false
                        print("👋 Goodbye!")
                    default:
                        print("Invalid choice. Please try again.\n")
                    }
                } catch {
                    print("❌ Error: \(error)\n")
                }
            }
            
        } catch {
            print("❌ Failed to initialize database: \(error)")
        }
    }
    
    static func addTodo(graph: GraphContext) async throws {
        print("Enter todo title: ", terminator: "")
        guard let title = readLine(), !title.isEmpty else {
            print("Title cannot be empty.\n")
            return
        }
        
        let todo = Todo(title: title)
        let saved = try await graph.save(todo)
        print("✅ Added: \(saved.title) (ID: \(saved.id))\n")
    }
    
    static func listTodos(graph: GraphContext) async throws {
        let todos = try await graph.fetch(Todo.self)
        
        if todos.isEmpty {
            print("📭 No todos found.\n")
        } else {
            print("\n📋 Your Todos:")
            print("----------------------------------------")
            for (index, todo) in todos.enumerated() {
                let status = todo.done ? "✅" : "⬜"
                print("\(index + 1). \(status) \(todo.title)")
                print("   Created: \(formatDate(todo.createdAt))")
            }
            print("----------------------------------------\n")
        }
    }
    
    static func toggleTodo(graph: GraphContext) async throws {
        let todos = try await graph.fetch(Todo.self)
        
        if todos.isEmpty {
            print("📭 No todos to toggle.\n")
            return
        }
        
        // Show todos
        for (index, todo) in todos.enumerated() {
            let status = todo.done ? "✅" : "⬜"
            print("\(index + 1). \(status) \(todo.title)")
        }
        
        print("\nEnter todo number to toggle: ", terminator: "")
        guard let input = readLine(), 
              let index = Int(input),
              index > 0 && index <= todos.count else {
            print("Invalid selection.\n")
            return
        }
        
        var todo = todos[index - 1]
        todo.done.toggle()
        let updated = try await graph.save(todo)
        
        let newStatus = updated.done ? "completed" : "incomplete"
        print("✅ Marked '\(updated.title)' as \(newStatus)\n")
    }
    
    static func deleteTodo(graph: GraphContext) async throws {
        let todos = try await graph.fetch(Todo.self)
        
        if todos.isEmpty {
            print("📭 No todos to delete.\n")
            return
        }
        
        // Show todos
        for (index, todo) in todos.enumerated() {
            let status = todo.done ? "✅" : "⬜"
            print("\(index + 1). \(status) \(todo.title)")
        }
        
        print("\nEnter todo number to delete: ", terminator: "")
        guard let input = readLine(), 
              let index = Int(input),
              index > 0 && index <= todos.count else {
            print("Invalid selection.\n")
            return
        }
        
        let todo = todos[index - 1]
        try await graph.delete(todo)
        print("🗑️ Deleted: \(todo.title)\n")
    }
    
    static func countTodos(graph: GraphContext) async throws {
        let total = try await graph.count(Todo.self)
        let completed = try await graph.count(Todo.self) { $0.done == true }
        let pending = total - completed
        
        print("""
        
        📊 Todo Statistics:
        ----------------------------------------
        Total todos: \(total)
        Completed: \(completed)
        Pending: \(pending)
        ----------------------------------------
        
        """)
    }
    
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}