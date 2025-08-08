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

## Performance & Reliability

The library includes several performance optimizations:

- **Automatic PreparedStatement Caching** - Queries are automatically cached for better performance
- **Connection Pooling** - Efficient connection management with configurable pool sizes
- **Optimized Type Conversions** - Automatic handling of UUID, Date, and numeric type conversions
- **Transaction Support** - ACID compliant transactions with automatic rollback on errors

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

## Declarative Query DSL

The Query DSL brings Swift's type safety and expressiveness to graph databases with a comprehensive set of features:

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

// Complex predicates with ranges
let ageRange = try await graph.query {
    Match.node(User.self, alias: "u")
    Where.path(\.age, on: "u").between(25, 65)
    Return.node("u")
}

// IN operator for multiple values
let cities = try await graph.query {
    Match.node(User.self, alias: "u")
    Where.path(\.city, on: "u").in(["Tokyo", "Osaka", "Kyoto"])
    Return.node("u")
}

// Combining OR conditions
let adminsOrWriters = try await graph.query {
    Match.node(User.self, alias: "u")
    Where.any([
        path(\.role, on: "u") == "admin",
        path(\.permissions, on: "u").contains("write")
    ])
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

// Advanced aggregations with type safety
let stats = try await graph.query {
    Match.node(User.self, alias: "u")
    Match.edge(Post.self, alias: "p")
        .from("u")
        .to(Post.self)
    Return.aggregates(
        (.count("p"), "postCount"),
        (.avg(path(\.likes, on: "p")), "avgLikes"),
        (.max(path(\.createdAt, on: "p")), "lastPost")
    ).groupBy(path(\.name, on: "u"))
     .orderBy("postCount", .descending)
}
```

### Advanced Features

#### Edge Properties with Type Safety
```swift
// Query edge properties
let recentFollows = try await graph.query {
    Match.edge(Follows.self, alias: "f")
        .from("a")
        .to("b")
    Where(edge(\.since, on: "f") > oneWeekAgo)
    Return.property(edge(\.since, on: "f"), as: "followDate")
}
```

#### OPTIONAL MATCH
```swift
// Find users and their optional profiles
let usersWithProfiles = try await graph.query {
    Match.node(User.self, alias: "u")
    OptionalMatch.node(Profile.self, alias: "p")
        .where(path(\.userId, on: "p") == path(\.id, on: "u"))
    Return.nodes("u", "p")
}
```

#### WITH Clause for Query Pipelining
```swift
// Multi-stage query with WITH
let results = try await graph.query {
    Match.node(User.self, alias: "u")
    With.aggregate(.count("u"), as: "userCount")
        .and("u")
        .limit(100)
    Match.edge(Follows.self)
        .from("u")
        .to("other")
    Return.node("other")
}
```

#### EXISTS Patterns
```swift
// Find users who have posted
let activeUsers = try await graph.query {
    Match.node(User.self, alias: "u")
    Where(Predicate.exists(
        Exists.edge(Post.self, from: "u", to: "p")
    ))
    Return.node("u")
}

// Complex EXISTS with subqueries
let popularUsers = try await graph.query {
    Match.node(User.self, alias: "u")
    Where(Predicate.exists(
        Exists.subquery {
            Match.edge(Follows.self).to("u")
            Return.count() > 100
        }
    ))
    Return.node("u")
}
```

#### Path Patterns
```swift
// Shortest path
let shortestPath = try await graph.query {
    Match.path(
        PathPattern.shortest(
            from: "alice",
            to: "bob",
            via: Follows.self,
            maxHops: 5,
            as: "p"
        )
    )
    Return.pathLength("p", as: "distance")
}

// Variable length paths
let friends = try await graph.query {
    Match.path(
        PathPattern.variablePath(
            from: "user",
            to: "friend",
            via: Follows.self,
            hops: 1...3,
            as: "friendship"
        )
    )
    Return.distinct("friend")
}

// All paths with constraints
let paths = try await graph.query {
    Match.path(
        PathPattern.allPaths(
            from: "start",
            to: "end",
            via: Follows.self,
            maxHops: 4
        )
    )
    Where(Predicate.pathLength("path", .lessThanOrEqual, 3))
    Return.pathNodes("path")
}
```

#### Batch Operations with UNWIND
```swift
// Batch create
let users = [user1, user2, user3]
try await graph.createMany(users)

// Batch update with conditions
try await graph.updateMany(
    User.self,
    matching: path(\.age, on: "u") < 18,
    set: ["category": "minor"]
)

// Batch merge (upsert)
try await graph.mergeMany(
    users,
    matchOn: "id",
    onCreate: ["createdAt": Date()],
    onMatch: ["updatedAt": Date()]
)
```

#### Query Within Transactions
```swift
try await graph.withTransaction { tx in
    // Use Query DSL within transactions
    let user = try tx.queryOne(User.self) {
        Match.node(User.self, alias: "u")
        Where(path(\.id, on: "u") == userId)
        Return.node("u")
    }
    
    // Update using DSL
    try tx.query {
        Match.node(User.self, alias: "u")
        Where(path(\.id, on: "u") == userId)
        Set.property(\.lastActive, on: "u", to: Date())
        Return.node("u")
    }
    
    // Transaction automatically commits or rolls back
}
```

#### Query Debugging and Analysis
```swift
// Enable verbose debugging
QueryDebug.enableVerbose()

// Debug specific query
let result = try await graph.debugQuery(debug: .verbose) {
    Match.node(User.self)
    Return.count()
}
// Outputs: Cypher, parameters, execution time, result count

// Analyze query without execution
let analysis = try graph.analyzeQuery {
    Match.node(User.self, alias: "u")
    Match.edge(Follows.self).from("u").to("other")
    Return.nodes("u", "other")
}
print(analysis.description)
// Shows: operations, node/edge types, complexity score

// Profile query performance
let (result, profile) = try await QueryProfiler.profile {
    try await graph.query {
        Match.node(User.self)
        Return.count()
    }
}
print("Query took \(profile.executionTimeMs)ms")
```

## What Works Today

### SwiftData-like CRUD Operations ✅

These methods are stable and ready for production use:

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

### Raw Cypher Queries ✅

For complex queries, use the stable `raw()` method:

```swift
// Relationship queries
let result = try await graph.raw(
    """
    MATCH (u:User {name: $name})-[:FOLLOWS]->(f:User)
    RETURN f
    """,
    bindings: ["name": "Alice"]
)

// Aggregations
let countResult = try await graph.raw(
    """
    MATCH (u:User)
    WHERE u.age > $minAge
    RETURN count(u) as userCount
    """,
    bindings: ["minAge": 25]
)
```

## Transactions ✅

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

## Query DSL Roadmap

The Query DSL is under active development. Here's the current status:

### ✅ Stable Features
- Basic node/edge matching with `Match.node()` and `Match.edge()`
- Property paths with `path()` for type-safe property access
- Predicates: `==`, `!=`, `>`, `<`, `>=`, `<=`, `between()`, `in()`, `contains()`
- Logical operators: `Where.all()`, `Where.any()`, `Where.not()`
- Create, Update (Set), Delete operations
- Return with ordering, limiting, and distinct
- Query compilation to parameterized Cypher
- Transaction support with automatic rollback
- Connection pooling and PreparedStatement caching

### 🚧 Beta Features
- Complex path queries and pattern matching
- Aggregation functions (count, sum, avg, max, min)
- WITH clause for query pipelining
- OPTIONAL MATCH patterns
- EXISTS patterns for subquery conditions

### 📋 Coming Soon
- Subqueries with full composition
- Graph algorithms (shortest path, etc.)
- Advanced pattern matching
- Full Cypher feature parity

For complex queries not yet supported by the DSL, use `raw()` queries for full Cypher access.

## Query DSL vs Raw Cypher

Currently, raw Cypher is more reliable for complex queries:

```swift
// Declarative Query DSL (Experimental - simple queries work)
let results = try await graph.query {
    Match.node(User.self, alias: "u")
    Where.path(\.age, on: "u") > 25
    Return.node("u")
}

// Raw Cypher (Recommended for production)
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

### Basic Configuration

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

### Connection Pool Configuration

The library automatically manages a connection pool for optimal performance:

```swift
// Detailed connection pool configuration
let config = GraphConfiguration(
    databasePath: "/path/to/graph.db",
    options: GraphConfiguration.Options(
        maxConnections: 10,        // Maximum concurrent connections
        minConnections: 2,         // Minimum connections to maintain
        connectionTimeout: 30.0,   // Connection timeout in seconds
        maxThreads: 4,            // Maximum threads for parallel operations
        extensions: [.fts, .vector]
    )
)

// Proper shutdown - ensures all connections are cleaned up
let context = try await GraphContext(configuration: config)
defer { 
    await context.close()  // Drains the connection pool
}
```

### Connection Pool Management

The connection pool automatically manages connections, but you can control its lifecycle:

```swift
// Automatic management with GraphDatabase.shared
let graph = try await GraphDatabase.shared.context()
// Connections are pooled automatically

// Manual management for custom scenarios
let container = try await GraphContainer(configuration: config)
// Use the container...
await container.close()  // Drains the pool and prevents new connections
```

## Troubleshooting

### Common Issues

1. **Reserved Keywords**: Avoid Cypher reserved words (e.g., use `result` instead of `exists`)
2. **Build Times**: First build compiles Kuzu C++ (~5-10 minutes). Use incremental builds.
3. **Type Mismatches**: Kuzu returns `Int64` for counts, handle accordingly
4. **Memory Usage**: Ensure 8GB+ RAM for C++ compilation

### Automatic Type Conversions

The library handles common type conversions automatically:

- **UUID** ↔ String conversion for storage
- **Date** ↔ Timestamp conversion (ISO8601 format)
- **Numeric types**: Flexible conversions between Int, Int64, Double, Float
- **Arrays and Dictionaries**: Automatic encoding/decoding with proper reference handling
- **Optional types**: Automatic wrapping/unwrapping

This means you can use Swift native types without worrying about database representations:

```swift
@GraphNode
struct User: Codable {
    @ID var id: UUID = UUID()  // Automatically converted to/from String
    var age: Int               // Works with Int64 from database
    var score: Double          // Works with various numeric types
    var tags: [String]         // Automatically encoded/decoded
    var metadata: [String: Any]? // Dictionaries handled properly
    @Timestamp var createdAt: Date = Date() // Converted to Timestamp
}
```

### Error Handling

The library provides comprehensive error handling with specific error types:

```swift
do {
    let results = try await graph.query { /* ... */ }
} catch GraphError.connectionPoolExhausted {
    // Connection pool has been drained (e.g., after calling close())
    print("Connection pool is no longer available")
} catch GraphError.connectionTimeout(let duration) {
    // Failed to acquire a connection within the timeout period
    print("Failed to get connection within \(duration) seconds")
} catch GraphError.transactionFailed(let reason) {
    // Transaction was rolled back due to an error
    print("Transaction failed: \(reason)")
} catch GraphError.invalidConfiguration(let message) {
    // Configuration issue
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