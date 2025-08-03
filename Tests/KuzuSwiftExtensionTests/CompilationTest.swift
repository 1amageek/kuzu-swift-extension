import Testing
import Foundation
@testable import KuzuSwiftExtension
@testable import KuzuSwiftExtensionMacros

// Test that basic types compile correctly
@Test func testBasicCompilation() async throws {
    // Test protocol conformance
    struct TestProtocol: _KuzuGraphModel {
        @_spi(Graph) static let _kuzuDDL: [String] = []
        @_spi(Graph) static let _kuzuColumns: [ColumnMeta] = []
        static let _kuzuTableName: String = "Test"
    }
    
    // Test GraphSchema
    let schema = GraphSchema(TestProtocol.self)
    #expect(schema.models.count == 1)
    
    // Test Configuration
    let config = GraphConfiguration(
        schema: schema,
        url: URL(string: ":memory:")!,
        name: "test"
    )
    #expect(config.name == "test")
    
    // Test Errors
    let error = GraphError.invalidConfiguration("test")
    #expect(error.errorDescription != nil)
    
    // Test Query Components
    let match = MatchClause(type: TestProtocol.self)
    #expect(match.variable == "test")
    
    let create = CreateClause(type: TestProtocol.self)
    #expect(create.variable == "test")
    
    // Test Predicate
    let predicate = Predicate<Int>.equal(42)
    switch predicate {
    case .equal(let value):
        #expect(value == 42)
    default:
        #expect(false)
    }
}