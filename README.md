# KuzuSwiftExtension

**SwiftUI-like Query DSL for Graph Databases** - Type-safe, declarative graph database operations in Swift

![Swift 6.2+](https://img.shields.io/badge/Swift-6.2+-orange.svg)
![Platform](https://img.shields.io/badge/platform-macOS%20|%20iOS%20|%20tvOS%20|%20watchOS-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)

## Overview

KuzuSwiftExtension brings SwiftUI's declarative approach to graph databases. Write type-safe queries with Swift's native syntax instead of error-prone string queries.

```swift
// Single component returns its result type directly
let adults: [User] = try await graph.query {
    User.where(\.age > 25)
}

// Multiple components return a tuple
let (users, posts) = try await graph.query {
    User.match().where(\.active == true)
    Post.match().orderBy(\.createdAt, .descending)
}
```

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/kuzu-swift-extension", branch: "main")
]
```

## Quick Start

### 1. Define Your Models

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

### 2. Start Using Immediately

```swift
// Zero configuration - just start using
let graph = try await GraphDatabase.shared.context()

// Save data
let alice = User(name: "Alice", age: 30)
try await graph.save(alice)

// Query with type-safe DSL
let adults = try await graph.query {
    User.where(\.age >= 18)
}
```

## Core Features

### CRUD Operations

```swift
// Create
let user = User(name: "Bob", age: 25)
try await graph.save(user)

// Read
let users = try await graph.fetch(User.self)
let bob = try await graph.fetchOne(User.self, id: user.id)

// Update
user.age = 26
try await graph.save(user)

// Delete
try await graph.delete(user)

// Count
let count = try await graph.count(User.self)
```

### Declarative Query DSL

The Query DSL provides comprehensive, type-safe query building:

#### Node Operations

```swift
// Match nodes with conditions
let users = try await graph.query {
    User.match()
        .where(\.age >= 18)
        .orderBy(\.name)
        .limit(10)
}

// Optional match for nullable results
let maybeUsers = try await graph.query {
    User.optional()
        .where(\.city == "Tokyo")
}

// Create nodes declaratively
try await graph.query {
    Create.node(User.self, properties: [
        "name": "Charlie",
        "age": 28
    ])
}

// Merge (upsert) operations
try await graph.query {
    User.merge(on: \.email, equals: "alice@example.com")
        .onCreate(set: ["createdAt": Date()])
        .onMatch(set: ["lastLogin": Date()])
}
```

#### Edge Operations

```swift
// Create edges between nodes
try await graph.query {
    let alice = User.match().where(\.name == "Alice")
    let bob = User.match().where(\.name == "Bob")
    
    Create.edge(Follows.self, from: alice, to: bob, properties: [
        "since": Date()
    ])
}

// Match edges with conditions
let followers = try await graph.query {
    let user = User.match().where(\.id == userId)
    Follows.match()
        .from(User.match())
        .to(user)
        .where("since", .greaterThan, oneMonthAgo)
}

// Merge edges (create if not exists)
try await graph.query {
    Follows.merge(from: alice, to: bob)
        .onCreate(set: ["since": Date()])
        .onMatch(set: ["lastInteraction": Date()])
}
```

#### Aggregations

```swift
// Count
let userCount = try await graph.query {
    Count<User>(nodeRef: User.match())
}

// Average
let avgAge = try await graph.query {
    Average(nodeRef: User.match(), keyPath: \User.age)
}

// Sum
let totalLikes = try await graph.query {
    Sum(Post.match(), keyPath: \Post.likes)
}

// Min/Max
let oldest = try await graph.query {
    Max(nodeRef: User.match(), keyPath: \User.age)
}

// Collect nodes into array
let allUsers = try await graph.query {
    Collect(nodeRef: User.match())
}
```

#### Complex Queries

```swift
// Multiple operations in one query
try await graph.query {
    // Match existing nodes
    let alice = User.match().where(\.name == "Alice")
    let bob = User.match().where(\.name == "Bob")
    
    // Create new edge
    Create.edge(Follows.self, from: alice, to: bob)
    
    // Update properties
    SetProperties(alice.alias)
        .set("lastActive", to: Date())
    
    // Delete old edges
    let oldFollows = Follows.match()
        .where("since", .lessThan, oneYearAgo)
    Delete(oldFollows.alias)
}

// Conditional queries
@QueryBuilder
func buildConditionalQuery(includeInactive: Bool) -> some QueryComponent {
    if includeInactive {
        User.match()
    } else {
        User.match().where(\.active == true)
    }
}

// Loops with ForEach
let queries = users.map { user in
    User.merge(on: \.id, equals: user.id)
        .onCreate(set: ["name": user.name])
}
try await graph.query {
    ForEachQuery(queries)
}
```

### Tuple Queries with Parameter Packs

The library uses Swift 6.2's parameter pack features for type-safe tuple queries:

```swift
// Single component - returns the component's Result type
let users: [User] = try await graph.query {
    User.match().where(\.active == true)
}

// Two components - returns a tuple (T1.Result, T2.Result)
let (users, posts) = try await graph.query {
    User.match().where(\.active == true)
    Post.match().where(\.published == true)
}

// Three or more components - returns an expanded tuple
let (users, posts, comments) = try await graph.query {
    User.match().where(\.active == true)
    Post.match().where(\.published == true)
    Comment.match().orderBy(\.createdAt, .descending)
}

// The @QueryBuilder automatically creates:
// - Single component: T
// - Multiple components: TupleQuery<repeat each T> where Result = (repeat (each T).Result)
```

### Component Types

#### Create Operations
```swift
// Create nodes
Create.node(User.self, properties: ["name": "Alice", "age": 30])
Create.node(user) // From instance

// Create edges
Create.edge(Follows.self, from: alice, to: bob)
Create.edge(followsInstance, from: alice, to: bob)
```

#### Merge Operations
```swift
// Merge nodes (upsert)
Merge(User.self, matching: ["email": email])
    .onCreate(set: ["createdAt": Date()])
    .onMatch(set: ["updatedAt": Date()])

// Merge edges
Follows.merge(from: alice, to: bob)
    .onCreate(set: ["since": Date()])
```

#### Update Operations
```swift
// Set properties on nodes or edges
SetProperties("nodeAlias")
    .set("property", to: value)
    .set("computed", to: { $0.value + 1 })
```

#### Delete Operations
```swift
// Delete nodes or edges
Delete("nodeAlias")
Delete("edgeAlias", detach: true) // Detach delete for nodes with edges
```

### Raw Cypher Support

For queries not yet expressible in the DSL, use raw Cypher:

```swift
let result = try await graph.raw("""
    MATCH (u:User)-[:FOLLOWS]->(f:User)
    WHERE u.name = $name
    RETURN f
    """, bindings: ["name": "Alice"])
let followers = try result.map(to: User.self)
```

### Transactions

```swift
try await graph.withTransaction { tx in
    let user = User(name: "Charlie", age: 28)
    try tx.save(user)
    
    // Use Query DSL within transactions
    try tx.query {
        Create.edge(Follows.self, 
            from: User.match().where(\.id == currentUserId),
            to: User.match().where(\.id == user.id)
        )
    }
    
    // Automatic rollback on error
    guard user.age >= 18 else {
        throw ValidationError.tooYoung
    }
}
```

### Property Attributes

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

## Advanced Features

### SwiftUI Integration

```swift
struct UserListView: View {
    @State private var users: [User] = []
    @State private var searchText = ""
    
    var body: some View {
        List(users) { user in
            UserRow(user: user)
        }
        .searchable(text: $searchText)
        .onChange(of: searchText) { _, query in
            Task {
                await searchUsers(query)
            }
        }
    }
    
    func searchUsers(_ query: String) async {
        let graph = try? await GraphDatabase.shared.context()
        users = try? await graph?.query {
            User.match()
                .where(\.name.contains(query))
                .limit(50)
        } ?? []
    }
}
```

## Real-World Examples

### Social Network

```swift
// Find mutual friends
let mutualFriends = try await graph.query {
    let user1 = User.match().where(\.id == userId1)
    let user2 = User.match().where(\.id == userId2)
    let mutual = User.match(alias: "mutual")
    
    Follows.match().from(user1).to(mutual)
    Follows.match().from(user2).to(mutual)
    
    Collect(nodeRef: mutual)
}

// Find influencers
let influencers = try await graph.query {
    let user = User.match(alias: "u")
    let follower = User.match(alias: "follower")
    
    Follows.match().from(follower).to(user)
    
    Count<User>(nodeRef: follower)
        .groupBy(user)
        .having(count > 1000)
        .orderBy(.descending)
}
```

### E-Commerce

```swift
// Product recommendations
let recommendations = try await graph.query {
    let product = Product.match().where(\.id == productId)
    let buyer = User.match(alias: "buyer")
    let otherProduct = Product.match(alias: "other")
        .where(\.id != productId)
    
    Purchase.match().from(buyer).to(product)
    Purchase.match().from(buyer).to(otherProduct)
    
    Collect(nodeRef: otherProduct)
        .groupBy(otherProduct)
        .orderBy(count, .descending)
        .limit(10)
}
```

### Content Management

```swift
// Find related articles
let related = try await graph.query {
    let article = Article.match().where(\.id == articleId)
    let tag = Tag.match(alias: "tag")
    let relatedArticle = Article.match(alias: "related")
        .where(\.id != articleId)
    
    HasTag.match().from(article).to(tag)
    HasTag.match().from(relatedArticle).to(tag)
    
    Count<Tag>(nodeRef: tag)
        .groupBy(relatedArticle)
        .orderBy(count, .descending)
        .limit(5)
}
```

## Performance Tips

1. **Use Indexes**: Add `@Index` to frequently queried properties
2. **Batch Operations**: Use `ForEachQuery` for bulk operations
3. **Limit Results**: Always use `.limit()` for large datasets
4. **Transactions**: Group related operations for better performance
5. **Connection Pooling**: Automatically managed with configurable parameters

## Configuration

```swift
// Default configuration - works out of the box
let graph = try await GraphDatabase.shared.context()

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

## Testing

```swift
// Automatically uses in-memory database in tests
@Test
func testUserCreation() async throws {
    let graph = try await GraphDatabase.test.context()
    
    let user = User(name: "Test", age: 25)
    try await graph.save(user)
    
    let fetched = try await graph.fetchOne(User.self, id: user.id)
    #expect(fetched?.name == "Test")
}
```

## Type Conversions

The library handles type conversions automatically:

- **UUID** ↔ String
- **Date** ↔ Timestamp (ISO8601)
- **Int** ↔ Int64
- **Double** ↔ Float
- **Arrays & Dictionaries** - Automatic encoding/decoding
- **Optional types** - Automatic wrapping/unwrapping

## Error Handling

```swift
do {
    let results = try await graph.query { /* ... */ }
} catch KuzuError.compilationFailed(let query, let reason) {
    print("Query compilation failed: \(reason)")
} catch KuzuError.noResults {
    print("No results found")
} catch GraphError.transactionFailed(let reason) {
    print("Transaction failed: \(reason)")
}
```

## Requirements

- Swift 6.2+
- macOS 14+, iOS 17+, tvOS 17+, watchOS 10+
- Xcode 16+

## Documentation

- [API Documentation](https://github.com/1amageek/kuzu-swift-extension/wiki)
- [SPECIFICATION.md](SPECIFICATION.md) - Complete feature specification
- [API_STATUS.md](API_STATUS.md) - API stability tracking

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License

## Acknowledgments

Built on [Kuzu](https://kuzudb.com) embedded graph database and its [Swift bindings](https://github.com/kuzudb/kuzu-swift).