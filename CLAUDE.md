# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Swift extension library for [kuzu-swift](https://github.com/kuzudb/kuzu-swift) that provides a declarative, type-safe interface for working with the Kuzu graph database. The library implements a comprehensive DSL for graph operations, automatic schema management, and Swift-native query building.

## Architecture Overview

The library follows a clean 5-layer architecture:

1. **Model Declaration Layer (Macros)** - `@GraphNode`, `@GraphEdge` annotations that generate schema definitions
2. **Schema Generation & Migration Layer** - Automatic DDL generation and migration from Swift models
3. **Persistence Layer** - `GraphConfiguration`, `GraphContainer`, `GraphContext` for managing connections
4. **Query System Layer** - Type-safe DSL that compiles to Cypher queries with parameter binding
5. **Result Processing Layer** - `KuzuEncoder`/`KuzuDecoder`, `ResultMapper` for type conversions

## Key Components

### Model System
- Models are structs annotated with `@GraphNode` or `@GraphEdge(from:to:)`
- Properties use `@ID`, `@Index`, `@Vector`, `@FullTextSearch`, `@Timestamp` annotations
- Macros generate `_kuzuDDL` and `_kuzuColumns` static properties conforming to `_KuzuGraphModel`

### Query DSL
- `GraphContext.query { }` accepts a `@QueryBuilder` closure
- Compiles Swift expressions to Cypher queries with parameter binding
- Supports `Create`, `Match`, `Set`, `Delete`, `Return`, `Where` clauses
- Type-safe predicates using KeyPaths with `PropertyPath<Model>`
- Comparison operators: `==`, `!=`, `<`, `>`, `<=`, `>=`
- String operators: `contains`, `startsWith`, `endsWith`
- Logical operators: `&&`, `||`, `!`

### Query Support

#### Raw Queries
- `GraphContext.raw(_:bindings:)` for direct Cypher execution
- Parameter binding via dictionary of `Sendable` values

#### Transaction Support
- `GraphContext.withTransaction { txCtx in }` for ACID transactions
- `TransactionalGraphContext` provides synchronous operations within transactions
- Automatic rollback on errors
- Single connection per transaction for consistency

## Commands

```bash
# Build the package
swift build

# Run tests
swift test

# Run a specific test class
swift test --filter TestClassName

# Run a specific test method
swift test --filter TestClassName/testMethodName

# Build for release
swift build -c release

# Generate documentation
swift package generate-documentation

# Update dependencies
swift package update

# Run lint (if configured)
npm run lint

# Run type check (if configured)
npm run typecheck

# Run SwiftLint or similar tools
swift run swiftlint
```

## Build Notes

### Build Time Optimization

The kuzu-swift dependency contains a large C++ codebase that takes significant time to compile. To optimize development workflow:

1. **Initial Build**: The first build will take several minutes due to compiling the Kuzu C++ library
2. **Incremental Builds**: Subsequent builds are faster as only changed Swift files need recompilation
3. **Test Execution**: 
   - Run specific test suites to avoid full rebuilds: `swift test --filter TestClassName`
   - For rapid iteration, consider using Xcode which caches build artifacts more efficiently
4. **CI/CD**: Allow sufficient time for builds in CI pipelines (typically 5-10 minutes for full build)

### Common Build Issues

- **Memory Usage**: The C++ compilation can use significant memory. Ensure at least 8GB RAM available.
- **Binary Downloads**: Set environment variables for pre-built binaries if available:
  ```bash
  export KUZU_USE_BINARY=1
  export KUZU_BINARY_URL="https://github.com/1amageek/kuzu-swift/releases/download/v0.11.1/Kuzu.xcframework.zip"
  export KUZU_BINARY_CHECKSUM="b13968dea0cc5c97e6e7ab7d500a4a8ddc7ddb420b36e25f28eb2bf0de49c1f9"
  ```

## Development Notes

### Macro Development
- Macro implementations are in `Sources/KuzuSwiftMacrosPlugin/`
- Macro declarations are in `Sources/KuzuSwiftMacros/`
- Test macros using `SwiftSyntaxMacrosTestSupport`

### Kuzu Swift SDK Integration
- The library depends on `https://github.com/kuzudb/kuzu-swift`
- Core Kuzu types: `Database`, `Connection`, `QueryResult`, `PreparedStatement`
- Database can be in-memory (`:memory:`) or file-based

