import KuzuSwiftExtension
import Foundation

@GraphNode
struct TestUser: Codable, Sendable {
    @ID var id: UUID = UUID()
    @Unique var email: String
    var name: String
    @Default("active") var status: String = "active"
    var age: Int
}

@GraphNode
struct TestPost: Codable, Sendable {
    @ID var id: UUID = UUID()
    var title: String
    @FullTextSearch var content: String
    var authorId: UUID
}

@GraphEdge(from: TestUser.self, to: TestPost.self)
struct TestAuthored: Codable, Sendable {
    var authoredAt: Date = Date()
    var metadata: String?
}

print("TestUser DDL: \(TestUser._kuzuDDL)")
print("TestPost DDL: \(TestPost._kuzuDDL)")
print("TestAuthored DDL: \(TestAuthored._kuzuDDL)")