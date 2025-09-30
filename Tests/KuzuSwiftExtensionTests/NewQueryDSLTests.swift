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

@GraphEdge(from: QueryTestUser.self, to: QueryTestPost.self)
struct QueryTestWrote: Codable {
    var createdAt: Date
}

struct NewQueryDSLTests {
    
    func setupGraph() async throws -> GraphContext {
        let container = try await GraphContainer(configuration: GraphConfiguration(databasePath: ":memory:"))
        let graph = GraphContext(container)
        
        // Create schema
        try await graph.raw(QueryTestUser._kuzuDDL)
        try await graph.raw(QueryTestPost._kuzuDDL)
        try await graph.raw(QueryTestWrote._kuzuDDL)
        
        return graph
    }
    
    @Test("Simple node query")
    func simpleNodeQuery() async throws {
        let graph = try await setupGraph()
        
        // Insert test data
        let user1 = QueryTestUser(id: UUID(), name: "Alice", age: 30)
        let user2 = QueryTestUser(id: UUID(), name: "Bob", age: 25)
        
        try await graph.raw("""
            CREATE (u:QueryTestUser {id: $id, name: $name, age: $age})
            """, bindings: ["id": user1.id.uuidString, "name": user1.name, "age": user1.age])
        
        try await graph.raw("""
            CREATE (u:QueryTestUser {id: $id, name: $name, age: $age})
            """, bindings: ["id": user2.id.uuidString, "name": user2.name, "age": user2.age])
        
        // Test new Query DSL
        let users = try await graph.query {
            QueryTestUser.where(\.age > 20)
        }
        
        #expect(users.count == 2)
    }
    
    @Test("Complex query with tuple result")
    func complexQuery() async throws {
        let graph = try await setupGraph()
        
        // Insert test data
        let user = QueryTestUser(id: UUID(), name: "Charlie", age: 35)
        let post = QueryTestPost(id: UUID(), title: "Hello World", content: "Test content")
        
        try await graph.raw("""
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
        let (authors, posts) = try await graph.query {
            QueryTestUser.where(\.name == "Charlie")
            QueryTestPost.match()
        }
        
        #expect(authors.first?.name == "Charlie")
        #expect(posts.first?.title == "Hello World")
    }
    
    @Test("Aggregation queries")
    func aggregation() async throws {
        let graph = try await setupGraph()
        
        // Insert test data
        for i in 1...5 {
            try await graph.raw("""
                CREATE (u:QueryTestUser {id: $id, name: $name, age: $age})
                """, bindings: ["id": UUID().uuidString, "name": "User\(i)", "age": i * 10])
        }
        
        // Test count
        let count = try await graph.query {
            Count<QueryTestUser>(nodeRef: QueryTestUser.match())
        }
        
        #expect(count == 5)
        
        // Test average  
        let avgAge = try await graph.query {
            Average(nodeRef: QueryTestUser.match(), keyPath: \QueryTestUser.age)
        }
        
        #expect(avgAge == 30.0)
    }
}