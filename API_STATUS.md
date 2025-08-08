# API Status (Beta 1)

This document tracks the implementation and stability status of all public APIs in kuzu-swift-extension.

## Status Legend

- ✅ **Stable** - Ready for use, unlikely to change
- 🚧 **Beta** - Working but may have breaking changes
- 🧪 **Experimental** - Early implementation, will change
- ❌ **Not Implemented** - Planned but not available

## Core APIs

### GraphContext

| API | Status | Notes |
|-----|--------|-------|
| `init(configuration:)` | ✅ | Stable |
| `raw(_:bindings:)` | ✅ | Stable |
| `save(_:)` | ✅ | Stable |
| `fetch(_:)` | ✅ | Stable |
| `fetchOne(_:id:)` | ✅ | Stable |
| `fetch(_:where:equals:)` | ✅ | Stable |
| `delete(_:)` | ✅ | Stable |
| `deleteAll(_:)` | ✅ | Stable |
| `count(_:)` | ✅ | Stable |
| `count(_:where:equals:)` | ✅ | Stable |
| `withTransaction(_:)` | ✅ | Stable |
| `query(_:)` | 🚧 | Beta - DSL may change |
| `queryValue(_:at:)` | 🚧 | Beta |
| `queryOptional(_:at:)` | 🚧 | Beta |
| `queryArray(_:)` | 🚧 | Beta |
| `close()` | ✅ | Stable |

### GraphDatabase (Singleton)

| API | Status | Notes |
|-----|--------|-------|
| `shared` | ✅ | Stable |
| `context()` | ✅ | Stable |
| `configure(_:)` | ✅ | Stable |

### Model Macros

| Macro | Status | Notes |
|-------|--------|-------|
| `@GraphNode` | ✅ | Stable |
| `@GraphEdge(from:to:)` | ✅ | Stable |
| `@ID` | ✅ | Stable |
| `@Index` | ✅ | Stable |
| `@Unique` | ✅ | Stable |
| `@Timestamp` | ✅ | Stable |
| `@Vector(dimensions:)` | 🚧 | Beta - Kuzu vector support evolving |
| `@FullTextSearch` | 🧪 | Experimental |
| `@Default(_:)` | 🚧 | Beta |

## Query DSL Components

### Basic Clauses

| Component | Status | Notes |
|-----------|--------|-------|
| `Match` | ✅ | Stable |
| `Where` | ✅ | Stable |
| `Create` | ✅ | Stable |
| `Return` | ✅ | Stable |
| `Delete` | ✅ | Stable |
| `Set` / `SetClause` | ✅ | Stable |

### Advanced Clauses

| Component | Status | Notes |
|-----------|--------|-------|
| `With` | 🚧 | Beta |
| `Unwind` | 🚧 | Beta |
| `OptionalMatch` | 🚧 | Beta |
| `Merge` | 🚧 | Beta |
| `OrderBy` | ✅ | Stable |
| `Limit` | ✅ | Stable |
| `Skip` | 🚧 | Beta |
| `Union` | ❌ | Not implemented |
| `Foreach` | ❌ | Not implemented |

### Predicates

| Predicate | Status | Notes |
|-----------|--------|-------|
| `==`, `!=` | ✅ | Stable |
| `<`, `>`, `<=`, `>=` | ✅ | Stable |
| `&&`, `||`, `!` | ✅ | Stable |
| `contains()` | ✅ | Stable |
| `startsWith()` | ✅ | Stable |
| `endsWith()` | ✅ | Stable |
| `in()` | ✅ | Stable |
| `between()` | 🚧 | Beta |
| `isNull` / `isNotNull` | ✅ | Stable |
| `regex()` | 🚧 | Beta |

### Patterns

| Pattern | Status | Notes |
|---------|--------|-------|
| Node patterns | ✅ | Stable |
| Edge patterns | ✅ | Stable |
| Path patterns | 🚧 | Beta |
| Variable length paths | 🚧 | Beta |
| Shortest path | ❌ | Not supported by Kuzu |
| All paths | 🚧 | Beta |

### Aggregations

| Function | Status | Notes |
|----------|--------|-------|
| `count()` | ✅ | Stable |
| `sum()` | 🚧 | Beta |
| `avg()` | 🚧 | Beta |
| `min()` | 🚧 | Beta |
| `max()` | 🚧 | Beta |
| `collect()` | 🚧 | Beta |
| `stDev()` | ❌ | Not implemented |
| `percentile()` | ❌ | Not implemented |

### Subqueries

| Type | Status | Notes |
|------|--------|-------|
| `EXISTS` | 🚧 | Beta |
| `NOT EXISTS` | 🚧 | Beta |
| Scalar subquery | 🧪 | Experimental |
| List subquery | 🧪 | Experimental |
| `CALL` subquery | 🧪 | Experimental |

