import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import KuzuSwiftMacrosPlugin

final class GraphEdgeMacroTests: XCTestCase {
    
    func testGraphEdgeMacro() throws {
        assertMacroExpansion(
            """
            @GraphEdge(from: User.self, to: Post.self)
            struct Authored {
                @ID var id: String
                var authoredAt: Date
                var role: String?
            }
            """,
            expandedSource: """
            struct Authored {
                var id: String
                var authoredAt: Date
                var role: String?
            
                public static let _kuzuDDL: String = "CREATE REL TABLE Authored (FROM User TO Post, id STRING PRIMARY KEY, authoredAt TIMESTAMP, role STRING)"
            
                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "id", type: "STRING", constraints: ["PRIMARY KEY"]), (name: "authoredAt", type: "TIMESTAMP", constraints: []), (name: "role", type: "STRING", constraints: [])]
            }
            
            extension Authored: GraphEdgeModel {
            }
            """,
            macros: ["GraphEdge": GraphEdgeMacro.self, "ID": IDMacro.self]
        )
    }
    
    func testGraphEdgeWithoutParameters() throws {
        assertMacroExpansion(
            """
            @GraphEdge
            struct Follows {
                var createdAt: Date
            }
            """,
            expandedSource: """
            struct Follows {
                var createdAt: Date
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@GraphEdge requires 'from' and 'to' type parameters", line: 1, column: 1)
            ],
            macros: ["GraphEdge": GraphEdgeMacro.self]
        )
    }
    
    func testGraphEdgeOnNonStruct() throws {
        assertMacroExpansion(
            """
            @GraphEdge(from: User.self, to: User.self)
            enum Relationship {
                case follows
                case blocks
            }
            """,
            expandedSource: """
            enum Relationship {
                case follows
                case blocks
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@GraphEdge can only be applied to structs", line: 1, column: 1)
            ],
            macros: ["GraphEdge": GraphEdgeMacro.self]
        )
    }
}