# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Swift extension library for [kuzu-swift](https://github.com/kuzudb/kuzu-swift) that provides a declarative, type-safe interface for working with the Kuzu graph database. The library implements a comprehensive DSL for graph operations, automatic schema management, and Swift-native query building.

## Architecture Overview

The library is structured in layers:

1. **Model Declaration Layer (Macros)** - `@GraphNode`, `@GraphEdge` annotations that generate schema definitions
2. **Schema Generation & Migration Layer** - Automatic DDL generation and migration from Swift models
3. **Persistence Layer** - `GraphConfiguration`, `GraphContainer`, `GraphContext` for managing connections
4. **Query System** - Type-safe DSL that compiles to Cypher queries
5. **Graph Extensions** - Path traversal, shortest path algorithms, etc.

## Key Components

### Model System
- Models are structs annotated with `@GraphNode` or `@GraphEdge(from:to:)`
- Properties use `@ID`, `@Index`, `@Vector`, `@FTS`, `@Timestamp` annotations
- Macros generate `_kuzuDDL` and `_kuzuColumns` static properties conforming to `_KuzuGraphModel`

### Query DSL
- `GraphContext.query { }` accepts a `@QueryBuilder` closure
- Compiles Swift expressions to Cypher queries with parameter binding
- Supports `Create`, `Match`, `Set`, `Delete`, `Return` clauses
- Type-safe predicates using KeyPaths

### Raw Query Support
- `GraphContext.raw(_:bindings:)` for direct Cypher execution
- Parameter binding via dictionary of `Encodable` values

## Commands

```bash
# Build the package
swift build

# Run tests
swift test

# Run a specific test
swift test --filter TestName

# Build for release
swift build -c release

# Generate documentation
swift package generate-documentation

# Update dependencies
swift package update
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
- Multiple `Connection` instances can be managed per `GraphContainer`
- Transactions are serialized on the actor's executor

### Error Handling
- All public APIs throw errors
- Error types: `GraphError`, `QueryError`
- Errors conform to `LocalizedError`

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