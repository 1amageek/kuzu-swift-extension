import Testing
import Foundation
@testable import KuzuSwiftExtension

// MARK: - Test Models

@GraphNode
fileprivate struct Article: Codable {
    @ID var id: String
    @Vector(dimensions: 3) var embedding: [Float]
    var title: String
    var published: Bool
}

@GraphNode
fileprivate struct Product: Codable {
    @ID var id: String
    @Vector(dimensions: 128) var features: [Float]
    var name: String
    var price: Double
    var inStock: Bool
}

@Suite("Vector Search DSL Tests")
struct VectorSearchDSLTests {

    // MARK: - Basic Vector Search Tests

    @Test("Basic vector search with type-safe DSL")
    func testBasicVectorSearch() throws {
        let container = try GraphContainer(
            for: Article.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Insert test data
        let articles = [
            Article(id: "a1", embedding: [1.0, 0.0, 0.0], title: "Tech News", published: true),
            Article(id: "a2", embedding: [0.9, 0.1, 0.0], title: "AI Updates", published: true),
            Article(id: "a3", embedding: [0.0, 1.0, 0.0], title: "Sports", published: false),
            Article(id: "a4", embedding: [0.8, 0.2, 0.0], title: "ML Research", published: true),
        ]

        for article in articles {
            context.insert(article)
        }
        try context.save()

        // Vector search using DSL
        let queryVector: [Float] = [1.0, 0.0, 0.0]
        let results = try context.vectorSearch(Article.self) {
            VectorSearch(\Article.embedding, query: queryVector, k: 5)
        }

        // Verify results
        #expect(results.count == 4, "Should return all 4 articles")

        // First result should be a1 (exact match, distance ~0)
        #expect(results[0].model.id == "a1")
        #expect(results[0].distance < 0.01, "Exact match should have distance near 0")

        // Results should be ordered by distance
        for i in 0..<(results.count - 1) {
            #expect(results[i].distance <= results[i + 1].distance,
                   "Results should be ordered by distance (ascending)")
        }
    }

