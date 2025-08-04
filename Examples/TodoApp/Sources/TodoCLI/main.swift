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
                6. Search todos
                7. Bulk operations
                8. Export/Import
                9. Exit
                
                Enter choice (1-9): 
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
                        try await searchTodos(graph: graph)
                    case 7:
                        try await bulkOperations(graph: graph)
                    case 8:
                        try await exportImport(graph: graph)
                    case 9:
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
        print("""
        Sort options:
        1. By creation date (newest first)
        2. By creation date (oldest first)
        3. By status (pending first)
        4. By status (completed first)
        5. No sorting
        
        Choose sorting option (1-5): 
        """, terminator: "")
        
        let sortOption = readLine().flatMap(Int.init) ?? 5
        
        let query: String
        switch sortOption {
        case 1:
            query = "MATCH (t:Todo) RETURN t ORDER BY t.createdAt DESC"
        case 2:
            query = "MATCH (t:Todo) RETURN t ORDER BY t.createdAt ASC"
        case 3:
            query = "MATCH (t:Todo) RETURN t ORDER BY t.done ASC, t.createdAt DESC"
        case 4:
            query = "MATCH (t:Todo) RETURN t ORDER BY t.done DESC, t.createdAt DESC"
        default:
            query = "MATCH (t:Todo) RETURN t"
        }
        
        let result = try await graph.raw(query)
        let todos = try result.decode([Todo].self)
        
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
        let completed = try await graph.count(Todo.self, where: "done", equals: true)
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
    
    static func searchTodos(graph: GraphContext) async throws {
        print("Enter search term: ", terminator: "")
        guard let searchTerm = readLine(), !searchTerm.isEmpty else {
            print("Search term cannot be empty.\n")
            return
        }
        
        // Use raw query for CONTAINS search
        let query = """
            MATCH (t:Todo)
            WHERE t.title CONTAINS $searchTerm
            RETURN t
            """
        
        let result = try await graph.raw(query, bindings: ["searchTerm": searchTerm])
        let todos = try result.decode([Todo].self)
        
        if todos.isEmpty {
            print("🔍 No todos found matching '\(searchTerm)'.\n")
        } else {
            print("\n🔍 Search Results for '\(searchTerm)':")
            print("----------------------------------------")
            for (index, todo) in todos.enumerated() {
                let status = todo.done ? "✅" : "⬜"
                print("\(index + 1). \(status) \(todo.title)")
                print("   Created: \(formatDate(todo.createdAt))")
            }
            print("----------------------------------------\n")
        }
    }
    
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    static func bulkOperations(graph: GraphContext) async throws {
        print("""
        
        Bulk Operations:
        1. Mark all todos as completed
        2. Mark all todos as pending
        3. Delete all completed todos
        4. Delete all todos (clear database)
        5. Cancel
        
        Choose operation (1-5): 
        """, terminator: "")
        
        guard let input = readLine(), let choice = Int(input) else {
            print("Invalid input.\n")
            return
        }
        
        switch choice {
        case 1:
            // Mark all as completed
            print("⚠️  Mark ALL todos as completed? (y/n): ", terminator: "")
            guard readLine()?.lowercased() == "y" else {
                print("Cancelled.\n")
                return
            }
            
            let query = "MATCH (t:Todo) SET t.done = true RETURN count(t)"
            let result = try await graph.raw(query)
            if result.hasNext() {
                let tuple = try result.getNext()
                if let count = try? tuple.getValue(at: 0) as? Int64 {
                    print("✅ Marked \(count) todos as completed.\n")
                }
            }
            
        case 2:
            // Mark all as pending
            print("⚠️  Mark ALL todos as pending? (y/n): ", terminator: "")
            guard readLine()?.lowercased() == "y" else {
                print("Cancelled.\n")
                return
            }
            
            let query = "MATCH (t:Todo) SET t.done = false RETURN count(t)"
            let result = try await graph.raw(query)
            if result.hasNext() {
                let tuple = try result.getNext()
                if let count = try? tuple.getValue(at: 0) as? Int64 {
                    print("⬜ Marked \(count) todos as pending.\n")
                }
            }
            
        case 3:
            // Delete all completed
            print("⚠️  Delete ALL completed todos? (y/n): ", terminator: "")
            guard readLine()?.lowercased() == "y" else {
                print("Cancelled.\n")
                return
            }
            
            let query = "MATCH (t:Todo {done: true}) DELETE t RETURN count(*)"
            let result = try await graph.raw(query)
            if result.hasNext() {
                let tuple = try result.getNext()
                if let count = try? tuple.getValue(at: 0) as? Int64 {
                    print("🗑️ Deleted \(count) completed todos.\n")
                }
            }
            
        case 4:
            // Delete all
            print("⚠️  DELETE ALL TODOS? This cannot be undone! (type 'DELETE ALL' to confirm): ", terminator: "")
            guard readLine() == "DELETE ALL" else {
                print("Cancelled.\n")
                return
            }
            
            let query = "MATCH (t:Todo) DELETE t RETURN count(*)"
            let result = try await graph.raw(query)
            if result.hasNext() {
                let tuple = try result.getNext()
                if let count = try? tuple.getValue(at: 0) as? Int64 {
                    print("🗑️ Deleted \(count) todos. Database is now empty.\n")
                }
            }
            
        case 5:
            print("Cancelled.\n")
            
        default:
            print("Invalid choice.\n")
        }
    }
    
    static func exportImport(graph: GraphContext) async throws {
        print("""
        
        Export/Import Options:
        1. Export todos to JSON file
        2. Import todos from JSON file
        3. Cancel
        
        Choose option (1-3): 
        """, terminator: "")
        
        guard let input = readLine(), let choice = Int(input) else {
            print("Invalid input.\n")
            return
        }
        
        switch choice {
        case 1:
            // Export
            try await exportTodos(graph: graph)
            
        case 2:
            // Import
            try await importTodos(graph: graph)
            
        case 3:
            print("Cancelled.\n")
            
        default:
            print("Invalid choice.\n")
        }
    }
    
    static func exportTodos(graph: GraphContext) async throws {
        let todos = try await graph.fetch(Todo.self)
        
        if todos.isEmpty {
            print("📭 No todos to export.\n")
            return
        }
        
        print("Enter filename for export (default: todos_export.json): ", terminator: "")
        let filename = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let exportFilename = filename.isEmpty ? "todos_export.json" : filename
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(todos)
        let url = URL(fileURLWithPath: exportFilename)
        try data.write(to: url)
        
        print("✅ Exported \(todos.count) todos to '\(exportFilename)'.\n")
    }
    
    static func importTodos(graph: GraphContext) async throws {
        print("Enter filename to import (default: todos_export.json): ", terminator: "")
        let filename = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let importFilename = filename.isEmpty ? "todos_export.json" : filename
        
        let url = URL(fileURLWithPath: importFilename)
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ File '\(importFilename)' not found.\n")
            return
        }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let todos = try decoder.decode([Todo].self, from: data)
        
        if todos.isEmpty {
            print("📭 No todos found in file.\n")
            return
        }
        
        print("Found \(todos.count) todos. Import options:")
        print("1. Add to existing todos")
        print("2. Replace all existing todos")
        print("3. Cancel")
        print("\nChoose option (1-3): ", terminator: "")
        
        guard let input = readLine(), let choice = Int(input) else {
            print("Invalid input.\n")
            return
        }
        
        switch choice {
        case 1:
            // Add to existing
            var imported = 0
            for todo in todos {
                _ = try await graph.save(todo)
                imported += 1
            }
            print("✅ Imported \(imported) todos.\n")
            
        case 2:
            // Replace all
            print("⚠️  This will DELETE all existing todos. Continue? (y/n): ", terminator: "")
            guard readLine()?.lowercased() == "y" else {
                print("Cancelled.\n")
                return
            }
            
            // Delete all existing
            _ = try await graph.raw("MATCH (t:Todo) DELETE t")
            
            // Import new
            var imported = 0
            for todo in todos {
                _ = try await graph.save(todo)
                imported += 1
            }
            print("✅ Replaced all todos. Imported \(imported) todos.\n")
            
        case 3:
            print("Cancelled.\n")
            
        default:
            print("Invalid choice.\n")
        }
    }
}