import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import KuzuSwiftMacrosPlugin

@Suite("Transient Macro Tests")
struct TransientMacroTests {

    @Test("Transient property excluded from DDL")
    func transientExcludedFromDDL() throws {
        assertMacroExpansion(
            """
            @GraphNode
            struct User: Codable {
                @ID var id: String
                var name: String

                @Transient
                var displayName: String
            }
            """,
            expandedSource: """
            struct User: Codable {
                var id: String
                var name: String
                var displayName: String

                public static let _kuzuDDL: String = "CREATE NODE TABLE User (id STRING PRIMARY KEY, name STRING)"

                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "id", type: "STRING", constraints: ["PRIMARY KEY"]), (name: "name", type: "STRING", constraints: [])]
            }

            extension User: GraphNodeModel {
            }
            """,
            macros: ["GraphNode": GraphNodeMacro.self, "ID": IDMacro.self, "Transient": TransientMacro.self]
        )
    }

    @Test("Transient with computed property")
    func transientWithComputedProperty() throws {
        assertMacroExpansion(
            """
            @GraphNode
            struct User: Codable {
                @ID var id: String
                var firstName: String
                var lastName: String

                @Transient
                var fullName: String {
                    "\\(firstName) \\(lastName)"
                }
            }
            """,
            expandedSource: """
            struct User: Codable {
                var id: String
                var firstName: String
                var lastName: String
                var fullName: String {
                    "\\(firstName) \\(lastName)"
                }

                public static let _kuzuDDL: String = "CREATE NODE TABLE User (id STRING PRIMARY KEY, firstName STRING, lastName STRING)"

                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "id", type: "STRING", constraints: ["PRIMARY KEY"]), (name: "firstName", type: "STRING", constraints: []), (name: "lastName", type: "STRING", constraints: [])]
            }

            extension User: GraphNodeModel {
            }
            """,
            macros: ["GraphNode": GraphNodeMacro.self, "ID": IDMacro.self, "Transient": TransientMacro.self]
        )
    }

    @Test("Multiple transient properties")
    func multipleTransientProperties() throws {
        assertMacroExpansion(
            """
            @GraphNode
            struct Product: Codable {
                @ID var id: String
                var price: Double

                @Transient
                var formattedPrice: String

                @Transient
                var displayName: String
            }
            """,
            expandedSource: """
            struct Product: Codable {
                var id: String
                var price: Double
                var formattedPrice: String
                var displayName: String

                public static let _kuzuDDL: String = "CREATE NODE TABLE Product (id STRING PRIMARY KEY, price DOUBLE)"

                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "id", type: "STRING", constraints: ["PRIMARY KEY"]), (name: "price", type: "DOUBLE", constraints: [])]
            }

            extension Product: GraphNodeModel {
            }
            """,
            macros: ["GraphNode": GraphNodeMacro.self, "ID": IDMacro.self, "Transient": TransientMacro.self]
        )
    }
}
