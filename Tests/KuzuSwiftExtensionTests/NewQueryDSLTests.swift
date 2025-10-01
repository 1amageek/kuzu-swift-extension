import Testing
import Foundation
@testable import KuzuSwiftExtension
import Kuzu

@GraphNode
struct QueryTestUser: Codable {
    @ID var id: UUID
    var name: String
    var age: Int
}

@GraphNode
struct QueryTestPost: Codable {
    @ID var id: UUID
    var title: String
    var content: String
}

@GraphEdge
struct QueryTestWrote: Codable {
    @Since(\QueryTestUser.id) var authorID: String
    @Target(\QueryTestPost.id) var postID: String
    var createdAt: Date
}

struct NewQueryDSLTests {
    
    func setupGraph() throws -> GraphContext {
        let container = try GraphContainer(configuration: GraphConfiguration(databasePath: ":memory:"))
        let graph = GraphContext(container)
        
        // Create schema
        try graph.raw(QueryTestUser._kuzuDDL)
        try graph.raw(QueryTestPost._kuzuDDL)
        try graph.raw(QueryTestWrote._kuzuDDL)
        
        return graph
    }
    
    @Test("Simple node query")
    func simpleNodeQuery() throws {
        let graph = try setupGraph()
        
        // Insert test data
        let user1 = QueryTestUser(id: UUID(), name: "Alice", age: 30)
        let user2 = QueryTestUser(id: UUID(), name: "Bob", age: 25)
        
        try graph.raw("""
            CREATE (u:QueryTestUser {id: $id, name: $name, age: $age})
            """, bindings: ["id": user1.id.uuidString, "name": user1.name, "age": user1.age])
        
        try graph.raw("""
            CREATE (u:QueryTestUser {id: $id, name: $name, age: $age})
            """, bindings: ["id": user2.id.uuidString, "name": user2.name, "age": user2.age])
        
        // Test new Query DSL
        let users = try graph.query {
            QueryTestUser.where(\.age > 20)
        }
        
        #expect(users.count == 2)
    }
    
    @Test("Complex query with tuple result")
    func complexQuery() throws {
        let graph = try setupGraph()
        
        // Insert test data
        let user = QueryTestUser(id: UUID(), name: "Charlie", age: 35)
        let post = QueryTestPost(id: UUID(), title: "Hello World", content: "Test content")
        
        try graph.raw("""
            CREATE (u:QueryTestUser {id: $uid, name: $name, age: $age})
            CREATE (p:QueryTestPost {id: $pid, title: $title, content: $content})
            CREATE (u)-[:QueryTestWrote {createdAt: timestamp($createdAt)}]->(p)
            """, bindings: [
                "uid": user.id.uuidString,
                "name": user.name,
                "age": user.age,
                "pid": post.id.uuidString,
                "title": post.title,
                "content": post.content,
                "createdAt": ISO8601DateFormatter().string(from: Date())
            ])
        
        // Test tuple query - no need for TupleQuery2!
        let (authors, posts) = try graph.query {
            QueryTestUser.where(\.name == "Charlie")
            QueryTestPost.match()
        }
        
        #expect(authors.first?.name == "Charlie")
        #expect(posts.first?.title == "Hello World")
    }
    
    @Test("Aggregation queries")
    func aggregation() throws {
        let graph = try setupGraph()
        
        // Insert test data
        for i in 1...5 {
            try graph.raw("""
                CREATE (u:QueryTestUser {id: $id, name: $name, age: $age})
                """, bindings: ["id": UUID().uuidString, "name": "User\(i)", "age": i * 10])
        }
        
        // Test count
        let count = try graph.query {
            Count<QueryTestUser>(nodeRef: QueryTestUser.match())
        }
        
        #expect(count == 5)
        
        // Test average  
        let avgAge = try graph.query {
            Average(nodeRef: QueryTestUser.match(), keyPath: \QueryTestUser.age)
        }
        
        #expect(avgAge == 30.0)
    }
}