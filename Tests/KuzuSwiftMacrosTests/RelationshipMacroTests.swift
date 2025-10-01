import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import KuzuSwiftMacrosPlugin

@Suite("Relationship Macro Tests")
struct RelationshipMacroTests {

    @Test("Relationship with default delete rule")
    func defaultDeleteRule() throws {
        assertMacroExpansion(
            """
            @GraphEdge(from: User.self, to: Post.self)
            struct Authored: Codable {
                @ID var id: String
                @Relationship var metadata: String?
            }
            """,
            expandedSource: """
            struct Authored: Codable {
                var id: String
                var metadata: String?
            }
            """,
            macros: ["GraphEdge": GraphEdgeMacro.self, "ID": IDMacro.self, "Relationship": RelationshipMacro.self]
        )
    }

    @Test("Relationship with cascade delete")
    func cascadeDelete() throws {
        assertMacroExpansion(
            """
            @GraphEdge(from: User.self, to: Post.self)
            struct Authored: Codable {
                @ID var id: String
                @Relationship(deleteRule: .cascade) var metadata: String?
            }
            """,
            expandedSource: """
            struct Authored: Codable {
                var id: String
                var metadata: String?
            }
            """,
            macros: ["GraphEdge": GraphEdgeMacro.self, "ID": IDMacro.self, "Relationship": RelationshipMacro.self]
        )
    }

    @Test("Relationship with deny delete")
    func denyDelete() throws {
        assertMacroExpansion(
            """
            @GraphEdge(from: User.self, to: Post.self)
            struct Authored: Codable {
                @ID var id: String
                @Relationship(deleteRule: .deny) var metadata: String?
            }
            """,
            expandedSource: """
            struct Authored: Codable {
                var id: String
                var metadata: String?
            }
            """,
            macros: ["GraphEdge": GraphEdgeMacro.self, "ID": IDMacro.self, "Relationship": RelationshipMacro.self]
        )
    }

    @Test("Relationship with inverse")
    func relationshipWithInverse() throws {
        assertMacroExpansion(
            """
            @GraphEdge(from: User.self, to: Post.self)
            struct Authored: Codable {
                @ID var id: String
                @Relationship(inverse: "author") var metadata: String?
            }
            """,
            expandedSource: """
            struct Authored: Codable {
                var id: String
                var metadata: String?
            }
            """,
            macros: ["GraphEdge": GraphEdgeMacro.self, "ID": IDMacro.self, "Relationship": RelationshipMacro.self]
        )
    }

    @Test("Relationship with cascade and inverse")
    func cascadeWithInverse() throws {
        assertMacroExpansion(
            """
            @GraphEdge(from: User.self, to: Post.self)
            struct Authored: Codable {
                @ID var id: String
                @Relationship(deleteRule: .cascade, inverse: "author") var metadata: String?
            }
            """,
            expandedSource: """
            struct Authored: Codable {
                var id: String
                var metadata: String?
            }
            """,
            macros: ["GraphEdge": GraphEdgeMacro.self, "ID": IDMacro.self, "Relationship": RelationshipMacro.self]
        )
    }
}
