import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import KuzuSwiftExtensionMacrosPlugin

@Test func testGraphNodeMacro() async throws {
    assertMacroExpansion(
        """
        @GraphNode
        struct Person {
            @ID var id: UUID
            @Index var name: String
            var age: Int?
        }
        """,
        expandedSource: """
        struct Person {
            @ID var id: UUID
            @Index var name: String
            var age: Int?
        }
        
        extension Person: GraphNodeProtocol, _KuzuGraphModel {
            @_spi(Graph)
            public static let _kuzuDDL: [String] = ["CREATE NODE TABLE Person (id UUID PRIMARY KEY, name STRING NOT NULL, age INT32)"]
            
            @_spi(Graph)
            public static let _kuzuColumns: [ColumnMeta] = [["name": "id", "kuzuType": "UUID", "modifiers": ["PRIMARY KEY"]], ["name": "name", "kuzuType": "STRING", "modifiers": ["NOT NULL"]], ["name": "age", "kuzuType": "INT32", "modifiers": []]]
            
            public static let _kuzuTableName: String = "Person"
        }
        """,
        macros: ["GraphNode": GraphNodeMacro.self]
    )
}