## Type Conversions

### Encoder (Swift → Kuzu)

| Type | Status | Notes |
|------|--------|-------|
| Basic types (Int, String, Bool, Double) | ✅ | Stable |
| UUID | ✅ | Stable - converts to String |
| Date | ✅ | Stable - converts to Timestamp |
| Data | 🚧 | Beta - Base64 encoding |
| Array | ✅ | Stable |
| Dictionary | 🚧 | Beta |
| Optional | ✅ | Stable |
| Custom Codable | 🚧 | Beta |

### Decoder (Kuzu → Swift)

| Type | Status | Notes |
|------|--------|-------|
| Basic types | ✅ | Stable |
| Numeric conversions (Int64 ↔ Int) | ✅ | Stable |
| UUID from String | ✅ | Stable |
| Date from Timestamp | ✅ | Stable |
| Array | ✅ | Stable |
| Dictionary | 🚧 | Beta |
| Optional | ✅ | Stable |
| Custom Decodable | 🚧 | Beta |

## Configuration

### GraphConfiguration

| Option | Status | Notes |
|--------|--------|-------|
| `databasePath` | ✅ | Stable |
| `maxConnections` | ✅ | Stable |
| `connectionTimeout` | ✅ | Stable |
| `extensions` | 🚧 | Beta - depends on Kuzu |
| `migrationPolicy` | 🚧 | Beta |
| `statementCacheSize` | ✅ | Stable |
| `encodingConfiguration` | 🚧 | Beta |
| `decodingConfiguration` | 🚧 | Beta |

### Extensions

| Extension | Status | Notes |
|-----------|--------|-------|
| `.fts` (Full Text Search) | 🧪 | Experimental - limited Kuzu support |
| `.vector` | 🧪 | Experimental - evolving in Kuzu |
| `.httpfs` | ❌ | Not implemented |
| `.json` | ❌ | Not implemented |

## Error Handling

### KuzuError

| Error Case | Status | Notes |
|------------|--------|-------|
| `compilationFailed` | ✅ | Stable |
| `executionFailed` | ✅ | Stable |
| `bindingFailed` | ✅ | Stable |
| `typeMismatch` | ✅ | Stable |
| `noResults` | ✅ | Stable |
| `decodingFailed` | ✅ | Stable |
| `constraintViolation` | ✅ | Stable |
| Other cases | ✅ | Stable |

### GraphError

| Error Case | Status | Notes |
|------------|--------|-------|
| `connectionTimeout` | ✅ | Stable |
| `connectionPoolExhausted` | ✅ | Stable |
| `transactionFailed` | ✅ | Stable |
| `invalidConfiguration` | ✅ | Stable |
| Other cases | ✅ | Stable |

## Utility APIs

### ResultMapper

| Method | Status | Notes |
|--------|--------|-------|
| `mapFirst()` | ✅ | Stable |
| `mapFirst(to:)` | ✅ | Stable |
| `mapFirstRequired(to:)` | ✅ | Stable |
| `mapAll()` | ✅ | Stable |
| `mapAll(to:)` | ✅ | Stable |

### OptimizedParameterGenerator

| Method | Status | Notes |
|--------|--------|-------|
| `semantic()` | ✅ | Internal API |
| `lightweight()` | ✅ | Internal API |
| `cached()` | ✅ | Internal API |

## Migration APIs

| API | Status | Notes |
|-----|--------|-------|
| Schema migration | 🧪 | Experimental |
| Migration policies | 🧪 | Experimental |
| Schema diffing | 🧪 | Experimental |

## Performance APIs

| API | Status | Notes |
|-----|--------|-------|
| Connection pooling | ✅ | Stable |
| Prepared statement caching | ✅ | Stable |
| Batch operations | 🚧 | Beta |
| Streaming results | ❌ | Not implemented |

## Graph Algorithms

| Algorithm | Status | Notes |
|-----------|--------|-------|
| PageRank | ❌ | Not supported by Kuzu |
| Community Detection | ❌ | Not supported by Kuzu |
| Shortest Path | ❌ | Not supported by Kuzu |
| Centrality | ❌ | Not supported by Kuzu |
| Similarity | ❌ | Not supported by Kuzu |

## Breaking Changes Log

### Beta 1
- Removed `GraphAlgorithms` module (not supported by Kuzu)
- Removed `QueryDebug` and `QueryDebuggable` 
- Unified error types into `KuzuError`
- Consolidated `ParameterNameGenerator` into `OptimizedParameterGenerator`

## Deprecation Notices

None yet - this is Beta 1.

## Future Considerations

APIs that may be added or changed:
- Streaming result support
- Query plan hints
- Distributed transaction support (when Kuzu supports it)
- Additional Cypher features
- Performance profiling APIs