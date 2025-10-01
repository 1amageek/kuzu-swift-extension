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
                var name: String
                var email: String?
                var age: Int
                var createdAt: Date
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

                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "id", type: "STRING", constraints: ["PRIMARY KEY"]), (name: "name", type: "STRING", constraints: []), (name: "email", type: "STRING", constraints: []), (name: "age", type: "INT64", constraints: []), (name: "createdAt", type: "TIMESTAMP", constraints: [])]

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
    
    @Test("GraphNode with Attribute spotlight")
    func graphNodeWithAttributeSpotlight() throws {
        assertMacroExpansion(
            """
            @GraphNode
            struct Article {
                @ID var id: String
                var title: String
                @Attribute(.spotlight) var content: String
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
            macros: ["GraphNode": GraphNodeMacro.self, "ID": IDMacro.self, "Attribute": AttributeMacro.self]
        )
    }
    
    @Test("GraphNode with computed properties should exclude them")
    func graphNodeWithComputedProperties() throws {
        assertMacroExpansion(
            """
            @GraphNode
            struct PhotoAsset {
                @ID var id: String
                @Vector(dimensions: 3) var labColor: [Float]
                var enabled: Bool
                var creationDate: Date?

                var labColorObject: LabColor {
                    return LabColor(L: labColor[0], a: labColor[1], b: labColor[2])
                }
            }
            """,
            expandedSource: """
            struct PhotoAsset {
                var id: String
                var labColor: [Float]
                var enabled: Bool
                var creationDate: Date?

                var labColorObject: LabColor {
                    return LabColor(L: labColor[0], a: labColor[1], b: labColor[2])
                }

                public static let _kuzuDDL: String = "CREATE NODE TABLE PhotoAsset (id STRING PRIMARY KEY, labColor FLOAT[3], enabled BOOLEAN, creationDate TIMESTAMP)"

                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "id", type: "STRING", constraints: ["PRIMARY KEY"]), (name: "labColor", type: "FLOAT[3]", constraints: []), (name: "enabled", type: "BOOLEAN", constraints: []), (name: "creationDate", type: "TIMESTAMP", constraints: [])]
            }

            extension PhotoAsset: GraphNodeModel {
            }
            """,
            macros: ["GraphNode": GraphNodeMacro.self, "ID": IDMacro.self, "Vector": VectorMacro.self]
        )
    }

    @Test("GraphNode with explicit CodingKeys should respect them")
    func graphNodeWithExplicitCodingKeys() throws {
        assertMacroExpansion(
            """
            @GraphNode
            struct Product {
                enum CodingKeys: String, CodingKey {
                    case id
                    case name
                    case price
                }

                @ID var id: String
                var name: String
                var price: Double
                var internalNotes: String
            }
            """,
            expandedSource: """
            struct Product {
                enum CodingKeys: String, CodingKey {
                    case id
                    case name
                    case price
                }

                var id: String
                var name: String
                var price: Double
                var internalNotes: String

                public static let _kuzuDDL: String = "CREATE NODE TABLE Product (id STRING PRIMARY KEY, name STRING, price DOUBLE)"

                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "id", type: "STRING", constraints: ["PRIMARY KEY"]), (name: "name", type: "STRING", constraints: []), (name: "price", type: "DOUBLE", constraints: [])]
            }

            extension Product: GraphNodeModel {
            }
            """,
            macros: ["GraphNode": GraphNodeMacro.self, "ID": IDMacro.self]
        )
    }

    @Test("GraphNode with both CodingKeys and computed properties")
    func graphNodeWithCodingKeysAndComputedProperties() throws {
        assertMacroExpansion(
            """
            @GraphNode
            struct Order {
                enum CodingKeys: String, CodingKey {
                    case id
                    case amount
                    case createdAt
                }

                @ID var id: String
                var amount: Double
                var createdAt: Date
                var computedTax: Double {
                    return amount * 0.1
                }
                var internalMemo: String
            }
            """,
            expandedSource: """
            struct Order {
                enum CodingKeys: String, CodingKey {
                    case id
                    case amount
                    case createdAt
                }

                var id: String
                var amount: Double
                var createdAt: Date
                var computedTax: Double {
                    return amount * 0.1
                }
                var internalMemo: String

                public static let _kuzuDDL: String = "CREATE NODE TABLE Order (id STRING PRIMARY KEY, amount DOUBLE, createdAt TIMESTAMP)"

                public static let _kuzuColumns: [(name: String, type: String, constraints: [String])] = [(name: "id", type: "STRING", constraints: ["PRIMARY KEY"]), (name: "amount", type: "DOUBLE", constraints: []), (name: "createdAt", type: "TIMESTAMP", constraints: [])]

                public static let _metadata = GraphMetadata(
                    vectorProperties: [],
                    fullTextSearchProperties: []
                )
            }

            extension Order: GraphNodeModel {
            }
            """,
            macros: ["GraphNode": GraphNodeMacro.self, "ID": IDMacro.self]
        )
    }
}