# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Status: Beta 2**

A Swift extension library for [kuzu-swift](https://github.com/kuzudb/kuzu-swift) that provides a declarative, type-safe interface for working with the Kuzu graph database. The library implements a comprehensive DSL for graph operations, automatic schema management, and Swift-native query building.

⚠️ **Note**: This is beta software. APIs may change between releases. Always check SPECIFICATION.md and API_STATUS.md for current feature status.

## Architecture Overview

The library follows a clean layered architecture:

1. **Model Declaration Layer** - `@GraphNode`, `@GraphEdge` annotations that generate schema definitions
2. **Schema Generation Layer** - Automatic DDL generation and migration from Swift models
3. **Persistence Layer** - `GraphConfiguration`, `GraphContainer`, `GraphContext` for managing connections
4. **Query DSL Layer** - Type-safe DSL that compiles to Cypher queries with parameter binding
5. **Result Processing Layer** - `KuzuEncoder`/`KuzuDecoder`, `ResultMapper` for type conversions
6. **SwiftUI Integration Layer** - `KuzuSwiftUI` library for SwiftData-style SwiftUI integration (optional)

## Extension Support

All extensions (Vector, Full-Text Search, JSON) are **statically linked** in kuzu-swift and available by default on all platforms. No configuration or loading required.

### Vector Extension
The vector extension is statically linked in kuzu-swift, providing:
- Vector data storage with `FLOAT[n]` or `DOUBLE[n]` types
- HNSW index support for similarity search
- Built-in vector functions
- Full support on all platforms (iOS/tvOS/watchOS/macOS)

### Vector Operations Syntax
```swift
// Create table with vector column
CREATE NODE TABLE items(
    id INT64 PRIMARY KEY,
    embedding FLOAT[384]  // Use FLOAT[] for vectors
)

// Create HNSW index
CALL CREATE_VECTOR_INDEX('items', 'embedding_idx', 'embedding',
    metric := 'l2')

// Vector similarity search
CALL QUERY_VECTOR_INDEX('items', 'embedding_idx',
    CAST([0.1, 0.2, ...] AS FLOAT[384]), 10)
RETURN node, distance ORDER BY distance

// Built-in functions
array_cosine_similarity(vec1, vec2)
array_distance(vec1, vec2)  // L2 distance
array_inner_product(vec1, vec2)
```

## Kuzu Index and Constraint Limitations

⚠️ **IMPORTANT**: Kuzu has significant limitations on indexes and constraints. Understanding these is critical for proper data modeling.

### ✅ Supported Indexes and Constraints

| Feature | Macro | Database Effect | Performance |
|---------|-------|-----------------|-------------|
| **PRIMARY KEY** | `@ID` | Hash Index automatically created | ✅ Fast lookups |
| **DEFAULT Values** | `@Default(value)` | Default constraint in DDL | ✅ Works as expected |
| **Vector Index (HNSW)** | `@Vector(dimensions: n)` | HNSW index automatically created | ✅ Fast similarity search |
| **Full-Text Search** | `@Attribute(.spotlight)` | Full-Text Search index automatically created | ✅ Fast text search |

### ❌ NOT Supported (Kuzu Database Limitations)

| Feature | Status | Impact |
|---------|--------|--------|
| **Regular Indexes** | ❌ Not supported | Non-PRIMARY-KEY columns use **full table scan** |
| **UNIQUE Constraints** | ❌ Only on PRIMARY KEY | Cannot enforce uniqueness on other columns |
| **Multiple PRIMARY KEYs** | ❌ One per table | Composite keys not supported |
| **B-tree Indexes** | ❌ Not supported | Only Hash (PRIMARY KEY), HNSW (Vector), Full-Text Search |

### Performance Implications

```swift
// ✅ FAST: PRIMARY KEY lookup (Hash Index)
@GraphNode
struct User: Codable {
    @ID var email: String  // Indexed, fast lookups
    var name: String
}
// Query: WHERE u.email = 'alice@example.com' → O(1) lookup

// ❌ SLOW: Regular property filtering (Full Table Scan)
@GraphNode
struct User: Codable {
    @ID var id: Int
    var age: Int  // NOT indexed, slow queries!
}
// Query: WHERE u.age > 30 → O(n) full scan
```

### Recommended Patterns

#### ✅ Good: Use PRIMARY KEY for frequently queried properties
```swift
@GraphNode
struct User: Codable {
    @ID var email: String  // Email as PRIMARY KEY → indexed + unique
    var name: String
}
```

#### ✅ Good: Use Vector Index for similarity search
```swift
@GraphNode
struct Photo: Codable {
    @ID var id: String
    @Vector(dimensions: 512) var embedding: [Float]  // HNSW index created
}
```

#### ✅ Good: Use Full-Text Search Index for text search
```swift
@GraphNode
struct Article: Codable {
    @ID var id: Int
    @Attribute(.spotlight) var content: String  // Full-Text Search index created
}

// Search
CALL QUERY_FTS_INDEX('Article', 'article_content_fts_idx', 'quantum computing')
```

#### ❌ Bad: Expecting indexes on regular properties
```swift
@GraphNode
struct Product: Codable {
    @ID var id: Int
    var category: String  // ❌ No index! Queries will be slow
    var price: Double     // ❌ No index! Range queries will be slow
}

// ❌ SLOW: Full table scan for every query
// WHERE p.category = 'Electronics'  → scans all rows
// WHERE p.price > 100               → scans all rows
```

#### ⚠️ Workaround: Denormalize or use edges for filtering
```swift
// Option 1: Use PRIMARY KEY for main filter
@GraphNode
struct Product: Codable {
    @ID var category: String  // Category as PRIMARY KEY
    var name: String
    var price: Double
}

// Option 2: Model as relationships
@GraphNode
struct Category: Codable {
    @ID var name: String
}

@GraphNode
struct Product: Codable {
    @ID var id: Int
    var name: String
}

@GraphEdge(from: Product.self, to: Category.self)
struct BelongsTo: Codable {}

// Query: Fast category filtering via graph traversal
// MATCH (p:Product)-[:BelongsTo]->(c:Category {name: 'Electronics'})
```

### UNIQUE Constraint Limitations

Kuzu **ONLY** supports UNIQUE on PRIMARY KEY. For other columns:

```swift
// ✅ SOLUTION: Use email as PRIMARY KEY
@GraphNode
struct User: Codable {
    @ID var email: String  // PRIMARY KEY → automatically UNIQUE + indexed
    var name: String
}

// ⚠️ If you need multiple unique columns, enforce at application level:
func insertUser(_ user: User, context: GraphContext) throws {
    // Check uniqueness manually
    let existing = try context.raw("MATCH (u:User {email: $email}) RETURN u",
                                    bindings: ["email": user.email])
    if existing.hasNext() {
        throw UserError.duplicateEmail
    }
    context.insert(user)
}
```

### Migration from Other Databases

If migrating from SQL or SwiftData that use secondary indexes:

1. **Identify frequently queried columns** → Make them PRIMARY KEY or use graph edges
2. **Text search needs** → Use `@Attribute(.spotlight)` for Full-Text Search
3. **Similarity search** → Use `@Vector` for embeddings
4. **Other filters** → Accept full table scan or denormalize data
5. **UNIQUE requirements** → Use PRIMARY KEY or implement application-level validation

## Key Components

### Model System
- Models are structs annotated with `@GraphNode` or `@GraphEdge(from:to:)`
- Properties use `@ID`, `@Vector`, `@Attribute`, `@Default`, `@Transient` annotations
- Macros generate `_kuzuDDL`, `_kuzuColumns`, and `_metadata` static properties conforming to `_KuzuGraphModel`
- Property macros use a shared `BasePropertyMacro` protocol for consistency
- `_metadata` contains index information for Vector and Full-Text Search indexes only

### GraphEdge Definition
- Edge types use `@GraphEdge(from: NodeType.self, to: NodeType.self)` syntax
- Generic constraints ensure `From` and `To` are `GraphNodeModel` types (compile-time safety)
- Edges are created via `context.connect()` - **not** `context.insert()`
- Kuzu automatically maintains internal source/target node IDs (KuzuInternalId)
- Edge properties should only contain relationship-specific data (timestamps, weights, etc.)
- No need to store user-level node IDs in edge properties - Kuzu handles this internally

### Available Property Macros

**DB Effect (Enforced):**
- `@ID` - PRIMARY KEY with Hash index (O(1) lookup, automatic UNIQUE)
- `@Default(value)` - DEFAULT constraint in DDL
- `@Vector(dimensions:metric:)` - HNSW index for similarity search
- `@Attribute(.spotlight)` - Full-Text Search index with BM25 ranking
- `@Transient` - Exclude property from database persistence

**Column Name Mapping:**
- Use Swift's standard `CodingKeys` enum to map Swift property names to database column names
- Example:
  ```swift
  @GraphNode
  struct User: Codable {
      enum CodingKeys: String, CodingKey {
          case id
          case userName = "user_name"  // DB column: "user_name"
      }

      @ID var id: String
      var userName: String  // Swift property: userName
  }
  ```

**No DB Effect:**
- Regular Date properties (no automatic timestamp tracking)
- Manual uniqueness validation required for non-PRIMARY KEY columns

### Query DSL
- `GraphContext.query { }` accepts a `@QueryBuilder` closure
- Compiles Swift expressions to parameterized Cypher queries
- Supports `Create`, `Match`, `Set`, `Delete`, `Return`, `Where`, `With`, `Unwind` clauses
- Type-safe predicates using KeyPaths
- Optimized parameter generation with `OptimizedParameterGenerator`

### Error Handling
- Unified `KuzuError` type for all operations
- Type aliases for backward compatibility (`QueryError`, `ResultMappingError`)
- Comprehensive error cases with recovery suggestions
- All errors conform to `LocalizedError`

## Package Structure

The repository provides multiple Swift packages for different use cases:

### Core Libraries

- **KuzuSwiftExtension** - Main library with graph database functionality
  - Model declarations (`@GraphNode`, `@GraphEdge`)
  - Persistence layer (`GraphContainer`, `GraphContext`)
  - Query DSL and result mapping
  - Use this for all non-SwiftUI projects

- **KuzuSwiftUI** - SwiftUI integration library (optional)
  - SwiftData-style environment integration
  - `@Environment(\.graphContainer)` and `@Environment(\.graphContext)`
  - Scene and View modifiers (`.graphContainer()`)
  - Only import if using SwiftUI

- **KuzuSwiftMacros** - Macro definitions
  - Exports `@GraphNode`, `@GraphEdge`, property macros
  - Automatically included when using `KuzuSwiftExtension`

- **KuzuSwiftProtocols** - Protocol definitions
  - Low-level protocols used by macros
  - Rarely imported directly

### Import Guide

```swift
// For SwiftUI projects
import KuzuSwiftUI  // Includes KuzuSwiftExtension automatically

// For non-SwiftUI projects (UIKit, AppKit, server-side, etc.)
import KuzuSwiftExtension

// Rarely needed (macros are re-exported by KuzuSwiftExtension)
import KuzuSwiftMacros
```

## Commands

```bash
# Build the package
swift build

# Run tests
swift test

# Run specific test class
swift test --filter TestClassName

# Build for release
swift build -c release

# Clean build
swift package clean

# Update dependencies
swift package update
```

## Build Optimization

### Build Times
- Initial build: 5-10 minutes (compiles Kuzu C++ library)
- Incremental builds: Much faster (only Swift changes)
- Use `swift test --filter` for targeted testing

### Memory Requirements
- Minimum 8GB RAM for C++ compilation
- Use pre-built binaries when available:
```bash
export KUZU_USE_BINARY=1
export KUZU_BINARY_URL="https://github.com/1amageek/kuzu-swift/releases/download/v0.11.1/Kuzu.xcframework.zip"
export KUZU_BINARY_CHECKSUM="b13968dea0cc5c97e6e7ab7d500a4a8ddc7ddb420b36e25f28eb2bf0de49c1f9"
```

## Beta 2 Changes

### Recent API Changes (Current)
- **KuzuSwiftUI Separation** - SwiftUI integration moved to separate `KuzuSwiftUI` library
  - Core functionality (`KuzuSwiftExtension`) no longer depends on SwiftUI
  - Optional import for SwiftUI projects: `import KuzuSwiftUI`
  - Cleaner separation of concerns and reduced compile times for non-UI code
- **GraphEdge Macro Simplified** - Reverted to `@GraphEdge(from:to:)` format for clarity and Kuzu compatibility
- **New Edge Connection API** - Added `connect()`/`disconnect()` methods for explicit edge creation
  - `context.connect(_ edge, from: fromID, to: toID)` - Create edge between existing nodes
  - `context.disconnect(_ edge, from: fromID, to: toID)` - Remove edge between nodes
  - Overloads available to auto-extract IDs from node instances
- **Removed @Since/@Target Macros** - Simplified edge definition to avoid data redundancy with Kuzu's internal IDs
- **Batch Edge Operations** - Uses UNWIND pattern for efficient bulk edge creation/deletion
- **Generic Constraints on GraphEdge** - `From` and `To` parameters now require `GraphNodeModel` conformance for type safety

### New Features in Beta 2
- **Modular SwiftUI Support** - Separate `KuzuSwiftUI` library for optional SwiftUI integration
- **Enhanced ResultMapper** - Automatic KuzuNode to Swift type mapping
- **Improved Query DSL** - Added `Return.node()` for direct node returns
- **Better Node Handling** - Single column KuzuNode results are automatically decoded
- **Raw Query Improvements** - `result.map(to:)` now handles KuzuNode transparently

### Recent Code Cleanup (Beta 1)
- Removed `QueryDebug.swift` and `QueryDebuggable.swift` - unnecessary complexity
- Deleted `ParameterNameGenerator.swift` - consolidated into `OptimizedParameterGenerator`
- Removed `GraphAlgorithms.swift` - Kuzu doesn't support graph algorithms
- Unified error types into single `KuzuError`
- Consolidated property macros with shared base implementation

### Current Focus
- Stabilizing core APIs for 1.0 release
- Completing Query DSL coverage
- Improving error messages and documentation
- Enhancing type safety and developer experience

## Development Guidelines

### Macro Development
- Implementations in `Sources/KuzuSwiftMacrosPlugin/`
- Use `BasePropertyMacro` protocol for new property macros
- Test with `SwiftSyntaxMacrosTestSupport`

### Query DSL Extensions
- Add new clauses to `Sources/KuzuSwiftExtension/Query/`
- Use `OptimizedParameterGenerator` for parameter names
- Implement `QueryComponent` protocol with `toCypher()` method

### Type Conversions
- **KuzuEncoder**: UUID→String, Date→Timestamp, automatic numeric conversions
- **KuzuDecoder**: Flexible numeric conversions (Int64↔Int, Double→Float), KuzuNode handling
- **ResultMapper**: Enhanced in Beta 2 - Automatic KuzuNode property extraction and mapping

### Testing Strategy
- Unit tests for each component
- Integration tests with in-memory database
- Use `swift test --filter` during development for speed
- All tests must pass before committing
- Implement Swift Testing only

## Common Patterns

### Basic Usage (SwiftData-style)
```swift
import KuzuSwiftExtension

// Create container with models
let container = try await GraphContainer(for: User.self, Post.self)

// Use mainContext (recommended for UI code, @MainActor bound)
let context = container.mainContext

// Or create context manually (for background tasks)
let context = GraphContext(container)

// Insert and save
let user = User(name: "Alice", age: 30)
context.insert(user)
try await context.save()
```

### SwiftUI Integration
```swift
import SwiftUI
import KuzuSwiftUI  // Automatically imports KuzuSwiftExtension

@main
struct MyApp: App {
    let container = try! GraphContainer(for: User.self, Post.self)

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .graphContainer(container)
    }
}

struct ContentView: View {
    @Environment(\.graphContext) var context

    var body: some View {
        Button("Add User") {
            let user = User(name: "Alice", age: 30)
            context.insert(user)
            try? context.save()
        }
    }
}
```

### Edge Creation with connect()
```swift
// Define edge type
@GraphEdge(from: User.self, to: Post.self)
struct Wrote: Codable {
    var createdAt: Date
}

// Insert nodes first
let user = User(name: "Alice", age: 30)
let post = Post(title: "Hello World", content: "...")
context.insert(user)
context.insert(post)

// Create edge connecting the nodes
let wrote = Wrote(createdAt: Date())
context.connect(wrote, from: user, to: post)  // Auto-extracts IDs

// Or manually specify IDs
context.connect(wrote, from: user.id.uuidString, to: post.id.uuidString)

try await context.save()
```

### Disconnect edges
```swift
// Remove edge between nodes
context.disconnect(wrote, from: user, to: post)
try await context.save()
```

### Transaction Usage
```swift
try await context.transaction {
    context.insert(user1)
    context.insert(user2)
    // Automatically saved when block completes
}
```

### Change Tracking (SwiftData-compatible)
```swift
// Check for unsaved changes
if context.hasChanges {
    try await context.save()
}

// Get pending changes
let insertedModels = context.insertedModelsArray
let deletedModels = context.deletedModelsArray
let changedModels = context.changedModelsArray  // Empty in Kuzu

// SwiftUI example: Conditional save button
Button("Save") {
    try? context.save()
}
.disabled(!context.hasChanges)
```

### Notifications (SwiftData-compatible)
```swift
// Listen for save events
NotificationCenter.default.addObserver(
    forName: GraphContext.didSave,
    object: context,
    queue: nil
) { notification in
    if let userInfo = notification.userInfo,
       let insertedIds = userInfo[GraphContext.NotificationKey.insertedIdentifiers.rawValue] as? [String] {
        print("Inserted: \(insertedIds)")
    }
}

// Lifecycle-based autosave (SwiftUI)
.onReceive(NotificationCenter.default.publisher(
    for: UIApplication.willResignActiveNotification
)) { _ in
    if context.hasChanges {
        try? context.save()
    }
}

// Lifecycle-based autosave (UIKit)
func applicationWillResignActive(_ application: UIApplication) {
    if context.hasChanges {
        try? context.save()
    }
}
```

### Query DSL (Beta 2: Enhanced)
```swift
let results = try await context.queryArray(User.self) {
    Match.node(User.self, alias: "u")
    Where(path(\User.age, on: "u") > 25)
    Return.node("u")  // Beta 2: Direct node returns now supported
}
```

### Raw Cypher (Beta 2: Enhanced)
```swift
// raw() is synchronous - no await needed
let result = try context.raw(
    "MATCH (u:User) WHERE u.age > $minAge RETURN u",
    bindings: ["minAge": 25]
)
// Beta 2: Automatic KuzuNode handling
let users = try result.map(to: User.self)
```

## Platform-Specific Considerations

### iOS/tvOS/watchOS
- All extensions are statically linked
- Vector, Full-Text Search, and JSON operations fully supported
- HNSW indexes work out of the box

### macOS
- Static extensions work identically to iOS
- Better performance for large datasets

## Troubleshooting

### Vector Operations
- **Vector functions not available**: Check if using correct syntax (FLOAT[] not DOUBLE[])
- **HNSW index creation fails**: Ensure column is FLOAT[n] or DOUBLE[n] type

### Type Mismatches
- Count queries return `Int64`, not `Int`
- Use flexible numeric conversion in decoders
- UUID automatically converts to/from String
- Vector columns must use fixed-size arrays: `FLOAT[384]` not `FLOAT[]`

### Reserved Keywords
- Avoid Cypher reserved words in aliases (e.g., use `result` not `exists`)
- Check Kuzu documentation for full list

### Transaction Issues
- Ensure all operations in transaction use the transaction context
- Transactions automatically rollback on error
- Don't mix transaction and non-transaction operations

## Code Quality Checklist

Before committing:
- [ ] Run `swift test` - all tests pass
- [ ] No compiler warnings
- [ ] New features have tests
- [ ] Public APIs have documentation comments
- [ ] Error cases are handled appropriately
- [ ] No unnecessary debug code or print statements

## API Stability

See [API_STATUS.md](API_STATUS.md) for detailed API stability information.

### Key Files to Reference
- `SPECIFICATION.md` - Complete feature specification
- `API_STATUS.md` - API stability tracking
- `README.md` - User-facing documentation

### When Making Changes
1. Check API_STATUS.md to understand stability level
2. Update SPECIFICATION.md if adding/changing features
3. Mark experimental features clearly
4. Don't break stable APIs without discussion
