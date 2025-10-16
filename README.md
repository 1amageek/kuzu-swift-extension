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

**Choose the right library for your project:**

```swift
// For SwiftUI projects
.product(name: "KuzuSwiftUI", package: "kuzu-swift-extension")

// For non-SwiftUI projects (UIKit, AppKit, server-side, etc.)
.product(name: "KuzuSwiftExtension", package: "kuzu-swift-extension")
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
    var createdAt: Date = Date()
}

@GraphEdge(from: User.self, to: User.self)
struct Follows: Codable {
    var since: Date = Date()
}
```

### 2. Start Using Immediately

```swift
// Create container with models
let container = try GraphContainer(for: User.self, Post.self)

// Use context for operations
let context = container.mainContext

// Save data
let alice = User(name: "Alice", age: 30)
context.insert(alice)
try context.save()

// Query with type-safe DSL
let adults = try context.query {
    User.match().where(\.age >= 18)
}
```

## Core Features

### CRUD Operations

```swift
// Create
let user = User(name: "Bob", age: 25)
context.insert(user)
try context.save()

// Read
let users = try context.fetch(User.self)
let bob = try context.fetch(User.self, id: user.id.uuidString).first

// Update (Kuzu is immutable - delete and recreate)
context.delete(user)
let updated = User(id: user.id, name: user.name, age: 26)
context.insert(updated)
try context.save()

// Delete
context.delete(user)
try context.save()

// Count
let count = try context.count(User.self)
```

### Declarative Query DSL

The Query DSL provides comprehensive, type-safe query building. Two styles are supported:

**Style 1: Static methods (concise)**
```swift
let users = try context.query {
    User.match().where(\.age >= 18)
}
```

**Style 2: Explicit clause construction**
```swift
let users = try context.query {
    Match.node(User.self, alias: "u")
    Where(path(\User.age, on: "u") >= 18)
    Return.node("u")
}
```

Both styles are valid and can be mixed.

#### Node Operations

```swift
// Match nodes with conditions
let users = try context.query {
    User.match()
        .where(\.age >= 18)
        .orderBy(\.name)
        .limit(10)
}

// Optional match for nullable results
let maybeUsers = try context.query {
    User.optional()
        .where(\.city == "Tokyo")
}

// Create nodes declaratively
try context.query {
    Create.node(User.self, properties: [
        "name": "Charlie",
        "age": 28
    ])
}

// Merge (upsert) operations
try context.query {
    User.merge(on: \.email, equals: "alice@example.com")
        .onCreate(set: ["createdAt": Date()])
        .onMatch(set: ["lastLogin": Date()])
}
```

#### Edge Operations

```swift
// Kuzu automatically manages internal node IDs
// Edge properties should only contain relationship-specific data
@GraphEdge(from: User.self, to: Post.self)
struct Wrote: Codable {
    var createdAt: Date  // ✅ Relationship metadata only
    // ❌ Don't store: var userId, var postId (Kuzu handles internally)
}

// Create edges using connect() - recommended approach
let alice = User(name: "Alice", age: 30)
let bob = User(name: "Bob", age: 25)
context.insert(alice)
context.insert(bob)

let follows = Follows(since: Date())
context.connect(follows, from: alice, to: bob)  // Auto-extracts IDs
try context.save()

// Or specify IDs manually
context.connect(follows, from: alice.id.uuidString, to: bob.id.uuidString)

// Disconnect edges
context.disconnect(follows, from: alice, to: bob)
try context.save()

// Using Query DSL for complex edge operations
try context.query {
    let alice = User.match().where(\.name == "Alice")
    let bob = User.match().where(\.name == "Bob")

    Create.edge(Follows.self, from: alice, to: bob, properties: [
        "since": Date()
    ])
}

// Match edges with conditions
let followers = try context.query {
    let user = User.match().where(\.id == userId)
    Follows.match()
        .from(User.match())
        .to(user)
        .where("since", .greaterThan, oneMonthAgo)
}
```

#### Aggregations

```swift
// Count
let userCount = try context.query {
    Count<User>(nodeRef: User.match())
}

// Average
let avgAge = try context.query {
    Average(nodeRef: User.match(), keyPath: \User.age)
}

// Sum
let totalLikes = try context.query {
    Sum(Post.match(), keyPath: \Post.likes)
}

// Min/Max
let oldest = try context.query {
    Max(nodeRef: User.match(), keyPath: \User.age)
}

// Collect nodes into array
let allUsers = try context.query {
    Collect(nodeRef: User.match())
}
```

#### Complex Queries

```swift
// Multiple operations in one query
try context.query {
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
try context.query {
    ForEachQuery(queries)
}
```

### Tuple Queries with Parameter Packs

The library uses Swift 6.2's parameter pack features for type-safe tuple queries:

```swift
// Single component - returns the component's Result type
let users: [User] = try context.query {
    User.match().where(\.active == true)
}

// Two components - returns a tuple (T1.Result, T2.Result)
let (users, posts) = try context.query {
    User.match().where(\.active == true)
    Post.match().where(\.published == true)
}

// Three or more components - returns an expanded tuple
let (users, posts, comments) = try context.query {
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
// raw() is synchronous - no await needed
let result = try context.raw("""
    MATCH (u:User)-[:FOLLOWS]->(f:User)
    WHERE u.name = $name
    RETURN f
    """, bindings: ["name": "Alice"])
let followers = try result.map(to: User.self)
```

