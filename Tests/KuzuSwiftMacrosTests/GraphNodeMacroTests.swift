import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import KuzuSwiftMacrosPlugin

@Suite("Graph Node Macro Tests")
struct GraphNodeMacroTests {
    
    @Test("GraphNode macro expansion")
    func graphNodeMacro() throws {
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
            
                public static let _kuzuDDL: String = "CREATE NODE TABLE User (id STRING PRIMARY KEY, name STRING, email STRING, age INT64, createdAt TIMESTAMP)"
            
                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "id", type: "STRING", constraints: ["PRIMARY KEY"]), (name: "name", type: "STRING", constraints: ["INDEX"]), (name: "email", type: "STRING", constraints: []), (name: "age", type: "INT64", constraints: []), (name: "createdAt", type: "TIMESTAMP", constraints: [])]
            }
            
            extension User: GraphNodeModel {
            }
            """,
            macros: ["GraphNode": GraphNodeMacro.self, "ID": IDMacro.self, "Index": IndexMacro.self, "Timestamp": TimestampMacro.self]
        )
    }
    
    @Test("GraphNode with Double Vector")
    func graphNodeWithDoubleVector() throws {
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

                public static let _kuzuDDL: String = "CREATE NODE TABLE Document (id STRING PRIMARY KEY, content STRING, embedding DOUBLE[1536])"

                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "id", type: "STRING", constraints: ["PRIMARY KEY"]), (name: "content", type: "STRING", constraints: []), (name: "embedding", type: "DOUBLE[1536]", constraints: [])]
            }

            extension Document: GraphNodeModel {
            }
            """,
            macros: ["GraphNode": GraphNodeMacro.self, "ID": IDMacro.self, "Vector": VectorMacro.self]
        )
    }

    @Test("GraphNode with Float Vector")
    func graphNodeWithFloatVector() throws {
        assertMacroExpansion(
            """
            @GraphNode
            struct Item {
                @ID var id: String
                var name: String
                @Vector(dimensions: 384) var embedding: [Float]
            }
            """,
            expandedSource: """
            struct Item {
                var id: String
                var name: String
                var embedding: [Float]

                public static let _kuzuDDL: String = "CREATE NODE TABLE Item (id STRING PRIMARY KEY, name STRING, embedding FLOAT[384])"

                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "id", type: "STRING", constraints: ["PRIMARY KEY"]), (name: "name", type: "STRING", constraints: []), (name: "embedding", type: "FLOAT[384]", constraints: [])]
            }

            extension Item: GraphNodeModel {
            }
            """,
            macros: ["GraphNode": GraphNodeMacro.self, "ID": IDMacro.self, "Vector": VectorMacro.self]
        )
    }
    
    @Test("GraphNode with FullTextSearch")
    func graphNodeWithFullTextSearch() throws {
        assertMacroExpansion(
            """
            @GraphNode
            struct Article {
                @ID var id: String
                var title: String
                @FullTextSearch var content: String
            }
            """,
            expandedSource: """
            struct Article {
                var id: String
                var title: String
                var content: String
            
                public static let _kuzuDDL: String = "CREATE NODE TABLE Article (id STRING PRIMARY KEY, title STRING, content STRING)"
            
                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "id", type: "STRING", constraints: ["PRIMARY KEY"]), (name: "title", type: "STRING", constraints: []), (name: "content", type: "STRING", constraints: ["FULLTEXT"])]
            }
            
            extension Article: GraphNodeModel {
            }
            """,
            macros: ["GraphNode": GraphNodeMacro.self, "ID": IDMacro.self, "FullTextSearch": FullTextSearchMacro.self]
        )
    }
    
    @Test("GraphNode with Unique and Default")
    func graphNodeWithUniqueAndDefault() throws {
        assertMacroExpansion(
            """
            @GraphNode
            struct Account {
                @ID var id: String
                @Unique var username: String
                @Default("active") var status: String
                var balance: Double
            }
            """,
            expandedSource: """
            struct Account {
                var id: String
                var username: String
                var status: String
                var balance: Double
            
                public static let _kuzuDDL: String = "CREATE NODE TABLE Account (id STRING PRIMARY KEY, username STRING UNIQUE, status STRING DEFAULT 'active', balance DOUBLE)"
            
                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "id", type: "STRING", constraints: ["PRIMARY KEY"]), (name: "username", type: "STRING", constraints: ["UNIQUE"]), (name: "status", type: "STRING", constraints: ["DEFAULT 'active'"]), (name: "balance", type: "DOUBLE", constraints: [])]
            }
            
            extension Account: GraphNodeModel {
            }
            """,
            macros: ["GraphNode": GraphNodeMacro.self, "ID": IDMacro.self, "Unique": UniqueMacro.self, "Default": DefaultMacro.self]
        )
    }
}