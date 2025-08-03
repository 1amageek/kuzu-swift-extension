import XCTest
import KuzuSwiftMacros
import KuzuSwiftExtension

// Example models using our macros
@GraphNode
struct Person {
    @ID var id: String
    @Index var name: String
    var age: Int
    var email: String?
    @Timestamp var createdAt: Date
}

@GraphNode
struct Movie {
    @ID var id: String
    var title: String
    var releaseYear: Int
    @Vector(dimensions: 384) var embedding: [Double]
}

@GraphEdge(from: Person.self, to: Movie.self)
struct ActedIn {
    @ID var id: String
    var role: String
    var year: Int
}

final class IntegrationTests: XCTestCase {
    
    func testBasicUsage() async throws {
        // Create in-memory database
        let config = GraphConfiguration(
            databasePath: ":memory:",
            options: .init(
                extensions: [.vector],
                migrationPolicy: .safeOnly
            )
        )
        
        let context = try await GraphContext(configuration: config)
        
        // Create schema from models
        try await context.createSchema(for: [
            Person.self,
            Movie.self,
            ActedIn.self
        ])
        
        // Create nodes using raw queries
        let createPerson = """
            CREATE (p:Person {
                id: $id,
                name: $name,
                age: $age,
                email: $email,
                createdAt: $createdAt
            })
        """
        
        _ = try await context.raw(createPerson, bindings: [
            "id": "person1",
            "name": "Tom Hanks",
            "age": 67,
            "email": "tom@example.com",
            "createdAt": Date()
        ])
        
        // Query the created node
        let queryPerson = "MATCH (p:Person {id: $id}) RETURN p"
        let result = try await context.raw(queryPerson, bindings: ["id": "person1"])
        
        XCTAssertTrue(result.hasNextQueryResult())
    }
    
    func testQueryDSL() async throws {
        let config = GraphConfiguration()
        let context = try await GraphContext(configuration: config)
        
        // Create schema
        try await context.createSchema(for: [Person.self, Movie.self, ActedIn.self])
        
        // Test Create clause compilation
        let createQuery = Create.node(Person.self, properties: [
            "id": "p1",
            "name": "Test Person",
            "age": 30,
            "createdAt": Date()
        ])
        
        let cypher = try createQuery.toCypher()
        XCTAssertTrue(cypher.query.contains("CREATE (person:Person"))
        XCTAssertEqual(cypher.parameters.count, 4)
        
        // Test Match clause compilation
        let matchQuery = Match.node(Person.self)
        let matchCypher = try matchQuery.toCypher()
        XCTAssertEqual(matchCypher.query, "MATCH (person:Person)")
        
        // Test Return clause compilation
        let returnQuery = Return.items(.alias("person"))
        let returnCypher = try returnQuery.toCypher()
        XCTAssertEqual(returnCypher.query, "RETURN person")
    }
    
    func testCypherCompiler() throws {
        let query = Query(components: [
            Match.node(Person.self, alias: "p"),
            Return.items(.property(alias: "p", property: "name"))
        ])
        
        let compiled = try CypherCompiler.compile(query)
        XCTAssertEqual(compiled.query, "MATCH (p:Person) RETURN p.name")
        XCTAssertTrue(compiled.parameters.isEmpty)
    }
    
    func testSchemaDiscovery() {
        let schema = GraphSchema.discover(from: [
            Person.self,
            Movie.self,
            ActedIn.self
        ])
        
        XCTAssertEqual(schema.nodes.count, 2)
        XCTAssertEqual(schema.edges.count, 1)
        
        let personNode = schema.nodes.first { $0.name == "Person" }
        XCTAssertNotNil(personNode)
        XCTAssertEqual(personNode?.columns.count, 5)
        
        let actedInEdge = schema.edges.first { $0.name == "ActedIn" }
        XCTAssertNotNil(actedInEdge)
        XCTAssertEqual(actedInEdge?.from, "Person")
        XCTAssertEqual(actedInEdge?.to, "Movie")
    }
}