### Transactions

```swift
try context.transaction {
    let user = User(name: "Charlie", age: 28)
    context.insert(user)

    // Create edges within transaction
    let follows = Follows(since: Date())
    context.connect(follows, from: currentUser, to: user)

    // Automatic save and rollback on error
    guard user.age >= 18 else {
        throw ValidationError.tooYoung
    }
}
```

### Property Attributes

All available property macros and their usage:

#### Core Macros

**@ID** - PRIMARY KEY with automatic Hash index
```swift
@ID var id: UUID = UUID()          // Hash indexed, O(1) lookup
@ID var email: String              // PRIMARY KEY can be any type
```

**@Default(value)** - Default value constraint
```swift
@Default("draft") var status: String
@Default(0) var points: Int
```

**@Transient** - Exclude from database persistence
```swift
@Transient
var displayName: String {          // Computed property, not stored
    "\(firstName) \(lastName)"
}
```

#### Indexing Macros

**@Vector(dimensions:metric:)** - HNSW index for similarity search
```swift
@Vector(dimensions: 384) var embedding: [Float]                    // L2 distance (default)
@Vector(dimensions: 1536, metric: .cosine) var embedding: [Double] // Cosine similarity
@Vector(dimensions: 512, metric: .innerProduct) var vec: [Float]   // Inner product

// Supported metrics: .l2, .cosine, .innerProduct
```

**@Attribute(.spotlight)** - Full-Text Search index
```swift
@Attribute(.spotlight) var content: String     // BM25-based full-text search
@Attribute(.spotlight) var description: String // Automatic stemming and stopword removal
```

#### Column Name Mapping

Use Swift's standard `CodingKeys` enum to map property names to database column names:

```swift
@GraphNode
struct User: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case userName = "user_name"  // Maps to DB column "user_name"
        case emailAddress = "email"   // Maps to DB column "email"
    }

    @ID var id: String
    var userName: String      // Swift property name
    var emailAddress: String  // Swift property name
}
```

#### Complete Example

```swift
@GraphNode
struct Article: Codable {
    @ID var id: UUID = UUID()                                      // PRIMARY KEY (Hash indexed)
    var title: String                                               // Regular property (no index)
    @Attribute(.spotlight) var content: String                      // Full-Text Search index
    @Vector(dimensions: 1536, metric: .cosine) var embedding: [Double]  // HNSW index
    @Default("draft") var status: String                            // Default value
    var createdAt: Date = Date()                                    // Regular Date property

    @Transient
    var displayTitle: String {                                      // Excluded from persistence
        title.uppercased()
    }
}
```

#### Kuzu Index Limitations

Kuzu **only** supports these 3 index types:
1. **PRIMARY KEY** (Hash) - via `@ID`
2. **Vector** (HNSW) - via `@Vector`
3. **Full-Text Search** - via `@Attribute(.spotlight)`

For frequently queried columns, consider:
- Using them as `@ID` (PRIMARY KEY)
- Modeling as graph relationships for fast traversal
- Accepting full table scan for non-indexed queries

For timestamps, use regular Date properties with default values:
```swift
var createdAt: Date = Date()  // Set at initialization
var updatedAt: Date = Date()  // Update manually when needed
```

#### Index Performance Characteristics

- **PRIMARY KEY (@ID)**: O(1) Hash index lookup
- **Vector (@Vector)**: HNSW index for approximate nearest neighbor search
- **Full-Text (@Attribute(.spotlight))**: BM25 ranking for text search
- **Other properties**: Full table scan (no B-tree indexes available)

For frequently queried non-PRIMARY KEY columns, consider:
- Using them as PRIMARY KEY if possible
- Modeling as graph edges for fast traversal
- Accepting full table scan for infrequent queries

## Extension Support

All extensions (Vector, Full-Text Search, JSON) are statically linked in kuzu-swift and available by default on all platforms. No configuration required.

### Vector Operations

Vector columns use HNSW indexes for similarity search:

```swift
@GraphNode
struct Photo: Codable {
    @ID var id: String
    @Vector(dimensions: 512) var embedding: [Float]
}

// HNSW index is automatically created
// Use vector search functions in queries
let similar = try context.raw("""
    CALL QUERY_VECTOR_INDEX('Photo', 'photo_embedding_idx',
        CAST($query AS FLOAT[512]), 10)
    RETURN node, distance ORDER BY distance
    """, bindings: ["query": queryVector])
```

⚠️ **Known Limitation**: HNSW index has a batch insert issue (race condition in CSR array). The library automatically uses sequential execution for `@Vector` properties to prevent crashes (20-30% slower but safe).

## Advanced Features

### SwiftUI Integration

The `KuzuSwiftUI` library provides SwiftData-style SwiftUI integration with environment-based container injection.

#### Setup

