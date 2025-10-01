# SwiftUI Integration Example

## Basic Setup

### 1. Define Your Models

```swift
import KuzuSwiftExtension

@GraphNode
struct User: Codable {
    @ID var id: String
    var name: String
    var email: String
}

@GraphNode
struct Post: Codable {
    @ID var id: String
    var title: String
    var content: String
}

@GraphEdge
struct Authored: Codable {
    @Since(\User.id) var authorID: String
    @Target(\Post.id) var postID: String
    var createdAt: Date
}
```

### 2. App Configuration (SwiftData-style)

```swift
import SwiftUI
import KuzuSwiftExtension

@main
struct MyApp: App {
    // Create container with your models
    let graphContainer: GraphContainer

    init() {
        do {
            graphContainer = try GraphContainer(
                for: User.self, Post.self, Authored.self,
                configuration: GraphConfiguration(databasePath: "myapp.db")
            )
        } catch {
            fatalError("Failed to create GraphContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .graphContainer(graphContainer)  // ✅ SwiftData-style injection
    }
}
```

### 3. Using in Views

#### Option 1: Access GraphContext (Recommended)

```swift
struct ContentView: View {
    @Environment(\.graphContext) var context
    @State private var users: [User] = []

    var body: some View {
        List(users, id: \.id) { user in
            Text(user.name)
        }
        .toolbar {
            Button("Add User") {
                addUser()
            }
        }
        .task {
            loadUsers()
        }
    }

    func loadUsers() {
        do {
            users = try context.fetch(User.self)
        } catch {
            print("Failed to load users: \(error)")
        }
    }

    func addUser() {
        let newUser = User(
            id: UUID().uuidString,
            name: "Alice",
            email: "alice@example.com"
        )
        context.insert(newUser)

        do {
            try context.save()
            loadUsers()
        } catch {
            print("Failed to save user: \(error)")
        }
    }
}
```

#### Option 2: Access GraphContainer

```swift
struct SettingsView: View {
    @Environment(\.graphContainer) var container

    var body: some View {
        if let container = container {
            Text("Database: \(container.configuration.databasePath)")
            Text("Models: \(container.models.count)")
        }
    }
}
```

## Advanced Patterns

### Change Tracking

```swift
struct SaveButton: View {
    @Environment(\.graphContext) var context

    var body: some View {
        Button("Save") {
            if context.hasChanges {
                try? context.save()
            }
        }
        .disabled(!context.hasChanges)
    }
}
```

### Lifecycle-based Auto-save

```swift
struct ContentView: View {
    @Environment(\.graphContext) var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MyContent()
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .background {
                    autosave()
                }
            }
    }

    func autosave() {
        if context.hasChanges {
            try? context.save()
        }
    }
}
```

### Transactions

```swift
struct BatchInsertView: View {
    @Environment(\.graphContext) var context

    func importUsers(_ users: [User]) {
        do {
            try context.transaction {
                for user in users {
                    context.insert(user)
                }
                // Automatically saved when block completes
            }
        } catch {
            print("Import failed: \(error)")
        }
    }
}
```

### Edge Creation

```swift
struct CreatePostView: View {
    @Environment(\.graphContext) var context
    let author: User
    @State private var title = ""
    @State private var content = ""

    func createPost() {
        let post = Post(
            id: UUID().uuidString,
            title: title,
            content: content
        )

        let edge = Authored(
            authorID: author.id,
            postID: post.id,
            createdAt: Date()
        )

        context.insert(post)
        context.insert(edge)

        try? context.save()
    }
}
```

## View-Level Container Injection

For testing or modular components:

```swift
struct PreviewContainer: View {
    let previewContainer: GraphContainer

    init() {
        previewContainer = try! GraphContainer(
            for: User.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
    }

    var body: some View {
        ContentView()
            .graphContainer(previewContainer)
    }
}
```

## Comparison with SwiftData

| SwiftData | kuzu-swift-extension |
|-----------|----------------------|
| `ModelContainer` | `GraphContainer` |
| `.modelContainer()` | `.graphContainer()` |
| `@Environment(\.modelContext)` | `@Environment(\.graphContext)` |
| `modelContext.insert()` | `context.insert()` |
| `try modelContext.save()` | `try context.save()` |

## Platform Support

- iOS 18.0+
- macOS 15.0+
- tvOS 18.0+
- watchOS 11.0+