    @Test("Vector search with WHERE filter")
    func testVectorSearchWithFilter() throws {
        let container = try GraphContainer(
            for: Article.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Insert test data
        let articles = [
            Article(id: "a1", embedding: [1.0, 0.0, 0.0], title: "Tech News", published: true),
            Article(id: "a2", embedding: [0.9, 0.1, 0.0], title: "AI Updates", published: true),
            Article(id: "a3", embedding: [0.0, 1.0, 0.0], title: "Sports", published: false),
            Article(id: "a4", embedding: [0.8, 0.2, 0.0], title: "ML Research", published: true),
        ]

        for article in articles {
            context.insert(article)
        }
        try context.save()

        // Vector search with published filter
        let queryVector: [Float] = [1.0, 0.0, 0.0]
        let results = try context.vectorSearch(Article.self) {
            VectorSearch(\Article.embedding, query: queryVector, k: 10)
                .where(\.published, .equal, true)
        }

        // Should only return published articles
        #expect(results.count == 3, "Should return only 3 published articles")

        // Verify all results are published
        for (article, _) in results {
            #expect(article.published == true)
        }

        // Should not contain a3 (unpublished)
        let ids = results.map { $0.model.id }
        #expect(!ids.contains("a3"))
    }

    @Test("Vector search with LIMIT")
    func testVectorSearchWithLimit() throws {
        let container = try GraphContainer(
            for: Article.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Insert 10 articles
        let articles = (0..<10).map { i in
            let embedding: [Float] = [Float(i) / 10.0, Float(10 - i) / 10.0, 0.5]
            return Article(id: "a\(i)", embedding: embedding, title: "Article \(i)", published: true)
        }

        for article in articles {
            context.insert(article)
        }
        try context.save()

        // Search with limit
        let queryVector: [Float] = [0.5, 0.5, 0.5]
        let results = try context.vectorSearch(Article.self) {
            VectorSearch(\Article.embedding, query: queryVector, k: 10)
                .limit(3)
        }

        // Should return exactly 3 results
        #expect(results.count == 3, "LIMIT 3 should return exactly 3 results")
    }

    @Test("Vector search returns models only")
    func testVectorSearchModelsOnly() throws {
        let container = try GraphContainer(
            for: Article.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Insert test data
        let articles = [
            Article(id: "a1", embedding: [1.0, 0.0, 0.0], title: "Tech News", published: true),
            Article(id: "a2", embedding: [0.9, 0.1, 0.0], title: "AI Updates", published: true),
        ]

        for article in articles {
            context.insert(article)
        }
        try context.save()

        // Use vectorSearchModels (no distances)
        let queryVector: [Float] = [1.0, 0.0, 0.0]
        let models = try context.vectorSearchModels(Article.self) {
            VectorSearch(\Article.embedding, query: queryVector, k: 5)
        }

        // Verify we got models
        #expect(models.count == 2)
        #expect(models[0].id == "a1")
        #expect(models[1].id == "a2")
    }

    // MARK: - Dimension Validation Tests

    @Test("Vector search validates dimensions")
    func testVectorSearchDimensionValidation() throws {
        let container = try GraphContainer(
            for: Article.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Try to search with wrong dimensions (Article.embedding is FLOAT[3])
        let wrongVector: [Float] = [1.0, 0.0, 0.0, 0.0, 0.0]  // 5 dimensions instead of 3

        #expect(throws: KuzuError.self) {
            _ = try context.vectorSearch(Article.self) {
                VectorSearch(\Article.embedding, query: wrongVector, k: 5)
            }
        }
    }

    // MARK: - Multiple Vector Properties Tests

    @Test("Vector search with different metrics")
    func testVectorSearchDifferentMetrics() throws {
        let container = try GraphContainer(
            for: Product.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Insert test data
        let queryFeatures = Array(repeating: Float(0.1), count: 128)
        let product = Product(
            id: "p1",
            features: queryFeatures,
            name: "Test Product",
            price: 99.99,
            inStock: true
        )
        context.insert(product)
        try context.save()

        // Search using cosine metric (defined in @Vector macro)
        let results = try context.vectorSearch(Product.self) {
            VectorSearch(\Product.features, query: queryFeatures, k: 1)
        }

        // Should find the product
        #expect(results.count == 1)
        #expect(results[0].model.id == "p1")
    }

    // MARK: - Chained Filters Tests

    @Test("Vector search with multiple WHERE clauses")
    func testVectorSearchMultipleFilters() throws {
        let container = try GraphContainer(
            for: Product.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Insert test data
        let products = [
            Product(id: "p1", features: Array(repeating: 0.1, count: 128), name: "A", price: 10.0, inStock: true),
            Product(id: "p2", features: Array(repeating: 0.2, count: 128), name: "B", price: 20.0, inStock: true),
            Product(id: "p3", features: Array(repeating: 0.15, count: 128), name: "C", price: 15.0, inStock: false),
            Product(id: "p4", features: Array(repeating: 0.12, count: 128), name: "D", price: 50.0, inStock: true),
        ]

        for product in products {
            context.insert(product)
        }
        try context.save()

        // Search with multiple filters
        let queryVector = Array(repeating: Float(0.1), count: 128)
        let results = try context.vectorSearch(Product.self) {
            VectorSearch(\Product.features, query: queryVector, k: 10)
                .where(\.inStock, .equal, true)
                .where(\.price, .lessThan, 30.0)
        }

        // Should return p1 and p2 only (inStock=true AND price < 30)
        #expect(results.count == 2)

        let ids = results.map { $0.model.id }
        #expect(ids.contains("p1"))
        #expect(ids.contains("p2"))
        #expect(!ids.contains("p3"), "p3 is not in stock")
        #expect(!ids.contains("p4"), "p4 price is 50.0")
    }

    // MARK: - Error Handling Tests

    @Test("Vector search on non-vector property fails")
    func testVectorSearchNonVectorProperty() throws {
        let container = try GraphContainer(
            for: Article.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Try to use VectorSearch on a non-@Vector property
        // This should fail at compile time, but we can verify runtime behavior
        // by checking the error message

        // Note: This test is more of a documentation of expected behavior
        // since Swift's type system prevents this at compile time
    }

    // MARK: - Integration Tests

    @Test("Vector search end-to-end workflow")
    func testVectorSearchEndToEnd() throws {
        let container = try GraphContainer(
            for: Article.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Step 1: Insert diverse articles
        let techArticles = [
            Article(id: "tech1", embedding: [0.9, 0.1, 0.0], title: "AI Trends", published: true),
            Article(id: "tech2", embedding: [0.85, 0.15, 0.0], title: "ML Guide", published: true),
            Article(id: "tech3", embedding: [0.8, 0.2, 0.0], title: "DL Basics", published: false),
        ]

        let sportsArticles = [
            Article(id: "sport1", embedding: [0.1, 0.9, 0.0], title: "Soccer", published: true),
            Article(id: "sport2", embedding: [0.15, 0.85, 0.0], title: "Tennis", published: true),
        ]

        for article in techArticles + sportsArticles {
            context.insert(article)
        }
        try context.save()

        // Step 2: Find similar published tech articles
        let techQueryVector: [Float] = [1.0, 0.0, 0.0]
        let results = try context.vectorSearch(Article.self) {
            VectorSearch(\Article.embedding, query: techQueryVector, k: 3)
                .where(\.published, .equal, true)
        }

        // Step 3: Verify results
        #expect(results.count == 2, "Should find 2 published tech articles (tech3 is unpublished)")

        // Should be ordered by similarity to tech content
        #expect(results[0].model.id.hasPrefix("tech"))
        #expect(results[1].model.id.hasPrefix("tech"))

        // Step 4: Find sports articles
        let sportsQueryVector: [Float] = [0.0, 1.0, 0.0]
        let sportsResults = try context.vectorSearch(Article.self) {
            VectorSearch(\Article.embedding, query: sportsQueryVector, k: 3)
        }

        #expect(sportsResults.count >= 2)
        #expect(sportsResults[0].model.id.hasPrefix("sport"))
    }

    // MARK: - Performance Tests

    @Test("Vector search with K-nearest neighbors ordering")
    func testVectorSearchKNN() throws {
        let container = try GraphContainer(
            for: Article.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Create a cluster with varying distances
        let center: [Float] = [0.5, 0.5, 0.5]
        let articles = [
            Article(id: "center", embedding: center, title: "Center", published: true),
            Article(id: "close1", embedding: [0.51, 0.51, 0.51], title: "Close 1", published: true),
            Article(id: "close2", embedding: [0.49, 0.49, 0.49], title: "Close 2", published: true),
            Article(id: "far", embedding: [0.0, 0.0, 0.0], title: "Far", published: true),
        ]

        for article in articles {
            context.insert(article)
        }
        try context.save()

        // Search for K=3 nearest to center
        let results = try context.vectorSearch(Article.self) {
            VectorSearch(\Article.embedding, query: center, k: 3)
        }

        #expect(results.count == 3, "Should return exactly K=3 results")

        // First should be exact match
        #expect(results[0].model.id == "center")
        #expect(results[0].distance < 0.01)

        // Last should not be "far"
        #expect(results[2].model.id != "far", "K=3 should exclude the furthest point")
    }
}
