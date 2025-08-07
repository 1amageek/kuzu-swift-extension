# Kuzu Swift Extension

**Type-Safe Graph Database for Swift** - A declarative, SwiftUI-like query DSL for the Kuzu graph database

![Swift 6.1+](https://img.shields.io/badge/Swift-6.1+-orange.svg)
![Platform](https://img.shields.io/badge/platform-macOS%20|%20iOS%20|%20tvOS%20|%20watchOS-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)

## Why This Library?

Graph databases are powerful but often require learning complex query languages. This library brings Swift's type safety and declarative syntax to graph databases, making them as easy to use as SwiftUI.

```swift
// Instead of error-prone string queries:
// "MATCH (u:User) WHERE u.age > 25 RETURN u"

// Write type-safe, declarative queries:
let adults = try await graph.query {
    Match.node(User.self, alias: "u")
    Where.path(\.age, on: "u") > 25
    Return.node("u")
}
```

## Features

- 🎯 **Declarative Query DSL** - SwiftUI-like syntax for graph queries
- 🔒 **100% Type-Safe** - Compile-time validation with Swift KeyPaths
- ✨ **Zero Configuration** - Start immediately with `GraphDatabase.shared`
- 🚀 **Modern Swift** - Full async/await and Swift 6 concurrency support
- 🔄 **Automatic Schema** - Generates DDL from your Swift models
- 💾 **ACID Transactions** - Full transaction support with automatic rollback
- 🎨 **Rich Attributes** - `@ID`, `@Index`, `@Unique`, `@FullTextSearch`, and more
- ⚡ **High Performance** - Connection pooling and batch operations

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/kuzu-swift-extension", from: "0.3.0")
]
```

Then add to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "KuzuSwiftExtension", package: "kuzu-swift-extension"),
        .product(name: "KuzuSwiftMacros", package: "kuzu-swift-extension")
    ]
)
```

## Quick Start

### 1. Define Your Model

```swift
import KuzuSwiftExtension

@GraphNode
struct User: Codable {
    @ID var id: UUID = UUID()
    var name: String
    var age: Int
    @Timestamp var createdAt: Date = Date()
}

@GraphEdge(from: User.self, to: User.self)
struct Follows: Codable {
    @Timestamp var since: Date = Date()
}
```

### 2. Use It Immediately

```swift
// Get the shared graph context
let graph = try await GraphDatabase.shared.context()

// Save a user
let alice = User(name: "Alice", age: 30)
try await graph.save(alice)

// Query with type-safe DSL
let adults = try await graph.query {
    Match.node(User.self, alias: "u")
    Where.path(\.age, on: "u") >= 18
    Return.node("u")
}
```

## Declarative Query DSL - The Heart of This Library

The Query DSL brings Swift's type safety and expressiveness to graph databases. No more string concatenation or runtime errors!

### Basic Queries

```swift
// Find users by name
let results = try await graph.query {
    Match.node(User.self, alias: "u")
    Where.path(\.name, on: "u") == "Alice"
    Return.node("u")
}

// Multiple conditions
let filtered = try await graph.query {
    Match.node(User.self, alias: "u")
    Where.all([
        path(\.age, on: "u") >= 25,
        path(\.age, on: "u") <= 65,
        path(\.city, on: "u") == "Tokyo"
    ])
    Return.node("u")
        .orderBy(path(\.name, on: "u"))
        .limit(10)
}

// String operations
let search = try await graph.query {
    Match.node(User.self, alias: "u")
    Where.path(\.name, on: "u").contains("John")
    Return.node("u")
}
```

### Relationship Queries

```swift
// Who does Alice follow?
let following = try await graph.query {
    Match.node(User.self, alias: "alice")
        .where(path(\.name, on: "alice") == "Alice")
    Match.edge(Follows.self)
        .from("alice")
        .to(User.self, alias: "friend")
    Return.node("friend")
}

// Find mutual friends
let mutual = try await graph.query {
    Match.node(User.self, alias: "user1")
        .where(path(\.id, on: "user1") == userId1)
    Match.node(User.self, alias: "user2")
        .where(path(\.id, on: "user2") == userId2)
    Match.edge(Follows.self).from("user1").to(User.self, alias: "mutual")
    Match.edge(Follows.self).from("user2").to("mutual")
    Return.distinct("mutual")
}

// Friends of friends (2 hops)
let friendsOfFriends = try await graph.query {
    Match.node(User.self, alias: "me")
        .where(path(\.id, on: "me") == myId)
    Match.path(
        from: "me",
        to: (User.self, "fof"),
        via: Follows.self,
        hops: 2
    )
    Where.not(path(\.id, on: "fof") == myId)
    Return.distinct("fof")
}
```

### Creating and Updating

```swift
// Create nodes and relationships
try await graph.query {
    Create.node(User.self, alias: "u1")
        .set(\.name, to: "Alice")
        .set(\.age, to: 30)
    Create.node(User.self, alias: "u2")
        .set(\.name, to: "Bob")
        .set(\.age, to: 25)
    Create.edge(Follows.self)
        .from("u1")
        .to("u2")
        .set(\.since, to: Date())
}

// Update existing nodes
try await graph.query {
    Match.node(User.self, alias: "u")
        .where(path(\.id, on: "u") == userId)
    Set.property(\.lastActive, on: "u", to: Date())
    Set.property(\.loginCount, on: "u", to: path(\.loginCount, on: "u") + 1)
    Return.node("u")
}

// Delete operations
try await graph.query {
    Match.node(User.self, alias: "u")
        .where(path(\.isDeleted, on: "u") == true)
    Delete.node("u")
}
```

### Aggregations

```swift
// Count followers
let followerCount = try await graph.queryValue(Int.self) {
    Match.node(User.self, alias: "u")
        .where(path(\.id, on: "u") == userId)
    Match.edge(Follows.self)
        .from(User.self, alias: "follower")
        .to("u")
    Return.count("follower")
}

// Group and aggregate
let stats = try await graph.query {
    Match.node(User.self, alias: "u")
    Match.edge(Post.self)
        .from("u")
        .to(Post.self, alias: "p")
    Return.items(
        .alias("u"),
        .count("p", as: "postCount"),
        .avg(path(\.likes, on: "p"), as: "avgLikes")
    )
    .groupBy("u")
    .orderBy("postCount", .descending)
}
```

### Advanced: Path Queries

```swift
// Shortest path between users
let path = try await graph.query {
    Match.shortestPath(
        from: (User.self, "start"),
        to: (User.self, "end"),
        via: Follows.self,
        maxHops: 6
    )
    Where.path(\.id, on: "start") == startId
    Where.path(\.id, on: "end") == endId
    Return.path("path")
}

// Recommendation engine - users within 3 hops
let recommendations = try await graph.query {
    Match.node(User.self, alias: "me")
        .where(path(\.id, on: "me") == myId)
    Match.path(
        from: "me",
        to: (User.self, "recommended"),
        via: Follows.self,
        hops: 2...3
    )
    Where.not(exists: Follows.self, from: "me", to: "recommended")
    Return.distinct("recommended")
        .limit(10)
}
```

## SwiftData-like CRUD Operations

For simple operations, use the familiar save/fetch/delete pattern:

```swift
let graph = try await GraphDatabase.shared.context()

// Save
let user = User(name: "Charlie", age: 28)
let saved = try await graph.save(user)

// Fetch
let users = try await graph.fetch(User.self)
let charlie = try await graph.fetchOne(User.self, id: saved.id)
let adults = try await graph.fetch(User.self, where: "age", equals: 18)

// Update
saved.age = 29
try await graph.save(saved)

// Delete
try await graph.delete(saved)
try await graph.deleteAll(User.self)

// Count
let count = try await graph.count(User.self)
```

## Transactions

Ensure data consistency with ACID transactions:

```swift
// All operations succeed or fail together
try await graph.withTransaction { txContext in
    let user = User(name: "Alice", age: 30)
    try txContext.save(user)
    
    let post = Post(title: "Hello Graph", authorId: user.id)
    try txContext.save(post)
    
    // If any operation fails, everything is rolled back
    guard post.title.count > 5 else {
        throw ValidationError.titleTooShort
    }
}
```

## Property Attributes

Enhance your models with powerful attributes:

```swift
@GraphNode
struct Article: Codable {
    @ID var id: UUID = UUID()
    @Unique var slug: String
    @Index var title: String
    @FullTextSearch var content: String
    @Vector(dimensions: 1536) var embedding: [Double]
    @Default("draft") var status: String
    @Timestamp var createdAt: Date = Date()
}
```

## Real-World Examples

### Social Network

```swift
// Find influencers (users with many followers)
let influencers = try await graph.query {
    Match.node(User.self, alias: "u")
    Match.edge(Follows.self)
        .from(User.self, alias: "follower")
        .to("u")
    Return.items(
        .alias("u"),
        .count("follower", as: "followerCount")
    )
    .groupBy("u")
    .having("followerCount", .greaterThan, 1000)
    .orderBy("followerCount", .descending)
    .limit(100)
}
```

### E-Commerce Recommendations

```swift
// Users who bought this also bought
let recommendations = try await graph.query {
    Match.node(Product.self, alias: "product")
        .where(path(\.id, on: "product") == productId)
    Match.edge(Purchased.self)
        .from(User.self, alias: "buyer")
        .to("product")
    Match.edge(Purchased.self)
        .from("buyer")
        .to(Product.self, alias: "otherProduct")
    Where.not(path(\.id, on: "otherProduct") == productId)
    Return.items(
        .alias("otherProduct"),
        .count("buyer", as: "purchaseCount")
    )
    .groupBy("otherProduct")
    .orderBy("purchaseCount", .descending)
    .limit(10)
}
```

### Content Management

```swift
// Find related articles by tags
let related = try await graph.query {
    Match.node(Article.self, alias: "article")
        .where(path(\.id, on: "article") == articleId)
    Match.edge(HasTag.self)
        .from("article")
        .to(Tag.self, alias: "tag")
    Match.edge(HasTag.self)
        .from(Article.self, alias: "related")
        .to("tag")
    Where.not(path(\.id, on: "related") == articleId)
    Return.items(
        .alias("related"),
        .count("tag", as: "commonTags")
    )
    .groupBy("related")
    .orderBy("commonTags", .descending)
    .limit(5)
}
```

## SwiftUI Integration

```swift
struct UserListView: View {
    @State private var users: [User] = []
    @State private var searchText = ""
    
    var body: some View {
        List(users) { user in
            UserRow(user: user)
        }
        .searchable(text: $searchText)
        .onChange(of: searchText) { _, newValue in
            Task {
                await searchUsers(newValue)
            }
        }
        .task {
            await loadUsers()
        }
    }
    
    func searchUsers(_ query: String) async {
        let graph = try? await GraphDatabase.shared.context()
        users = try? await graph?.query {
            Match.node(User.self, alias: "u")
            Where.path(\.name, on: "u").contains(query)
            Return.node("u")
                .limit(50)
        } ?? []
    }
}
```

## Query DSL vs Raw Cypher

While the Query DSL is recommended for type safety, you can still use raw Cypher when needed:

```swift
// Declarative Query DSL (Recommended)
let results = try await graph.query {
    Match.node(User.self, alias: "u")
    Where.path(\.age, on: "u") > 25
    Return.node("u")
}

// Raw Cypher (For complex or dynamic queries)
let results = try await graph.raw("""
    MATCH (u:User)
    WHERE u.age > $minAge
    RETURN u
    """, bindings: ["minAge": 25])
```

## Performance Tips

1. **Use Indexes**: Add `@Index` to frequently queried properties
2. **Batch Operations**: Use `batchInsert()` for bulk data
3. **Connection Pooling**: Automatically managed, configure if needed
4. **Limit Results**: Always use `.limit()` for large datasets
5. **Use Transactions**: Group related operations for better performance

## Advanced Configuration

```swift
// Custom configuration
let config = GraphConfiguration(
    databasePath: "/custom/path/graph.db",
    options: GraphConfiguration.Options(
        maxConnections: 10,
        connectionTimeout: 30.0,
        extensions: [.fts, .vector]
    )
)

let context = try await GraphContext(configuration: config)
```

## Troubleshooting

### Common Issues

1. **Reserved Keywords**: Avoid Cypher reserved words (e.g., use `result` instead of `exists`)
2. **Build Times**: First build compiles Kuzu C++ (~5-10 minutes). Use incremental builds.
3. **Type Mismatches**: Kuzu returns `Int64` for counts, handle accordingly
4. **Memory Usage**: Ensure 8GB+ RAM for C++ compilation

### Error Handling

```swift
do {
    let results = try await graph.query { /* ... */ }
} catch GraphError.connectionTimeout(let duration) {
    print("Connection timed out after \(duration)s")
} catch GraphError.invalidConfiguration(let message) {
    print("Configuration error: \(message)")
} catch {
    print("Unexpected error: \(error)")
}
```

## Requirements

- Swift 6.1+
- macOS 14+, iOS 17+, tvOS 17+, watchOS 10+
- Xcode 16+

## Documentation

- [API Documentation](https://github.com/1amageek/kuzu-swift-extension/wiki)
- [Query DSL Reference](https://github.com/1amageek/kuzu-swift-extension/wiki/Query-DSL)
- [Migration Guide](https://github.com/1amageek/kuzu-swift-extension/wiki/Migration)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License

## Acknowledgments

Built on the excellent [Kuzu](https://kuzudb.com) embedded graph database and its [Swift bindings](https://github.com/kuzudb/kuzu-swift).

Special thanks to the Kuzu team for creating such a powerful and easy-to-use graph database.