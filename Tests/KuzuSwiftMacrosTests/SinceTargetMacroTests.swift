import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import KuzuSwiftMacrosPlugin

@Suite("Since and Target Macro Tests")
struct SinceTargetMacroTests {

    @Test("GraphEdge with @Since and @Target")
    func graphEdgeWithSinceTarget() throws {
        assertMacroExpansion(
            """
            @GraphEdge
            struct Authored {
                @Since(\\User.id) var authorID: String
                @Target(\\Post.id) var postID: String
                var createdAt: Date
            }
            """,
            expandedSource: """
            struct Authored {
                var authorID: String
                var postID: String
                var createdAt: Date

                public static let _kuzuDDL: String = "CREATE REL TABLE Authored (FROM User TO Post, authorID STRING, postID STRING, createdAt TIMESTAMP)"

                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "authorID", type: "STRING", constraints: []), (name: "postID", type: "STRING", constraints: []), (name: "createdAt", type: "TIMESTAMP", constraints: [])]

                public static let _metadata = GraphMetadata(edgeMetadata: EdgeMetadata(
                    sinceProperty: "authorID",
                    sinceNodeType: "User",
                    sinceNodeKeyPath: "id",
                    targetProperty: "postID",
                    targetNodeType: "Post",
                    targetNodeKeyPath: "id"
                ))
            }

            extension Authored: GraphEdgeModel {
            }
            """,
            macros: [
                "GraphEdge": GraphEdgeMacro.self,
                "Since": SinceMacro.self,
                "Target": TargetMacro.self
            ]
        )
    }

    @Test("GraphEdge with @Since and @Target - no additional properties")
    func graphEdgeWithOnlySinceTarget() throws {
        assertMacroExpansion(
            """
            @GraphEdge
            struct Follows {
                @Since(\\User.email) var followerEmail: String
                @Target(\\User.email) var followeeEmail: String
            }
            """,
            expandedSource: """
            struct Follows {
                var followerEmail: String
                var followeeEmail: String

                public static let _kuzuDDL: String = "CREATE REL TABLE Follows (FROM User TO User, followerEmail STRING, followeeEmail STRING)"

                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "followerEmail", type: "STRING", constraints: []), (name: "followeeEmail", type: "STRING", constraints: [])]

                public static let _metadata = GraphMetadata(edgeMetadata: EdgeMetadata(
                    sinceProperty: "followerEmail",
                    sinceNodeType: "User",
                    sinceNodeKeyPath: "email",
                    targetProperty: "followeeEmail",
                    targetNodeType: "User",
                    targetNodeKeyPath: "email"
                ))
            }

            extension Follows: GraphEdgeModel {
            }
            """,
            macros: [
                "GraphEdge": GraphEdgeMacro.self,
                "Since": SinceMacro.self,
                "Target": TargetMacro.self
            ]
        )
    }

    @Test("GraphEdge with @Since, @Target and @Default")
    func graphEdgeWithDefaultValue() throws {
        assertMacroExpansion(
            """
            @GraphEdge
            struct WorksAt {
                @Since(\\User.id) var employeeID: String
                @Target(\\Company.id) var companyID: String
                var startDate: Date
                @Default("full-time") var employmentType: String
            }
            """,
            expandedSource: """
            struct WorksAt {
                var employeeID: String
                var companyID: String
                var startDate: Date
                var employmentType: String

                public static let _kuzuDDL: String = "CREATE REL TABLE WorksAt (FROM User TO Company, employeeID STRING, companyID STRING, startDate TIMESTAMP, employmentType STRING DEFAULT 'full-time')"

                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "employeeID", type: "STRING", constraints: []), (name: "companyID", type: "STRING", constraints: []), (name: "startDate", type: "TIMESTAMP", constraints: []), (name: "employmentType", type: "STRING", constraints: ["DEFAULT 'full-time'"])]

                public static let _metadata = GraphMetadata(edgeMetadata: EdgeMetadata(
                    sinceProperty: "employeeID",
                    sinceNodeType: "User",
                    sinceNodeKeyPath: "id",
                    targetProperty: "companyID",
                    targetNodeType: "Company",
                    targetNodeKeyPath: "id"
                ))
            }

            extension WorksAt: GraphEdgeModel {
            }
            """,
            macros: [
                "GraphEdge": GraphEdgeMacro.self,
                "Since": SinceMacro.self,
                "Target": TargetMacro.self,
                "Default": DefaultMacro.self
            ]
        )
    }

    @Test("GraphEdge missing @Since property - should fail")
    func graphEdgeMissingSince() throws {
        assertMacroExpansion(
            """
            @GraphEdge
            struct Authored {
                @Target(\\Post.id) var post: Post
            }
            """,
            expandedSource: """
            struct Authored {
                var post: Post
            }

            extension Authored: GraphEdgeModel {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@GraphEdge requires at least one property marked with @Since",
                    line: 1,
                    column: 1,
                    severity: .error
                )
            ],
            macros: [
                "GraphEdge": GraphEdgeMacro.self,
                "Target": TargetMacro.self
            ]
        )
    }

    @Test("GraphEdge missing @Target property - should fail")
    func graphEdgeMissingTarget() throws {
        assertMacroExpansion(
            """
            @GraphEdge
            struct Authored {
                @Since(\\User.id) var author: User
            }
            """,
            expandedSource: """
            struct Authored {
                var author: User
            }

            extension Authored: GraphEdgeModel {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@GraphEdge requires at least one property marked with @Target",
                    line: 1,
                    column: 1,
                    severity: .error
                )
            ],
            macros: [
                "GraphEdge": GraphEdgeMacro.self,
                "Since": SinceMacro.self
            ]
        )
    }
}