```swift
import SwiftUI
import KuzuSwiftUI  // Automatically imports KuzuSwiftExtension

@main
struct MyApp: App {
    let container = try! GraphContainer(for: User.self, Post.self, Follows.self)

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .graphContainer(container)  // Inject container into environment
    }
}
```

#### Using in Views

```swift
import SwiftUI
import KuzuSwiftUI

struct ContentView: View {
    @Environment(\.graphContext) var context  // Access injected context
    @State private var users: [User] = []

    var body: some View {
        List(users) { user in
            Text(user.name)
        }
        .task {
            loadUsers()
        }
    }

    func loadUsers() {
        do {
            users = try context.fetch(User.self)
        } catch {
            print("Error loading users: \(error)")
        }
    }
}
```

#### Creating and Saving Data

```swift
struct AddUserView: View {
    @Environment(\.graphContext) var context
    @State private var name = ""
    @State private var age = 0

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("Age", value: $age, format: .number)

            Button("Save") {
                saveUser()
            }
            .disabled(!context.hasChanges)  // Enable only when there are changes
        }
    }

    func saveUser() {
        let user = User(name: name, age: age)
        context.insert(user)
        try? context.save()
    }
}
```

#### Full Example with Search

```swift
struct UserListView: View {
    @Environment(\.graphContext) var context
    @State private var users: [User] = []
    @State private var searchText = ""

    var body: some View {
        List(users) { user in
            UserRow(user: user)
        }
        .searchable(text: $searchText)
        .onChange(of: searchText) { _, query in
            searchUsers(query)
        }
        .task {
            loadAllUsers()
        }
    }

    func loadAllUsers() {
        do {
            users = try context.fetch(User.self)
        } catch {
            print("Error: \(error)")
        }
    }

    func searchUsers(_ query: String) {
        guard !query.isEmpty else {
            loadAllUsers()
            return
        }

        do {
            users = try context.fetch(User.self, where: "name", equals: query)
        } catch {
            print("Error: \(error)")
        }
    }
}
```

#### Available Environment Values

```swift
// Access the container
@Environment(\.graphContainer) var container: GraphContainer?

// Access the main context (@MainActor bound)
@Environment(\.graphContext) var context: GraphContext
```

#### Change Tracking with SwiftUI

```swift
struct EditorView: View {
    @Environment(\.graphContext) var context
    @State private var user: User

    var body: some View {
        Form {
            TextField("Name", text: $user.name)
            TextField("Age", value: $user.age, format: .number)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    try? context.save()
                }
                .disabled(!context.hasChanges)
            }
        }
        .onChange(of: user) { oldValue, newValue in
            context.delete(oldValue)
            context.insert(newValue)
        }
    }
}
```

## Real-World Examples

### Social Network

```swift
// Find mutual friends
let mutualFriends = try context.query {
    let user1 = User.match().where(\.id == userId1)
    let user2 = User.match().where(\.id == userId2)
    let mutual = User.match(alias: "mutual")

    Follows.match().from(user1).to(mutual)
    Follows.match().from(user2).to(mutual)

    Collect(nodeRef: mutual)
}

// Find influencers
let influencers = try context.query {
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
let recommendations = try context.query {
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
let related = try context.query {
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

⚠️ **Important**: Kuzu supports only 3 index types: PRIMARY KEY (Hash), Vector (HNSW), and Full-Text Search.

1. **Use PRIMARY KEY for lookups**: Use `@ID` on frequently queried properties (Hash indexed, O(1) lookup)
2. **Use Vector indexes**: Add `@Vector(dimensions: n)` for similarity search with HNSW
3. **Use Full-Text Search**: Add `@Attribute(.spotlight)` for text search with BM25 ranking
4. **Batch Operations**: Use `ForEachQuery` for bulk operations
5. **Limit Results**: Always use `.limit()` for large datasets
6. **Transactions**: Group related operations for better performance
7. **Accept full scans**: Non-indexed properties require full table scan (no B-tree indexes)

## Configuration

```swift
// SwiftData-style: Create container with models
let container = try GraphContainer(for: User.self, Post.self)

// Use mainContext (recommended for UI code, @MainActor bound)
let context = container.mainContext

// Or create context manually (for background tasks)
let context = GraphContext(container)

// Custom configuration
let config = GraphConfiguration(
    databasePath: "/custom/path/graph.db",
    options: GraphConfiguration.Options(
        maxConnections: 10,
        connectionTimeout: 30.0
    )
)
let container = try GraphContainer(
    for: User.self, Post.self,
    configuration: config
)
```

## Testing

```swift
// Use in-memory database for tests
@Test
func testUserCreation() throws {
    let config = GraphConfiguration(databasePath: ":memory:")
    let container = try GraphContainer(for: User.self, configuration: config)
    let context = container.mainContext

    let user = User(name: "Test", age: 25)
    context.insert(user)
    try context.save()

    let fetched = try context.fetchOne(User.self, id: user.id)
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
    let results = try context.query { /* ... */ }
} catch KuzuError.compilationFailed(let query, let reason) {
    print("Query compilation failed: \(reason)")
} catch KuzuError.noResults {
    print("No results found")
} catch KuzuError.transactionFailed(let reason) {
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
