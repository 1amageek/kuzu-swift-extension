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
        let container = try GraphContainer(configuration: config)
        let context = GraphContext(container)
        
        // First call - creates the table
        try context.createSchemaIfNotExists(for: DuplicationTestNode.self)
        
        // Second call - should skip existing table (not error)
        try context.createSchemaIfNotExists(for: DuplicationTestNode.self)
        
        // Third call - verify still works
        try context.createSchemaIfNotExists(for: DuplicationTestNode.self)
        
        // Test passed if we get here without errors
        #expect(true)
        
    }
    
    @Test("GraphContainer with automatic migration")
    func testAutomaticMigration() async throws {
        // Use SwiftData-style container API
        let container = try GraphContainer(
            for: DuplicationTestNode.self,
            configuration: GraphConfiguration(
                databasePath: ":memory:",
                migrationMode: .automatic
            )
        )
        let context = GraphContext(container)
        
        // Try creating schema again - should not error
        try context.createSchemaIfNotExists(for: DuplicationTestNode.self)
        
        // Can also use batch method
        try context.createSchemasIfNotExist(for: [DuplicationTestNode.self])
        
        #expect(true)
        
    }
    
    @Test("MigrationManager handles existing tables")
    func testMigrationManagerSafety() async throws {
        let config = GraphConfiguration(
            databasePath: ":memory:",
            migrationMode: .none
        )
        let container = try GraphContainer(configuration: config)
        let context = GraphContext(container)
        
        // Manually create the table first
        let ddl = DuplicationTestNode._kuzuDDL
        _ = try context.raw(ddl)
        
        // Now use MigrationManager - should not error on existing table
        let manager = MigrationManager(
            context: context,
            policy: .safe
        )
        
        try manager.migrateIfNeeded(types: [DuplicationTestNode.self])
        
        #expect(true)
        
    }
}