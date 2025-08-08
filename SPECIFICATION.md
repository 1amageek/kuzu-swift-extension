# Kuzu Swift Extension - Specification (Beta 1)

## Overview

This document specifies the current implementation status of kuzu-swift-extension as of Beta 1. The library provides a type-safe, declarative Swift interface for the Kuzu embedded graph database.

## Version Status

**Current Status**: Beta 1
**Stability**: API may change between beta releases
**Production Use**: Core features are stable, but evaluate carefully for production use

## Architecture

### Layer Structure

1. **Model Declaration Layer**
   - Swift Macros (`@GraphNode`, `@GraphEdge`)
   - Property annotations (`@ID`, `@Index`, `@Vector`, etc.)
   - Automatic schema generation

2. **Schema Management Layer**
   - DDL generation from Swift models
   - Migration support (safe and destructive)
   - Schema diffing and validation

3. **Persistence Layer**
   - `GraphConfiguration` - Database configuration
   - `GraphContainer` - Connection pool management
   - `GraphContext` - Main API interface (actor-based)
   - `TransactionalGraphContext` - Transaction scope

4. **Query DSL Layer**
   - Type-safe query building
   - Cypher compilation with parameter binding
   - Query component composition

5. **Result Processing Layer**
   - `KuzuEncoder` - Swift to Kuzu type conversion
   - `KuzuDecoder` - Kuzu to Swift type conversion
   - `ResultMapper` - Query result mapping

## Feature Status

### ✅ Stable Features

These features are tested and ready for use:

#### Core Operations
- `save(_:)` - Insert/update nodes and edges
- `fetch(_:)` - Retrieve all nodes of a type
- `fetchOne(_:id:)` - Retrieve single node by ID
- `fetch(_:where:equals:)` - Simple filtered queries
- `delete(_:)` - Delete nodes/edges
- `deleteAll(_:)` - Bulk deletion
- `count(_:)` - Count operations

#### Raw Cypher Execution
- `raw(_:bindings:)` - Execute raw Cypher with parameters
- Full parameter binding support
- Prepared statement caching

#### Transaction Support
- `withTransaction { }` - ACID transactions
- Automatic rollback on error
- Single connection per transaction
- Nested transaction prevention

#### Basic Query DSL
- `Match` - Node and edge pattern matching
- `Where` - Filtering with predicates
- `Create` - Node and edge creation
- `Set` - Property updates
- `Delete` - Deletion operations
- `Return` - Result specification with ordering/limiting

#### Type System
- Automatic UUID ↔ String conversion
- Date ↔ Timestamp conversion
- Flexible numeric conversions (Int, Int64, Double, Float)
- Optional type handling
- Array and Dictionary support

### 🚧 Beta Features

These features work but may have API changes:

#### Advanced Query DSL
- `With` - Query pipelining
- `Unwind` - List expansion
- `OptionalMatch` - Optional patterns
- `Merge` - Upsert operations
- `Exists` / `NotExists` - Existence checks
- `Subquery` - Nested queries
- `Call` - Procedure calls

#### Path Operations
- Variable length paths
- Path patterns
- Path functions

#### Aggregations
- `count()`, `sum()`, `avg()`, `min()`, `max()`
- Group by operations
- Having clauses

### 🧪 Experimental Features

These features are incomplete or may change significantly:

#### Complex Predicates
- Full text search predicates
- Vector similarity search
- Complex boolean expressions

#### Schema Migration
- Automatic migration detection
- Safe vs destructive migrations
- Migration rollback

### ❌ Not Implemented

These features are not available:

#### Graph Algorithms
- PageRank
- Community detection (Louvain)
- Shortest path algorithms
- Centrality measures
- **Note**: Kuzu does not yet support these algorithms

#### Advanced Cypher Features
- FOREACH loops
- CASE expressions
- List comprehensions
- Map projections

## API Reference

### GraphContext

Main entry point for database operations:

```swift
// Initialize with default configuration
let graph = try await GraphDatabase.shared.context()

// Or with custom configuration
let config = GraphConfiguration(
    databasePath: "/path/to/db",
    options: GraphConfiguration.Options(
        maxConnections: 10,
        extensions: [.fts, .vector]
    )
)
let graph = try await GraphContext(configuration: config)
```

### Model Declaration

```swift
@GraphNode
struct User: Codable {
    @ID var id: UUID = UUID()
    @Index var email: String
    var name: String
    @Timestamp var createdAt: Date = Date()
}

@GraphEdge(from: User.self, to: User.self)
struct Follows: Codable {
    @Timestamp var since: Date = Date()
}
```

### Query DSL

```swift
// Type-safe query building
let adults = try await graph.query {
    Match.node(User.self, alias: "u")
    Where(path(\.age, on: "u") > 18)
    Return.node("u")
}

// Raw Cypher
let result = try await graph.raw(
    "MATCH (u:User) WHERE u.age > $minAge RETURN u",
    bindings: ["minAge": 18]
)
```

### Transactions

```swift
try await graph.withTransaction { tx in
    let user = User(name: "Alice")
    try tx.save(user)
    
    let post = Post(authorId: user.id)
    try tx.save(post)
    
    // Automatically commits or rolls back
}
```

## Performance Characteristics

### Build Time
- Initial build: 5-10 minutes (Kuzu C++ compilation)
- Incremental builds: Fast (Swift changes only)
- Test execution: Use `--filter` for targeted testing

### Runtime Performance
- Connection pooling with configurable size (default: 10)
- Prepared statement caching
- Optimized parameter generation
- Lazy result iteration support

### Memory Usage
- Minimum 8GB RAM for compilation
- Runtime memory proportional to result set size
- Connection pool memory overhead: ~1MB per connection

## Error Handling

Unified error type `KuzuError` with cases:

### Query Errors
- `compilationFailed` - Invalid Cypher syntax
- `executionFailed` - Runtime query errors
- `bindingFailed` - Parameter binding issues

### Result Errors
- `noResults` - Empty result set
- `typeMismatch` - Type conversion failures
- `decodingFailed` - Decoding errors

### Schema Errors
- `missingRequiredProperty` - Required field missing
- `constraintViolation` - Unique/primary key violations

## Limitations

### Kuzu Limitations
- No distributed transactions
- Limited full-text search capabilities
- No graph algorithm support yet
- Maximum database size: OS file system limit

### Library Limitations
- Query DSL doesn't cover all Cypher features
- Migration system is basic
- No query plan optimization hints
- No streaming for large result sets (fully materialized)

## Testing

### Test Coverage
- 166 test cases across 17 test files
- Unit tests for all public APIs
- Integration tests with in-memory database
- Macro expansion tests

### Test Categories
- Model tests - Schema generation
- Query DSL tests - Query compilation
- Transaction tests - ACID compliance
- Type conversion tests - Encoder/decoder
- Connection pool tests - Concurrency

## Migration from Other Versions

This is Beta 1 - no migration needed from previous versions.

Future beta releases may include breaking changes. Check release notes for migration guides.

## Known Issues

1. **Build Times** - C++ compilation is slow on first build
2. **Type Conversions** - Some edge cases in numeric conversions
3. **Error Messages** - Could be more descriptive in some cases
4. **Memory Usage** - Large result sets are fully materialized

## Roadmap

### Beta 2 (Planned)
- Streaming result support
- Improved error messages
- Query DSL completion

### 1.0 Release Criteria
- Stable API
- Complete Query DSL
- Comprehensive documentation
- Performance benchmarks

## Support

- GitHub Issues: Report bugs and feature requests
- Documentation: README.md, CLAUDE.md
- Examples: See Tests directory for usage examples