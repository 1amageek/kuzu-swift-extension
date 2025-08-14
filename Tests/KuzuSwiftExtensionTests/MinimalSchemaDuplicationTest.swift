import Testing
import KuzuSwiftExtension
@testable import KuzuSwiftExtension
import struct Foundation.UUID

// Minimal test model - no Date to avoid import issues
@GraphNode
struct DuplicationTestNode {
    @ID var id: UUID = UUID()
    var name: String
}

@Suite("Minimal Schema Duplication Test")
struct MinimalSchemaDuplicationTest {
    
    @Test("createSchemaIfNotExists works without duplication error")
    func testCreateSchemaIfNotExists() async throws {
        // Create in-memory context with automatic migration
        let config = GraphConfiguration(
            databasePath: ":memory:",
            migrationMode: .automatic
        )
        let context = try await GraphContext(configuration: config)
        
        // First call - creates the table
        try await context.createSchemaIfNotExists(for: DuplicationTestNode.self)
        
        // Second call - should skip existing table (not error)
        try await context.createSchemaIfNotExists(for: DuplicationTestNode.self)
        
        // Third call - verify still works
        try await context.createSchemaIfNotExists(for: DuplicationTestNode.self)
        
        // Test passed if we get here without errors
        #expect(true)
        
        await context.close()
    }
    
    @Test("GraphDatabase.container with automatic migration")
    func testAutomaticMigration() async throws {
        // Use SwiftData-style container API
        let context = try await GraphDatabase.container(
            for: [DuplicationTestNode.self],
            inMemory: true,
            migrationMode: .automatic
        )
        
        // Try creating schema again - should not error
        try await context.createSchemaIfNotExists(for: DuplicationTestNode.self)
        
        // Can also use batch method
        try await context.createSchemasIfNotExist(for: [DuplicationTestNode.self])
        
        #expect(true)
        
        await context.close()
    }
    
    @Test("MigrationManager handles existing tables")
    func testMigrationManagerSafety() async throws {
        let config = GraphConfiguration(
            databasePath: ":memory:",
            migrationMode: .none
        )
        let context = try await GraphContext(configuration: config)
        
        // Manually create the table first
        let ddl = DuplicationTestNode._kuzuDDL
        _ = try await context.raw(ddl)
        
        // Now use MigrationManager - should not error on existing table
        let manager = MigrationManager(
            context: context,
            policy: .safeOnly
        )
        
        try await manager.migrateIfNeeded(types: [DuplicationTestNode.self])
        
        #expect(true)
        
        await context.close()
    }
}