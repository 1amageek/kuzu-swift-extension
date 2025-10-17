# GraphContainer Deferred Initialization Design

## Overview

This document describes the deferred initialization design for `GraphContainer` in kuzu-swift-extension. This design builds on top of the deferred Database initialization provided by kuzu-swift.

**Related Document**: See [kuzu-swift/ASYNC_DATABASE_INIT_DESIGN.md](../kuzu-swift/ASYNC_DATABASE_INIT_DESIGN.md) for the underlying Database deferred initialization design.

## Problem Context

**Current Issue**: GraphContainer initialization blocks the calling thread during:
1. Database initialization (14+ seconds on iOS due to F_FULLFSYNC)
2. Schema creation (fast, ~100ms)

**User Impact**: iOS apps freeze for 14+ seconds at startup when initializing GraphContainer synchronously.

## GraphContainer Location

**File Location**: `/Users/1amageek/Desktop/kuzu-swift-extension/Sources/KuzuSwiftExtension/Core/GraphContainer.swift`

**Package Structure**:
```
kuzu-swift/                  # Base package (Database, Connection, etc.)
└── ASYNC_DATABASE_INIT_DESIGN.md

kuzu-swift-extension/        # Higher-level package (GraphContainer, SwiftUI integration)
├── GRAPHCONTAINER_ASYNC_DESIGN.md  (this file)
└── Sources/KuzuSwiftExtension/Core/GraphContainer.swift
```

**Dependency**: kuzu-swift-extension depends on kuzu-swift, so GraphContainer uses Database from kuzu-swift.

## Solution: SwiftData-like Deferred Initialization

GraphContainer constructor returns immediately after Database initialization (which spawns background thread). Heavy initialization happens in background. First query waits transparently for completion.

### Database Initialization Phases (from kuzu-swift)

**Phase 1** (synchronous, 20-50ms):
- VFS, BufferManager, MemoryManager initialization
- QueryProcessor, Catalog, TransactionManager initialization
- Constructor returns immediately

**Phase 2-4** (background thread, 14+ seconds):
- Phase 2: WAL replay + F_FULLFSYNC (~14s)
- Phase 3: Extension loading (few hundred ms)
- Phase 4: HNSW index loading (synchronized, same thread)

All phases run in single background thread with `isRecoveryInProgress=true`.

### GraphContainer Initialization

```
Timeline of GraphContainer():
┌──────────────────────────────────────────────────────┐
│ Main Thread                                          │
│                                                       │
│ 0ms:  GraphContainer(for: PhotoAsset.self)          │
│       ├─ Database() constructor called               │
│       │  ├─ Phase 1 complete (20ms)                  │
│       │  └─ Background thread spawned                │
│       ├─ Schema creation (fast, ~100ms)             │
│       └─ GraphContainer returned                     │
│                                                       │
│ 100ms: App shows UI (SplashView)                    │
│        Optional: Poll initializationStatus           │
│                                                       │
│ 14s+:  First query called                            │
│        └─ Waits internally for Database init         │
│        └─ Query executes                             │
│                                                       │
│ 14s+:  Subsequent queries execute immediately        │
└──────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────┐
│ Background Thread (spawned by Database)              │
│                                                       │
│ Phase 2: Storage Recovery (14s)                     │
│ Phase 3: Extension Loading (few hundred ms)          │
│ Phase 4: HNSW Index Loading (few seconds)           │
│                                                       │
│ All phases complete → initComplete = true           │
└──────────────────────────────────────────────────────┘
```

## API Design

### GraphContainer Initializer (Unchanged)

**Signature remains the same**, behavior changes:

```swift
public final class GraphContainer: @unchecked Sendable {
    private let database: Database

    /// Initializes a new GraphContainer.
    ///
    /// **Note**: Constructor returns immediately. Heavy database initialization happens
    /// in background. First query will wait transparently for completion.
    ///
    /// - Parameters:
    ///   - forTypes: Model types to register
    ///   - configuration: Graph configuration
    /// - Throws: Error if initialization fails
    ///
    /// ## Deferred Initialization
    /// The constructor returns in <100ms by delegating to Database (which spawns background thread).
    /// Use `initializationStatus` to track progress:
    ///
    /// ```swift
    /// let container = try GraphContainer(for: PhotoAsset.self)
    /// // Returns immediately!
    ///
    /// // Optional: Check status for UI feedback
    /// while case .initializing = container.initializationStatus {
    ///     await Task.sleep(for: .milliseconds(100))
    /// }
    /// // CRUD + vector search both available
    /// ```
    public init(
        for forTypes: (any _KuzuGraphModel.Type)...,
        configuration: GraphConfiguration = GraphConfiguration()
    ) throws {
        // Database constructor returns immediately (spawns background thread)
        self.database = try Database(
            configuration.databasePath,
            configuration.systemConfig
        )

        // Create schema (fast, synchronous, ~100ms)
        if !forTypes.isEmpty {
            let schemaManager = SchemaManager(forTypes)
            try schemaManager.ensureSchema(in: database)
        }

        // Constructor returns - database initialization continues in background
    }

    /// The current initialization status of the underlying database.
    ///
    /// When this returns `.ready`, both CRUD operations and vector search are available.
    ///
    /// Use this to track initialization progress in UI:
    ///
    /// ```swift
    /// @State private var status: DatabaseStatus = .initializing
    ///
    /// var body: some View {
    ///     if case .ready = status {
    ///         MainView()  // All features available
    ///     } else {
    ///         SplashView(status: status)
    ///             .task {
    ///                 while case .initializing = status {
    ///                     status = container.initializationStatus
    ///                     try? await Task.sleep(for: .milliseconds(100))
    ///                 }
    ///             }
    ///     }
    /// }
    /// ```
    public var initializationStatus: DatabaseStatus {
        database.initializationStatus
    }
}
```

### Changes Summary

**API Changes**:
- ✅ **Constructor signature unchanged**: `try GraphContainer(for: Model.self)`
- ✅ **Single status property**: `initializationStatus` (forwarded from Database)
- ✅ **Removed**: `vectorIndexesStatus` (no longer needed - included in `initializationStatus`)
- ✅ **Documentation updated**: Notes about deferred initialization

**Behavior Changes**:
- ✅ **Constructor returns immediately**: <100ms instead of 14+ seconds
- ✅ **Background initialization**: Database spawns thread automatically
- ✅ **Transparent waiting**: First query blocks until ready
- ✅ **Single status**: When `.ready`, all features available (CRUD + vector search)

## Usage Examples

### Example 1: Minimal Change (SwiftData-like)

**Before**:
```swift
@main
struct PXLApp: App {
    let graphContainer: GraphContainer = {
        try! GraphContainer(for: PhotoAsset.self)  // Blocks for 14s
    }()

    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .graphContainer(graphContainer)
    }
}
```

**After** (same API, different behavior):
```swift
@main
struct PXLApp: App {
    // ✅ Returns immediately! Same API!
    let graphContainer: GraphContainer = {
        try! GraphContainer(for: PhotoAsset.self)  // <100ms
    }()

    var body: some Scene {
        WindowGroup {
            MainView()  // Shows immediately
        }
        .graphContainer(graphContainer)
    }
}
```

**Key Point**: API is identical. Constructor now returns immediately, initialization happens in background.

### Example 2: Optional Status Polling for Splash Screen

```swift
@main
struct PXLApp: App {
    let graphContainer: GraphContainer = {
        try! GraphContainer(for: PhotoAsset.self)
    }()

    @State private var status: DatabaseStatus = .initializing

    var body: some Scene {
        WindowGroup {
            if case .ready = status {
                MainView()  // CRUD + vector search both available
            } else {
                SplashView(status: status)
                    .task {
                        // Optional: Poll status for UI feedback
                        while case .initializing = status {
                            status = graphContainer.initializationStatus
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                    }
            }
        }
        .graphContainer(graphContainer)
    }
}

struct SplashView: View {
    let status: DatabaseStatus

