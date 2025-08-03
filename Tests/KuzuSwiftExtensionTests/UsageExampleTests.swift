import Testing
import Foundation
@testable import KuzuSwiftExtension

// MARK: - Example Models

@GraphNode
struct Person {
    @ID var id: UUID
    @Index var name: String
    var age: Int?
    @Vector(dimensions: 128) var embedding: [Float]?
    @FTS var bio: String?
}

@GraphNode
struct City {
    @ID var id: UUID
    @Index(unique: true) var name: String
    var population: Int
    var country: String
}

@GraphEdge(from: Person.self, to: Person.self)
struct Follows {
    @Timestamp(default: .now) var since: Date
    var isClose: Bool = false
}

@GraphEdge(from: Person.self, to: City.self)
struct LivesIn {
    @Timestamp(default: .now) var since: Date
    var address: String?
}

// MARK: - Usage Examples

@Test func exampleUsage() async throws {
    // 1. Setup
    let schema = GraphSchema(Person.self, City.self, Follows.self, LivesIn.self)
    
    let config = GraphConfiguration(
        schema: schema,
        inMemory: true,
        name: "test",
        options: .init(
            extensions: [.vector, .fts, .algo]
        )
    )
    
    let container = try await GraphContainer(for: schema, config)
    let context = container.defaultContext
    
    // 2. Create Data
    let alice = Person(
        id: UUID(),
        name: "Alice",
        age: 30,
        embedding: Array(repeating: 0.1, count: 128),
        bio: "Software engineer passionate about graphs"
    )
    
    let bob = Person(
        id: UUID(),
        name: "Bob",
        age: 28,
        embedding: Array(repeating: 0.2, count: 128),
        bio: "Data scientist working on ML"
    )
    
    let tokyo = City(
        id: UUID(),
        name: "Tokyo",
        population: 14_000_000,
        country: "Japan"
    )
    
    // 3. Insert data
    context.insert(alice)
    context.insert(bob)
    context.insert(tokyo)
    try await context.save()
    
    // 4. Query using DSL
    let people = try await context.query {
        Match(Person.self)
            .where(\.age > 25)
        Return.variable("person")
    }
    
    // 5. Create relationships
    let follows = Follows(since: Date(), isClose: true)
    try await context.raw("""
        MATCH (a:Person {id: $1}), (b:Person {id: $2})
        CREATE (a)-[:Follows {since: $3, isClose: $4}]->(b)
        """, bindings: [
            "1": alice.id,
            "2": bob.id,
            "3": follows.since,
            "4": follows.isClose
        ])
    
    // 6. Path queries
    let paths = try await context.query {
        Match(Person.self, as: "p1")
            .where(\.name == "Alice")
        Match(Person.self, as: "p2")
            .where(\.name == "Bob")
        Return.property("p1", "name")
        Return.property("p2", "name")
    }
    
    // 7. Graph algorithms
    let pageRankResults = try await context.algo.pageRank(Person.self)
    
    // 8. Vector search
    let similarPeople = try await context.vector.similaritySearch(
        in: Person.self,
        vector: Array(repeating: 0.15, count: 128),
        property: "embedding",
        topK: 5
    )
    
    // 9. Full-text search
    let searchResults = try await context.fts.search(
        in: Person.self,
        property: "bio",
        query: "engineer OR scientist"
    )
    
    // 10. Complex query with multiple operations
    let complexResults = try await context.query {
        Match(Person.self, as: "person")
            .where(\.age > 25)
        Match(City.self, as: "city")
            .where(\.population > 1_000_000)
        Create(LivesIn.self, as: "lives", properties: [
            "since": Date(),
            "address": "123 Main St"
        ])
        Return.variable("person")
        Return.variable("city")
    }
    
    #expect(true) // Tests would verify actual results
}

@Test func examplePathTraversal() async throws {
    // Example of path traversal DSL
    let pathQuery = Path("friendPath") {
        NodePattern(Person.self, as: "start")
            .to(Person.self, via: Follows.self, hops: 1...3, as: "friend")
            .to(City.self, via: LivesIn.self, as: "city")
    }
    
    // This would be compiled to:
    // MATCH friendPath = (start:Person)-[:Follows*1..3]->(friend:Person)-[:LivesIn]->(city:City)
    
    #expect(true)
}

@Test func exampleAdvancedFTS() async throws {
    // Advanced FTS query building
    let query = FTSQuery()
        .phrase("software engineer")
        .and(
            FTSQuery()
                .term("graph", boost: 2.0)
                .or(FTSQuery().term("database"))
        )
        .not(FTSQuery().term("junior"))
    
    // This would generate:
    // "software engineer" AND (graph^2.0 OR database) NOT (junior)
    
    #expect(true)
}