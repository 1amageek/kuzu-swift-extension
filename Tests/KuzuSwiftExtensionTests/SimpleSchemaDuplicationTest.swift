import Testing
import KuzuSwiftExtension
@testable import KuzuSwiftExtension
import struct Foundation.UUID

// Simple test model
@GraphNode
struct TestItem {
    @ID var id: UUID = UUID()
    var name: String
}

@Suite("Simple Schema Duplication Test")
struct SimpleSchemaDuplicationTest {
    
    @Test("createSchemaIfNotExists does not error on duplicate")
    func testCreateSchemaIfNotExists() async throws {
        // Create a test context
        let config = GraphConfiguration(
            databasePath: ":memory:",
            migrationMode: .automatic
        )
        let context = try await GraphContext(configuration: config)
        
        // First creation - should succeed
        try await context.createSchemaIfNotExists(for: TestItem.self)
        
        // Second creation - should not error (skip existing)
        try await context.createSchemaIfNotExists(for: TestItem.self)
        
        // Third creation - verify still works
        try await context.createSchemaIfNotExists(for: TestItem.self)
        
        // If we reach here, the test passed
        #expect(true, "No duplicate table error occurred")
        
        await context.close()
    }
    
    @Test("MigrationManager migrateIfNeeded handles existing tables")
    func testMigrationManagerSafety() async throws {
        let config = GraphConfiguration(
            databasePath: ":memory:",
            migrationMode: .none  // Manual control
        )
        let context = try await GraphContext(configuration: config)
        
        // Create schema manually first
        let ddl = TestItem._kuzuDDL
        _ = try await context.raw(ddl)
        
        // Now use MigrationManager - should not error
        let migrationManager = MigrationManager(
            context: context,
            policy: .safe
        )
        
        // This should handle the existing table gracefully
        try await migrationManager.migrateIfNeeded(types: [TestItem.self])
        
        #expect(true, "MigrationManager handled existing table")
        
        await context.close()
    }
    
    @Test("Automatic migration mode in GraphDatabase")  
    func testAutomaticMigrationMode() async throws {
        // Use the new container API with automatic migration
        let context = try await GraphDatabase.container(
            for: [TestItem.self],
            inMemory: true,
            migrationMode: .automatic
        )
        
        // Try to create schema again - should not error
        try await context.createSchemasIfNotExist(for: [TestItem.self])
        
        #expect(true, "Automatic migration handled duplicates")
        
        await context.close()
    }
}