    var body: some View {
        VStack(spacing: 20) {
            Image("AppIcon")

            switch status {
            case .initializing:
                ProgressView("Initializing database...")
                Text("Loading WAL, extensions, and indexes...")
                    .font(.caption)
            case .ready:
                Text("Ready!")
            case .failed(let error):
                Text("Error: \(error.localizedDescription)")
                    .foregroundStyle(.red)
            }
        }
    }
}
```

### Example 3: No Status Polling (Simplest)

```swift
@main
struct PXLApp: App {
    // Constructor returns immediately
    let graphContainer = try! GraphContainer(for: PhotoAsset.self)

    var body: some Scene {
        WindowGroup {
            MainView()  // First query will wait transparently
        }
        .graphContainer(graphContainer)
    }
}
```

**Timeline**:
- **0ms**: App launches, constructor returns
- **100ms**: MainView appears immediately
- **First query**: Blocks until initialization complete (transparent to user)
- **Subsequent queries**: Execute immediately
- **All features available**: CRUD + vector search

## Comparison: Before vs After

### Before (Blocking)

```swift
let container = try GraphContainer(for: PhotoAsset.self)
// ↑ Blocks for 14+ seconds
// App appears frozen
```

**Timeline**:
```
0s    : Constructor called
0-14s : FROZEN (Database initialization blocking main thread)
14s   : Constructor returns
14s   : UI shows
```

### After (Deferred Initialization)

```swift
let container = try GraphContainer(for: PhotoAsset.self)
// ↑ Returns in <100ms
// App shows UI immediately
```

**Timeline**:
```
0ms   : Constructor called
100ms : Constructor returns
100ms : UI shows (SplashView)
14s   : Background initialization completes
14s   : First query executes immediately
       All features available (CRUD + vector search)
```

## Design Rationale

### Why No Separate Vector Status

**Previous Design** (rejected):
```swift
public var initializationStatus: DatabaseStatus  // CRUD ready
public var vectorIndexesStatus: VectorIndexesStatus  // Vector search ready
```

**New Design** (simplified):
```swift
public var initializationStatus: DatabaseStatus  // Everything ready
```

**Reasons**:
- ✅ **Single background thread**: Database Phases 2-4 run sequentially in one thread
- ✅ **isRecoveryInProgress**: Kept true throughout, so HNSW loads synchronously
- ✅ **Atomic readiness**: When `initComplete=true`, CRUD + vector search both ready
- ✅ **Simpler API**: One status property, one concept

**From kuzu-swift design**:
> "Keep `isRecoveryInProgress=true` throughout Phases 2, 3, and 4, so HNSW loads synchronously in the same background thread."

### Why Constructor Returns Immediately

**Implementation**:
```swift
public init(for forTypes: ...) throws {
    // Database constructor spawns thread, returns immediately
    self.database = try Database(...)  // 20-50ms

    // Schema creation (fast)
    try schemaManager.ensureSchema(in: database)  // ~100ms

    // Constructor returns (total: <100ms)
}
```

**Reasons**:
- ✅ **Fast Phase 1**: Database lightweight initialization (20-50ms)
- ✅ **Fast schema creation**: Simple synchronous operation (~100ms)
- ✅ **Total <100ms**: Acceptable blocking time for instant UI
- ✅ **Background continues**: Database initialization thread keeps running

### Why First Query Waits Transparently

**Implementation** (in Database class, from kuzu-swift):
```swift
// Connection.query() calls waitForInitialization() internally
public func query(_ query: String) -> QueryResult {
    database.waitForInitialization()  // ← Transparent wait
    // Execute query
}
```

**Reasons**:
- ✅ **Safe by default**: Cannot query uninitialized database
- ✅ **Zero API changes**: User calls query normally
- ✅ **Fast path**: After initialization, single atomic check
- ✅ **Error propagation**: Init errors thrown at first query

## Implementation Checklist

### Phase 1: Update GraphContainer

- [ ] **GraphContainer.swift**: Add `initializationStatus` computed property
- [ ] **GraphContainer.swift**: Remove `vectorIndexesStatus` (no longer needed)
- [ ] **GraphContainer.swift**: Update constructor documentation
- [ ] **GraphContainer.swift**: Add usage examples in documentation

### Phase 2: Testing

- [ ] **Unit tests**: Verify constructor returns immediately (<100ms)
- [ ] **Unit tests**: Verify first query waits for initialization
- [ ] **Unit tests**: Verify status transitions (initializing → ready)
- [ ] **Unit tests**: Verify all features available when status is ready
- [ ] **Integration tests**: Test with real iOS app (startup time)

### Phase 3: Documentation

- [ ] Update README with deferred initialization examples
- [ ] Add migration guide (no changes needed, but explain new behavior)
- [ ] Document status polling patterns for splash screens

## Success Criteria

1. ✅ **Instant Constructor**: GraphContainer constructor returns in <100ms
2. ✅ **Background Init**: Database initialization happens in background
3. ✅ **Transparent Wait**: First query blocks until initialization complete
4. ✅ **Single Status**: `initializationStatus` indicates full readiness
5. ✅ **SwiftData-like**: API matches SwiftData simplicity
6. ✅ **Zero Migration**: Existing code works without changes
7. ✅ **All Features Ready**: When status is `.ready`, CRUD + vector search available

## Common Questions

### Q1: Does this require changes to my code?

**A**: No! The API is unchanged:

```swift
// Before (blocks for 14s)
let container = try GraphContainer(for: PhotoAsset.self)

// After (returns in <100ms, same API)
let container = try GraphContainer(for: PhotoAsset.self)
```

First query waits transparently, so existing code works as-is.

### Q2: How do I show a splash screen during initialization?

**A**: Poll `initializationStatus`:

```swift
@State private var status: DatabaseStatus = .initializing

var body: some View {
    if case .ready = status {
        MainView()
    } else {
        SplashView(status: status)
            .task {
                while case .initializing = status {
                    status = container.initializationStatus
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
    }
}
```

### Q3: What happens if I query immediately after construction?

**A**: First query waits transparently:

```swift
let container = try GraphContainer(for: PhotoAsset.self)
// Returns immediately

let context = GraphContext(container)
let assets = try await context.fetch(PhotoAsset.self)
// ↑ Blocks here until initialization complete (transparent)
```

### Q4: When is vector search available?

**A**: When `initializationStatus == .ready`:

```swift
if case .ready = container.initializationStatus {
    // Both CRUD and vector search available
    let results = try await context.vectorSearch(...)
}
```

There's no separate status - everything is ready together.

### Q5: Why is there only one status property now?

**A**: Because Database Phases 2-4 run in a single thread with `isRecoveryInProgress=true`, HNSW indexes load synchronously. When initialization completes, everything is ready (CRUD + vector search).

## Benefits

- ✅ **Instant App Startup**: Constructor returns in <100ms instead of 14+ seconds
- ✅ **SwiftData-like API**: Matches SwiftData patterns exactly
- ✅ **Zero Migration**: Existing code works without modification
- ✅ **Safe by Default**: Impossible to query uninitialized database
- ✅ **Single Status**: One property for all features
- ✅ **Platform Agnostic**: Works on all platforms
- ✅ **Thread Safe**: Proper synchronization in C++ layer
- ✅ **Simple**: No complex multi-stage status tracking

## Summary

**Key Design Decisions**:

1. ✅ **Constructor unchanged**: `try GraphContainer(for: Model.self)` returns immediately
2. ✅ **Single status property**: `initializationStatus` indicates full readiness
3. ✅ **Transparent waiting**: First query blocks internally
4. ✅ **SwiftData-like**: No async/await, callbacks, or manual waiting
5. ✅ **Backward compatible**: Existing code works without changes

**Migration**:
- **Required changes**: None
- **Optional enhancements**: Add splash screen with status polling
- **Breaking changes**: None

**When status is `.ready`**:
- ✅ CRUD operations available
- ✅ Vector similarity search available
- ✅ All database features available
