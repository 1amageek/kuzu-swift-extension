import XCTest
import KuzuSwiftMacros
import KuzuSwiftExtension

@GraphNode
struct User {
    @ID var id: String
    @Index var name: String
    var email: String?
    var age: Int
    @Timestamp var createdAt: Date
}

@GraphNode
struct Post {
    @ID var id: String
    var title: String
    var content: String
    @Vector(dimensions: 1536) var embedding: [Double]
    @Timestamp var createdAt: Date
}

@GraphEdge(from: User.self, to: Post.self)
struct Authored {
    @ID var id: String
    var authoredAt: Date
    var role: String?
}

final class MacroExampleTests: XCTestCase {
    
    func testUserNodeDDL() {
        let expectedDDL = "CREATE NODE TABLE User (id STRING PRIMARY KEY, name STRING, email STRING, age INT64, createdAt TIMESTAMP)"
        XCTAssertEqual(User._kuzuDDL, expectedDDL)
    }
    
    func testUserNodeColumns() {
        XCTAssertEqual(User._kuzuColumns.count, 5)
        
        let idColumn = User._kuzuColumns[0]
        XCTAssertEqual(idColumn.name, "id")
        XCTAssertEqual(idColumn.type, "STRING")
        XCTAssertEqual(idColumn.constraints, ["PRIMARY KEY"])
        
        let nameColumn = User._kuzuColumns[1]
        XCTAssertEqual(nameColumn.name, "name")
        XCTAssertEqual(nameColumn.type, "STRING")
        XCTAssertEqual(nameColumn.constraints, ["INDEX"])
    }
    
    func testPostNodeWithVector() {
        let expectedDDL = "CREATE NODE TABLE Post (id STRING PRIMARY KEY, title STRING, content STRING, embedding DOUBLE[1536], createdAt TIMESTAMP)"
        XCTAssertEqual(Post._kuzuDDL, expectedDDL)
        
        let embeddingColumn = Post._kuzuColumns[3]
        XCTAssertEqual(embeddingColumn.name, "embedding")
        XCTAssertEqual(embeddingColumn.type, "DOUBLE[1536]")
    }
    
    func testAuthoredEdgeDDL() {
        let expectedDDL = "CREATE REL TABLE Authored (FROM User TO Post, id STRING PRIMARY KEY, authoredAt TIMESTAMP, role STRING)"
        XCTAssertEqual(Authored._kuzuDDL, expectedDDL)
    }
    
    func testProtocolConformance() {
        XCTAssertTrue((User.self as Any) is _KuzuGraphModel.Type)
        XCTAssertTrue((Post.self as Any) is _KuzuGraphModel.Type)
        XCTAssertTrue((Authored.self as Any) is _KuzuGraphModel.Type)
    }
}