### Concurrency Model
- `GraphContext` is an actor for thread-safe operations
- `GraphContainer` is an actor managing connection pooling
- `ConnectionPool` handles connection lifecycle with timeout support
- `TransactionalGraphContext` is a value type (struct) for transaction operations
- All types conform to `Sendable` for Swift concurrency

### Error Handling
- All public APIs throw errors
- Primary error type: `GraphError` with 16 distinct cases
- Errors conform to `LocalizedError` with recovery suggestions
- Common errors: `connectionTimeout`, `transactionFailed`, `invalidConfiguration`

## Testing Strategy

- Unit tests for macro expansion
- Integration tests with in-memory Kuzu database
- Query DSL compilation tests
- Migration scenario tests

### Test Execution Notes

Due to the large C++ codebase in kuzu-swift, running tests can be time-consuming:

1. **Full Test Suite**: Can take 5-10 minutes on first run
2. **Specific Test Classes**: Use `swift test --filter TestClassName` to run only specific test classes
3. **Individual Tests**: Use `swift test --filter TestClassName/testMethodName` for even more granular testing
4. **Recommended Workflow**: During development, run only the relevant test class or method to save time

## Important Implementation Details

### Schema Migration
- Non-destructive migrations are default (`MigrationPolicy.safeOnly`)
- Destructive migrations require explicit `.allowDestructive`
- All DDL executed in single transaction

### Query Compilation
- DSL expressions compile to parameterized Cypher
- Type checking happens at Swift compile time via macros
- Runtime validation for parameter binding

### Extension Management
- Vector/FTS extensions loaded via `GraphConfiguration.options.extensions`
- Automatic `INSTALL`/`LOAD` on container initialization

### Type Conversions

The library handles type conversions between Swift and Kuzu in several places:

#### KuzuEncoder (Swift → Kuzu)
- UUID → String (via `uuid.uuidString`)
- Date → Timestamp (ISO8601 or epoch-based)
- Data → Base64 String or custom encoding
- Arrays and Dictionaries are recursively encoded

#### KuzuDecoder (Kuzu → Swift)
Supports flexible numeric conversions:
- Int64 ↔ Int
- Double → Float
- Int → Float
- Int64 → Float
- Automatic handling of Kuzu's numeric types

#### ResultMapper (Query Results → Swift)
Similar conversions as KuzuDecoder, particularly important for:
- `count()` functions return Int64 from Kuzu
- Numeric type flexibility for query results

### Common Issues and Solutions

1. **UUID Parameter Errors**
   - Error: `valueConversionFailed("Unsupported Swift type UUID")`
   - Solution: KuzuEncoder.encodeValue converts UUID to String automatically

2. **Count Query Type Mismatch**
   - Error: `typeMismatch(expected: "Optional<Int>", actual: "Int64")`
   - Solution: Use `Int64` for count results: `result.mapFirst(to: Int64.self)`

3. **Array/Dictionary Encoding**
   - Issue: Arrays and dictionaries returning nil when encoded
   - Solution: Use reference-based storage wrappers (_StorageRef, _DictStorageRef)

4. **Numeric Type Conversions**
   - Issue: Type mismatches between Swift numeric types and Kuzu
   - Solution: Both KuzuDecoder and ResultMapper support bidirectional conversions

5. **Reserved Keywords in Cypher**
   - Error: `Parser exception: mismatched input 'exists'`
   - Solution: Avoid reserved keywords like `exists` as aliases, use `result` instead

6. **Transaction Rollback**
   - Issue: Each operation using different connection
   - Solution: Use `GraphContext.withTransaction` for proper transaction scope

## Recent API Changes

### Transaction API Consolidation (Latest)
- **Removed**: `rawTransaction`, `transactionValue`, `transactionArray`, `transaction` (QueryBuilder overloads)
- **Unified API**: Use `GraphContext.withTransaction { txCtx in }` for all transaction needs
- **Internal**: `GraphContainer.withTransaction` is now internal (use GraphContext API)

### TransactionalGraphContext Design
- Changed from `actor` to `struct` for value semantics
- Synchronous operations (no `async`) to match Kuzu's synchronous Connection API
- Single connection per transaction for ACID guarantees
- Proper parameter encoding with `KuzuEncoder`

### Code Quality Tools

When making changes, ensure code quality by running:
- Lint checks (if configured in the project)
- Type checking for Swift code
- Test coverage for new functionality

The project should pass all quality checks before committing changes.