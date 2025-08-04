# Kuzu Swift Extension

**Graph database as easy as SQLite** - A type-safe graph database extension library for Swift developers

![Swift 6.1+](https://img.shields.io/badge/Swift-6.1+-orange.svg)
![Platform](https://img.shields.io/badge/platform-macOS%20|%20iOS%20|%20tvOS%20|%20watchOS-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)

## Features

- ✨ **Zero Configuration** - Start immediately with `GraphDatabase.shared`
- 🎯 **SwiftData-like API** - Intuitive methods: `save()`, `fetch()`, `delete()`
- 🔄 **Automatic Schema Management** - Auto-generates DDL from your models
- 🏗️ **Type Safety** - Compile-time error detection with Swift macros
- 🚀 **Modern Swift** - Full async/await support

## Installation

### Swift Package Manager

In Xcode, go to File → Add Package Dependencies and add:

```
https://github.com/1amageek/kuzu-swift-extension
```

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/kuzu-swift-extension", from: "0.2.0")
]
```

Then add the dependency to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "KuzuSwiftExtension", package: "kuzu-swift-extension"),
        .product(name: "KuzuSwiftMacros", package: "kuzu-swift-extension")
    ]
)
```

Minimal configuration example:

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MyGraphApp",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/1amageek/kuzu-swift-extension", from: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "MyGraphApp",
            dependencies: [
                .product(name: "KuzuSwiftExtension", package: "kuzu-swift-extension"),
                .product(name: "KuzuSwiftMacros", package: "kuzu-swift-extension")
            ]
        )
    ]
)
```

## Quick Start - Works from the First Line!

### 1. Define Your Model (Todo.swift)

```swift
import KuzuSwiftExtension

@GraphNode
struct Todo: Codable {
    @ID var id: UUID = UUID()
    var title: String
    var done: Bool = false
    @Timestamp var createdAt: Date = Date()
}
```

### 2. Usage (Works in 3 Lines!)

```swift
// Initialize graph DB (automatic file path configuration)
let graph = try await GraphDatabase.shared.context()

// Save a Todo
let todo = Todo(title: "Buy groceries")
try await graph.save(todo)

// Fetch all todos
let todos = try await graph.fetch(Todo.self)
print(todos) // [Todo(id: ..., title: "Buy groceries", done: false)]
```

### 3. More Practical Example

```swift
import SwiftUI
import KuzuSwiftExtension

// Using with SwiftUI
struct ContentView: View {
    @State private var todos: [Todo] = []
    @State private var newTodoTitle = ""
    
    var body: some View {
        VStack {
            // Todo input
            HStack {
                TextField("New Todo", text: $newTodoTitle)
                Button("Add") {
                    Task {
                        let todo = Todo(title: newTodoTitle)
                        let graph = try await GraphDatabase.shared.context()
                        try await graph.save(todo)
                        todos = try await graph.fetch(Todo.self)
                        newTodoTitle = ""
                    }
                }
            }
            
            // Todo list
            List(todos, id: \.id) { todo in
                HStack {
                    Text(todo.title)
                    Spacer()
                    if todo.done {
                        Image(systemName: "checkmark")
                    }
                }
                .onTapGesture {
                    Task {
                        var updatedTodo = todo
                        updatedTodo.done.toggle()
                        let graph = try await GraphDatabase.shared.context()
                        try await graph.save(updatedTodo)
                        todos = try await graph.fetch(Todo.self)
                    }
                }
            }
        }
        .task {
            let graph = try await GraphDatabase.shared.context()
            todos = try await graph.fetch(Todo.self)
        }
    }
}
```

## Advanced Usage

### SwiftData-like CRUD Operations

```swift
let graph = try await GraphDatabase.shared.context()

// Fetch one
if let todo = try await graph.fetchOne(Todo.self, id: todoId) {
    print(todo)
}

// Query with conditions
let completedTodos = try await graph.fetch(Todo.self, where: "done", equals: true)

// Delete
try await graph.delete(todo)
try await graph.deleteAll(Todo.self)

// Count
let count = try await graph.count(Todo.self)
```

### Relationships (Follow Feature)

```swift
@GraphNode 
struct User: Codable {
    @ID var id: UUID = UUID()
    var name: String
}

@GraphEdge(from: User.self, to: User.self)
struct Follows: Codable {
    @Timestamp var since: Date = Date()
}

// Create follow relationship
let alice = User(name: "Alice")
let bob = User(name: "Bob")

try await graph.save([alice, bob])
try await graph.createRelationship(
    from: alice,
    to: bob, 
    edge: Follows()
)
```

## Traditional Advanced Features

### Property Annotations

```swift
@GraphNode
struct Document: Codable {
    @ID var id: UUID = UUID()
    @Index var title: String
    @FTS var content: String  // Full-text search
    @Vector(dimensions: 1536) var embedding: [Double]  // Vector search
    @Timestamp var createdAt: Date = Date()  // Automatic timestamp
}
```

### Complex Queries (Query DSL)

```swift
// Find users with common interests
let result = try await graph.query {
    Match.node(User.self, alias: "u1")
    Match.node(Interest.self, alias: "i")
    Match.node(User.self, alias: "u2", where: property("u2", "id") != property("u1", "id"))
    Match.edge(HasInterest.self).from("u1").to("i")
    Match.edge(HasInterest.self).from("u2").to("i")
    Return.items(.alias("u1"), .alias("u2"), .alias("i"))
        .orderBy("i.name")
        .limit(10)
}
```

### Raw Cypher Queries

```swift
// Execute Cypher with parameter binding
let result = try await graph.raw(
    """
    MATCH (u:User {name: $name})-[:FOLLOWS]->(f:User)
    RETURN f
    """,
    bindings: ["name": "Alice"]
)
```

### Transactions

```swift
// Operations within a transaction
try await graph.transaction { ctx in
    let charlie = User(name: "Charlie")
    try await ctx.save(charlie)
    
    try await ctx.createRelationship(
        from: alice,
        to: charlie,
        edge: Follows()
    )
}
```

### Automatic Schema Migration

```swift
// Register models for automatic schema creation on first launch
GraphDatabase.shared.register(models: [
    Todo.self,
    User.self,
    Follows.self
])

// Manual migration is also possible
let graph = try await GraphDatabase.shared.context()
try await graph.createSchema(for: [Todo.self])
```

## Why Graph Database?

- **Natural Relationship Modeling** - Intuitively model follows, likes, friendships
- **Fast Graph Traversal** - Quickly compute mutual friends, recommendations, shortest paths
- **Flexible Schema** - Freely add properties to nodes and edges

## Requirements

- Swift 6.1+
- macOS 14+, iOS 17+, tvOS 17+, watchOS 10+

## License

MIT License

## Acknowledgments

Built on the excellent [Kuzu](https://kuzudb.com) graph database and its [Swift bindings](https://github.com/kuzudb/kuzu-swift).