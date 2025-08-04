import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import KuzuSwiftMacrosPlugin

final class GraphNodeMacroTests: XCTestCase {
    
    func testGraphNodeMacro() throws {
        assertMacroExpansion(
            """
            @GraphNode
            struct User {
                @ID var id: String
                @Index var name: String
                var email: String?
                var age: Int
                @Timestamp var createdAt: Date
            }
            """,
            expandedSource: """
            struct User {
                var id: String
                var name: String
                var email: String?
                var age: Int
                var createdAt: Date
            
                static let _kuzuDDL: String = "CREATE NODE TABLE User (id STRING PRIMARY KEY, name STRING, email STRING, age INT64, createdAt TIMESTAMP)"
            
                static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "id", type: "STRING", constraints: ["PRIMARY KEY"]), (name: "name", type: "STRING", constraints: ["INDEX"]), (name: "email", type: "STRING", constraints: []), (name: "age", type: "INT64", constraints: []), (name: "createdAt", type: "TIMESTAMP", constraints: [])]
            }
            
            extension User: GraphNodeModel {
            }
            """,
            macros: ["GraphNode": GraphNodeMacro.self, "ID": IDMacro.self, "Index": IndexMacro.self, "Timestamp": TimestampMacro.self]
        )
    }
    
    func testGraphNodeWithVector() throws {
        assertMacroExpansion(
            """
            @GraphNode
            struct Document {
                @ID var id: String
                var content: String
                @Vector(dimensions: 1536) var embedding: [Double]
            }
            """,
            expandedSource: """
            struct Document {
                var id: String
                var content: String
                var embedding: [Double]
            
                static let _kuzuDDL: String = "CREATE NODE TABLE Document (id STRING PRIMARY KEY, content STRING, embedding DOUBLE[1536])"
            
                static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "id", type: "STRING", constraints: ["PRIMARY KEY"]), (name: "content", type: "STRING", constraints: []), (name: "embedding", type: "DOUBLE[1536]", constraints: [])]
            }
            
            extension Document: GraphNodeModel {
            }
            """,
            macros: ["GraphNode": GraphNodeMacro.self, "ID": IDMacro.self, "Vector": VectorMacro.self]
        )
    }
    
    func testGraphNodeOnNonStruct() throws {
        assertMacroExpansion(
            """
            @GraphNode
            class User {
                var id: String = ""
            }
            """,
            expandedSource: """
            class User {
                var id: String = ""
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@GraphNode can only be applied to structs", line: 1, column: 1)
            ],
            macros: ["GraphNode": GraphNodeMacro.self]
        )
    }
}