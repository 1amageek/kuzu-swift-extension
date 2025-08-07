# Kuzu Swift Extension API Improvements

This document describes the recent API improvements to the Kuzu Swift Extension library.

## 1. Type-Safe Property Paths with KeyPaths

### Before
```swift
context.query {
    Match.node(User.self, alias: "u")
    Where.condition(property("u", "name") == "John")  // String-based, error-prone
    Return.node("u")
}
```

### After
```swift
context.query {
    Match.node(User.self, alias: "u")
    Where.path(\.name, on: "u") == "John"  // Type-safe with KeyPath
    Return.node("u")
}
```

### Features
- Type-safe property references using Swift KeyPaths
- Compile-time validation of property names
- Full support for comparison operators (`==`, `!=`, `<`, `>`, `<=`, `>=`)
- Additional predicates: `contains()`, `startsWith()`, `endsWith()`, `matches()`, `isNull`, `isNotNull`

## 2. Enhanced Model Attributes

### New Macros
```swift
@GraphNode
struct User {
    @ID var id: UUID
    @Unique var email: String              // Unique constraint
    @Default("active") var status: String  // Default value
    @FullTextSearch var bio: String        // Full-text search index
    @Index var username: String            // Standard index
}
```

### Available Attributes
- `@ID` - Primary key
- `@Index` - Standard database index
- `@Unique` - Unique constraint
- `@Default(value)` - Default value
- `@FullTextSearch` - Full-text search index
- `@Vector(dimensions:)` - Vector embedding
- `@Timestamp` - Auto-updated timestamp

## 3. Simplified Relationship Operations

### Creating Relationships
```swift
// Simple relationship
try await context.connect(AuthoredBy.self, from: user, to: post)

// With properties
let edge = AuthoredBy(authoredAt: Date())
try await context.connect(edge, from: user, to: post)
```

### Querying Relationships
```swift
// Find related nodes
let posts: [Post] = try await context.related(
    to: user,
    via: AuthoredBy.self,
    direction: .outgoing
)

// With edges
let results = try await context.relatedWithEdges(
    to: user,
    via: AuthoredBy.self
)
// results: [(node: Post, edge: AuthoredBy)]
```

### Deleting Relationships
```swift
// Remove specific relationship
try await context.disconnect(from: user, to: post, via: AuthoredBy.self)

// Remove all relationships
try await context.disconnectAll(from: user, edgeType: AuthoredBy.self)
```

## 4. Enhanced Result Mapping

### Simplified Decoding
```swift
// Decode from specific column
let users = try result.decode(User.self, column: "u")

// Get first result
let user = try result.first(User.self, column: "u")

// Decode node-edge pairs
let pairs = try result.decodePairs(
    nodeType: User.self,
    edgeType: AuthoredBy.self,
    nodeColumn: "u",
    edgeColumn: "e"
)
```

### Direct Type Mapping
```swift
// Map to basic types
let names = try result.mapStrings(at: 0)
let counts = try result.mapInts(at: 1)

// Fluent API
let filtered = try result
    .filter { $0["age"] as? Int ?? 0 > 18 }
    .map { $0["name"] as? String ?? "" }
```

## 5. Batch Operations

### Batch Create
```swift
let users = [user1, user2, user3]
try await context.createMany(users)
```

### Batch Update
```swift
// Update by predicate
try await context.updateMany(
    User.self,
    matching: property("u", "status") == "inactive",
    set: ["status": "active", "updatedAt": Date()]
)

// Update specific models
try await context.updateMany(users, properties: ["status", "updatedAt"])
```

### Batch Delete
```swift
// Delete by predicate
try await context.deleteMany(
    User.self,
    where: property("u", "createdAt") < oldDate
)

// Delete by IDs
try await context.deleteMany(User.self, ids: userIds)
```

### Batch Merge (Upsert)
```swift
try await context.mergeMany(
    users,
    matchOn: "email",
    onCreate: ["createdAt": Date()],
    onMatch: ["updatedAt": Date()]
)
```

## 6. Advanced Queries

### Unwind for Array Processing
```swift
context.query {
    Unwind.items(tags, as: "tag")
    Match.node(Post.self, alias: "p")
    Where.condition(property("p", "tag").contains(PropertyReference(alias: "tag", property: "")))
    Return.node("p")
}
```

### Path Queries
```swift
// Shortest path
let path = try await context.shortestPath(
    from: user1,
    to: user2,
    maxHops: 3
)

// Check connection
let connected = try await context.areConnected(
    user1,
    user2,
    via: Follows.self,
    maxHops: 2
)
```

## Migration Guide

### Updating Existing Code

1. **Property References**: Replace string-based property references with KeyPaths
2. **Relationship Operations**: Use the new helper methods instead of raw Cypher
3. **Result Mapping**: Use the enhanced decoding methods
4. **Batch Operations**: Replace loops with batch methods

### Backward Compatibility

All existing APIs remain functional. New features are additive and don't break existing code.

## Performance Considerations

- Batch operations significantly reduce round-trips to the database
- Type-safe predicates compile to efficient Cypher queries
- Connection pooling ensures efficient resource usage
- Index attributes improve query performance

## Best Practices

1. Use KeyPath-based predicates for type safety
2. Leverage batch operations for bulk data manipulation
3. Add appropriate indexes to frequently queried properties
4. Use relationship helpers for cleaner, more maintainable code
5. Take advantage of the fluent result mapping API