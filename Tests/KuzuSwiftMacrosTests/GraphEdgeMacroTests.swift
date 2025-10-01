import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import KuzuSwiftMacrosPlugin

@Suite("Graph Edge Macro Tests")
struct GraphEdgeMacroTests {
    
    @Test("GraphEdge macro expansion")
    func graphEdgeMacro() throws {
        assertMacroExpansion(
            """
            @GraphEdge(from: User.self, to: Post.self)
            struct AuthoredBy {
                var createdAt: Date
                var metadata: String?
            }
            """,
            expandedSource: """
            struct AuthoredBy {
                var createdAt: Date
                var metadata: String?

                public static let _kuzuDDL: String = "CREATE REL TABLE AuthoredBy (FROM User TO Post, createdAt TIMESTAMP, metadata STRING)"

                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "createdAt", type: "TIMESTAMP", constraints: []), (name: "metadata", type: "STRING", constraints: [])]
            }

            extension AuthoredBy: GraphEdgeModel {
                public static let _fromType: Any.Type = User.self
                public static let _toType: Any.Type = Post.self
            }
            """,
            macros: ["GraphEdge": GraphEdgeMacro.self]
        )
    }
    
    @Test("GraphEdge with various property types")
    func graphEdgeWithProperties() throws {
        assertMacroExpansion(
            """
            @GraphEdge(from: User.self, to: Company.self)
            struct WorksAt {
                var startDate: Date
                var position: String
                @Default("full-time") var employmentType: String
                var salary: Double?
            }
            """,
            expandedSource: """
            struct WorksAt {
                var startDate: Date
                var position: String
                var employmentType: String
                var salary: Double?

                public static let _kuzuDDL: String = "CREATE REL TABLE WorksAt (FROM User TO Company, startDate TIMESTAMP, position STRING, employmentType STRING DEFAULT 'full-time', salary DOUBLE)"
            
                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "startDate", type: "TIMESTAMP", constraints: []), (name: "position", type: "STRING", constraints: []), (name: "employmentType", type: "STRING", constraints: ["DEFAULT 'full-time'"]), (name: "salary", type: "DOUBLE", constraints: [])]
            }
            
            extension WorksAt: GraphEdgeModel {
                public static let _fromType: Any.Type = User.self
                public static let _toType: Any.Type = Company.self
            }
            """,
            macros: ["GraphEdge": GraphEdgeMacro.self, "Default": DefaultMacro.self]
        )
    }
    
    @Test("Simple GraphEdge without properties")
    func simpleGraphEdge() throws {
        assertMacroExpansion(
            """
            @GraphEdge(from: User.self, to: User.self)
            struct Follows {
            }
            """,
            expandedSource: """
            struct Follows {
            
                public static let _kuzuDDL: String = "CREATE REL TABLE Follows (FROM User TO User)"
            
                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = []
            }
            
            extension Follows: GraphEdgeModel {
                public static let _fromType: Any.Type = User.self
                public static let _toType: Any.Type = User.self
            }
            """,
            macros: ["GraphEdge": GraphEdgeMacro.self]
        )
    }
}