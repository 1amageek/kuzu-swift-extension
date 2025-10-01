import Testing
import Foundation
import Kuzu
import KuzuSwiftMacros
@testable import KuzuSwiftExtension

// SwiftData-style model definitions
@GraphNode
fileprivate struct User: Codable {
    @ID var id: Int
    var name: String
    var email: String
    var username: String

    @Transient
    var displayName: String {
        "\(name) (@\(username))"
    }

    var createdAt: Date

    @Default(0)
    var points: Int
}

@GraphNode
fileprivate struct Article: Codable {
    @ID var id: Int
    var title: String

    @Attribute(.spotlight)
    var content: String

    var slug: String
}

@GraphNode
fileprivate struct Person: Codable {
    @ID var id: Int
    var firstName: String
    var lastName: String
    var age: Int

    @Transient
    var fullName: String {
        "\(firstName) \(lastName)"
    }
}

@Suite("SwiftData Compatibility Tests")
struct SwiftDataCompatibilityTests {

    @Test("SwiftData-style container initialization")
    func containerInitialization() throws {
        // SwiftData pattern: ModelContainer(for: User.self, Post.self)
        let container = try GraphContainer(
            for: User.self, Article.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )

        #expect(container.models.count == 2)
    }

    @Test("Transient properties excluded from persistence")
    func transientExclusion() throws {
        let container = try GraphContainer(
            for: User.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        let user = User(
            id: 1,
            name: "Alice",
            email: "alice@example.com",
            username: "alice",
            createdAt: Date(),
            points: 100
        )
        context.insert(user)
        try context.save()

        // Verify DDL doesn't include displayName
        #expect(!User._kuzuDDL.contains("displayName"))

        // Verify columns don't include displayName
        let columns = User._kuzuColumns.map { $0.name }
        #expect(!columns.contains("displayName"))
    }

    @Test("Attribute spotlight option for full-text search")
    func attributeSpotlightOption() throws {
        _ = try GraphContainer(
            for: Article.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )

        // Verify spotlight (FULLTEXT) constraint in columns metadata
        let contentColumn = Article._kuzuColumns.first { $0.name == "content" }
        #expect(contentColumn?.constraints.contains("FULLTEXT") == true)

        // Verify Full-Text Search metadata is generated
        #expect(Article._metadata.fullTextSearchProperties.count == 1)
        #expect(Article._metadata.fullTextSearchProperties[0].propertyName == "content")
    }

    @Test("Default value macro")
    func defaultValue() throws {
        _ = try GraphContainer(
            for: User.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )

        // Verify DEFAULT constraint
        let pointsColumn = User._kuzuColumns.first { $0.name == "points" }
        #expect(pointsColumn?.constraints.contains("DEFAULT 0") == true)
    }

    @Test("Full SwiftData-style workflow")
    func fullWorkflow() throws {
        // 1. Create container (SwiftData: ModelContainer(for:))
        let container = try GraphContainer(
            for: User.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )

        // 2. Get context (SwiftData: container.mainContext)
        let context = GraphContext(container)

        // 3. Insert data (SwiftData: context.insert())
        let user = User(
            id: 1,
            name: "Bob",
            email: "bob@example.com",
            username: "bob",
            createdAt: Date(),
            points: 50
        )
        context.insert(user)

        // 4. Save (SwiftData: try context.save())
        try context.save()

        // 5. Query
        let result = try context.raw("MATCH (u:User) WHERE u.email = 'bob@example.com' RETURN u.name AS name")
        #expect(result.hasNext())

        if let row = try result.getNext(),
           let name = try row.getValue(0) as? String {
            #expect(name == "Bob")
        }
    }

    @Test("Multiple models with mixed features")
    func mixedFeatures() throws {
        let container = try GraphContainer(
            for: User.self, Article.self, Person.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Insert data into all models
        context.insert(User(id: 1, name: "Alice", email: "alice@example.com", username: "alice", createdAt: Date(), points: 100))
        context.insert(Article(id: 1, title: "Test", content: "Content", slug: "test"))
        context.insert(Person(id: 1, firstName: "John", lastName: "Doe", age: 30))
        try context.save()

        // Verify all tables exist
        let userResult = try context.raw("MATCH (u:User) RETURN count(u) AS count")
        #expect(userResult.hasNext())

        let articleResult = try context.raw("MATCH (a:Article) RETURN count(a) AS count")
        #expect(articleResult.hasNext())

        let personResult = try context.raw("MATCH (p:Person) RETURN count(p) AS count")
        #expect(personResult.hasNext())
    }
}
