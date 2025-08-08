# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Status: Beta 1**

A Swift extension library for [kuzu-swift](https://github.com/kuzudb/kuzu-swift) that provides a declarative, type-safe interface for working with the Kuzu graph database. The library implements a comprehensive DSL for graph operations, automatic schema management, and Swift-native query building.

⚠️ **Note**: This is beta software. APIs may change between releases. Always check SPECIFICATION.md and API_STATUS.md for current feature status.

## Architecture Overview

The library follows a clean layered architecture:

1. **Model Declaration Layer** - `@GraphNode`, `@GraphEdge` annotations that generate schema definitions
2. **Schema Generation Layer** - Automatic DDL generation and migration from Swift models  
3. **Persistence Layer** - `GraphConfiguration`, `GraphContainer`, `GraphContext` for managing connections
4. **Query DSL Layer** - Type-safe DSL that compiles to Cypher queries with parameter binding
5. **Result Processing Layer** - `KuzuEncoder`/`KuzuDecoder`, `ResultMapper` for type conversions

## Key Components

### Model System
- Models are structs annotated with `@GraphNode` or `@GraphEdge(from:to:)`
- Properties use `@ID`, `@Index`, `@Vector`, `@FullTextSearch`, `@Timestamp` annotations
- Macros generate `_kuzuDDL` and `_kuzuColumns` static properties conforming to `_KuzuGraphModel`
- Property macros use a shared `BasePropertyMacro` protocol for consistency

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

## Beta 1 Changes

### Recent Code Cleanup
- Removed `QueryDebug.swift` and `QueryDebuggable.swift` - unnecessary complexity
- Deleted `ParameterNameGenerator.swift` - consolidated into `OptimizedParameterGenerator`
- Removed `GraphAlgorithms.swift` - Kuzu doesn't support graph algorithms
- Unified error types into single `KuzuError`
- Consolidated property macros with shared base implementation

### Current Focus
- Stabilizing core APIs for 1.0 release
- Completing Query DSL coverage
- Improving error messages and documentation

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
- **KuzuDecoder**: Flexible numeric conversions (Int64↔Int, Double→Float)
- **ResultMapper**: Handles query result mapping with type flexibility

### Testing Strategy
- Unit tests for each component
- Integration tests with in-memory database
- Use `swift test --filter` during development for speed
- All tests must pass before committing

## Common Patterns

### Transaction Usage
```swift
try await graph.withTransaction { tx in
    // All operations use same connection
    try tx.save(node)
    let result = try tx.raw("MATCH (n) RETURN n")
}
```

### Query DSL
```swift
let results = try await graph.query {
    Match.node(User.self, alias: "u")
    Where(path(\.age, on: "u") > 25)
    Return.node("u")
}
```

### Raw Cypher
```swift
let result = try await graph.raw(
    "MATCH (u:User) WHERE u.age > $minAge RETURN u",
    bindings: ["minAge": 25]
)
```

## Troubleshooting

### Type Mismatches
- Count queries return `Int64`, not `Int`
- Use flexible numeric conversion in decoders
- UUID automatically converts to/from String

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