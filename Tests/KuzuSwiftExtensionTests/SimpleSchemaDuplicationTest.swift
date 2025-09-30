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
        let container = try GraphContainer(configuration: config)
        let context = GraphContext(container)
        
        // First creation - should succeed
        try context.createSchemaIfNotExists(for: TestItem.self)
        
        // Second creation - should not error (skip existing)
        try context.createSchemaIfNotExists(for: TestItem.self)
        
        // Third creation - verify still works
        try context.createSchemaIfNotExists(for: TestItem.self)
        
        // If we reach here, the test passed
        #expect(true, "No duplicate table error occurred")
        
    }
    
    @Test("MigrationManager migrateIfNeeded handles existing tables")
    func testMigrationManagerSafety() async throws {
        let config = GraphConfiguration(
            databasePath: ":memory:",
            migrationMode: .none  // Manual control
        )
        let container = try GraphContainer(configuration: config)
        let context = GraphContext(container)
        
        // Create schema manually first
        let ddl = TestItem._kuzuDDL
        _ = try context.raw(ddl)
        
        // Now use MigrationManager - should not error
        let migrationManager = MigrationManager(
            context: context,
            policy: .safe
        )
        
        // This should handle the existing table gracefully
        try migrationManager.migrateIfNeeded(types: [TestItem.self])
        
        #expect(true, "MigrationManager handled existing table")
        
    }
    
    @Test("Automatic migration mode with GraphContainer")
    func testAutomaticMigrationMode() async throws {
        // Use the new container API with automatic migration
        let container = try GraphContainer(
            for: TestItem.self,
            configuration: GraphConfiguration(
                databasePath: ":memory:",
                migrationMode: .automatic
            )
        )
        let context = GraphContext(container)
        
        // Try to create schema again - should not error
        try context.createSchemasIfNotExist(for: [TestItem.self])
        
        #expect(true, "Automatic migration handled duplicates")
        
    }
}