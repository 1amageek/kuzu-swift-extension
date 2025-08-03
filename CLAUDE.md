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