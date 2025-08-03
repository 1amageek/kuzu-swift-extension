import Testing
import Foundation
@testable import KuzuSwiftExtension

// Simple test to verify basic types compile
@Test func testBasicTypes() async throws {
    // Test GraphSchema creation
    let schema = GraphSchema()
    #expect(schema.models.isEmpty)
    
    // Test Configuration
    let config = GraphConfiguration(
        schema: schema,
        inMemory: true,
        name: "test"
    )
    #expect(config.name == "test")
    #expect(config.options.inMemory == true)
    
    // Test Error types
    let error = GraphError.invalidConfiguration("test")
    #expect(error.localizedDescription.contains("test"))
}