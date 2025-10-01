import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import KuzuSwiftMacrosPlugin

@Suite("Attribute Macro Tests")
struct AttributeMacroTests {

    @Test("Attribute with spotlight option")
    func spotlightOption() throws {
        assertMacroExpansion(
            """
            @GraphNode
            struct Article: Codable {
                @ID var id: String
                @Attribute(.spotlight) var content: String
            }
            """,
            expandedSource: """
            struct Article: Codable {
                var id: String
                var content: String

                public static let _kuzuDDL: String = "CREATE NODE TABLE Article (id STRING PRIMARY KEY, content STRING)"

                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "id", type: "STRING", constraints: ["PRIMARY KEY"]), (name: "content", type: "STRING", constraints: ["FULLTEXT"])]

                public static let _metadata = GraphMetadata(
                    vectorProperties: [],
                    fullTextSearchProperties: [FullTextSearchPropertyMetadata(propertyName: "content", stemmer: "porter")]
                )
            }

            extension Article: GraphNodeModel {
            }
            """,
            macros: ["GraphNode": GraphNodeMacro.self, "ID": IDMacro.self, "Attribute": AttributeMacro.self]
        )
    }

    @Test("CodingKeys with custom column names")
    func codingKeysColumnMapping() throws {
        assertMacroExpansion(
            """
            @GraphNode
            struct User: Codable {
                enum CodingKeys: String, CodingKey {
                    case id
                    case userName = "user_name"
                }

                @ID var id: String
                var userName: String
            }
            """,
            expandedSource: """
            struct User: Codable {
                enum CodingKeys: String, CodingKey {
                    case id
                    case userName = "user_name"
                }

                var id: String
                var userName: String

                public static let _kuzuDDL: String = "CREATE NODE TABLE User (id STRING PRIMARY KEY, user_name STRING)"

                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "id", type: "STRING", constraints: ["PRIMARY KEY"]), (name: "user_name", type: "STRING", constraints: [])]

                public static let _metadata = GraphMetadata(
                    vectorProperties: [],
                    fullTextSearchProperties: []
                )
            }

            extension User: GraphNodeModel {
            }
            """,
            macros: ["GraphNode": GraphNodeMacro.self, "ID": IDMacro.self]
        )
    }
}
