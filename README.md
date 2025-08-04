# Kuzu Swift Extension

A declarative, type-safe Swift extension for [Kuzu](https://github.com/kuzudb/kuzu-swift) graph database that brings the power of Swift's type system to graph operations.

![Swift 6.1+](https://img.shields.io/badge/Swift-6.1+-orange.svg)
![Platform](https://img.shields.io/badge/platform-macOS%20|%20iOS%20|%20tvOS%20|%20watchOS-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)

## Features

- 🎯 **Type-Safe Graph Models** - Define nodes and edges using Swift structs with property wrappers
- 🔄 **Automatic Schema Management** - Generate DDL from Swift types with migration support
- 🔍 **Swift-Native Query DSL** - Build Cypher queries using familiar Swift syntax
- 🏗️ **Compile-Time Safety** - Catch schema and query errors at compile time with Swift macros
- 🔗 **Connection Pooling** - Efficient connection management with configurable pool sizes
- 🚀 **Async/Await Support** - Modern Swift concurrency throughout the API
- 🎨 **Property Annotations** - Support for indices, vectors, full-text search, and timestamps

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/kuzu-swift-extension", from: "0.1.0")
]
```

Then add `KuzuSwiftExtension` to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: ["KuzuSwiftExtension"]
)
```

## Quick Start

### 1. Define Your Graph Models

```swift
import KuzuSwiftExtension

// Define a node
@GraphNode
struct User {
    @ID var id: String
    @Index var username: String
    var email: String?
    var createdAt: Date
}

// Define an edge
@GraphEdge(from: User.self, to: User.self)
struct Follows {
    @ID var id: String
    @Timestamp var followedAt: Date
}
```

### 2. Initialize the Graph Container

```swift
// Configure the database
let config = GraphConfiguration(
    databasePath: "path/to/database",
    options: GraphConfiguration.Options(
        maxConnections: 10,
        minConnections: 2
    )
)

// Create container
let container = try await GraphContainer(configuration: config)

// Initialize context with your models
let context = GraphContext(
    container: container,
    models: [User.self, Follows.self]
)

// Migrate schema
try await context.migrate()
```

### 3. Create and Query Data

```swift
// Create users
try await context.query {
    Create(User(id: "1", username: "alice", email: "alice@example.com", createdAt: Date()))
    Create(User(id: "2", username: "bob", email: "bob@example.com", createdAt: Date()))
}

// Create relationship
try await context.query {
    Match(User.self, where: \User.id == "1").as("a")
    Match(User.self, where: \User.id == "2").as("b")
    Create(Follows(id: "f1", followedAt: Date())).from("a").to("b")
}

// Query followers
let followers = try await context.query {
    Match(User.self).as("follower")
    Match(Follows.self).from("follower").to("user")
    Match(User.self, where: \User.username == "bob").as("user")
    Return("follower")
}.decode(User.self)

print("Bob's followers: \(followers)")
```

## Advanced Features

### Property Annotations

```swift
@GraphNode
struct Document {
    @ID var id: String
    @Index var title: String
    @FTS var content: String  // Full-text search
    @Vector(dimensions: 1536) var embedding: [Double]  // Vector for similarity search
    @Timestamp var createdAt: Date  // Auto-timestamp
}
```

### Complex Queries

```swift
// Find users with common interests
let result = try await context.query {
    Match(User.self).as("u1")
    Match(Interest.self).as("i")
    Match(User.self, where: \User.id != "u1.id").as("u2")
    Match(HasInterest.self).from("u1").to("i")
    Match(HasInterest.self).from("u2").to("i")
    Return("u1", "u2", "i")
        .orderBy("i.name")
        .limit(10)
}
```

### Raw Cypher Queries

```swift
// Execute raw Cypher with parameter binding
let result = try await context.raw(
    """
    MATCH (u:User {username: $username})-[:FOLLOWS]->(f:User)
    RETURN f
    """,
    bindings: ["username": "alice"]
)
```

### Transactions

```swift
// Perform operations in a transaction
try await context.transaction { ctx in
    try await ctx.query {
        Create(User(id: "3", username: "charlie", email: nil, createdAt: Date()))
    }
    
    try await ctx.query {
        Match(User.self, where: \User.id == "1").as("a")
        Match(User.self, where: \User.id == "3").as("c")
        Create(Follows(id: "f2", followedAt: Date())).from("a").to("c")
    }
}
```

### Migration Policies

```swift
// Safe migrations only (default)
try await context.migrate(policy: .safeOnly)

// Allow destructive changes
try await context.migrate(policy: .allowDestructive)
```

## Architecture

The library is organized in layers:

1. **Model Layer** - Swift macros generate schema from your types
2. **Schema Layer** - Automatic DDL generation and migration
3. **Context Layer** - Connection management and query execution
4. **Query DSL** - Type-safe Cypher query builder
5. **Result Mapping** - Automatic decoding of query results

## Requirements

- Swift 6.1+
- macOS 14+, iOS 17+, tvOS 17+, watchOS 10+
- [Kuzu](https://kuzudb.com) database

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

Built on top of the excellent [Kuzu](https://kuzudb.com) graph database and its [Swift bindings](https://github.com/kuzudb/kuzu-swift).