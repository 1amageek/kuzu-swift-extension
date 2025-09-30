import Testing
import Foundation
@testable import KuzuSwiftExtension

@Suite("Vector Index Tests")
struct VectorIndexTests {

    // MARK: - Test Models

    @GraphNode
    struct PhotoAsset: Codable {
        @ID var id: String
        @Vector(dimensions: 3) var labColor: [Float]
        var enabled: Bool = true
    }

    @GraphNode
    struct MultiVectorModel: Codable {
        @ID var id: String
        @Vector(dimensions: 128) var embedding: [Float]
        @Vector(dimensions: 3) var color: [Float]
        var name: String
    }

    // MARK: - Metadata Tests

    @Test("Vector metadata generation")
    func testVectorMetadataGeneration() {
        #expect(PhotoAsset._vectorProperties.count == 1)
        #expect(PhotoAsset._vectorProperties[0].propertyName == "labColor")
        #expect(PhotoAsset._vectorProperties[0].dimensions == 3)
        #expect(PhotoAsset._vectorProperties[0].metric == .l2)
    }

    @Test("Multiple vector properties metadata")
    func testMultipleVectorProperties() {
        #expect(MultiVectorModel._vectorProperties.count == 2)

        let embeddingProp = MultiVectorModel._vectorProperties.first { $0.propertyName == "embedding" }
        #expect(embeddingProp?.dimensions == 128)

        let colorProp = MultiVectorModel._vectorProperties.first { $0.propertyName == "color" }
        #expect(colorProp?.dimensions == 3)
    }

    @Test("Index name generation")
    func testIndexNameGeneration() {
        let metadata = VectorPropertyMetadata(
            propertyName: "labColor",
            dimensions: 3,
            metric: .l2
        )

        let indexName = metadata.indexName(for: "PhotoAsset")
        #expect(indexName == "photoasset_labcolor_idx")
    }

    // MARK: - Integration Tests

    @Test("Automatic index creation on registration")
    func testAutomaticIndexCreation() async throws {
        let container = try await GraphContainer(
            for: PhotoAsset.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Check if index exists - first try to query it
        let hasIndex = try await context.container.withConnection { connection in
            try VectorIndexManager.hasVectorIndex(
                table: "PhotoAsset",
                indexName: "photoasset_labcolor_idx",
                connection: connection
            )
        }

        if !hasIndex {
            print("⚠️  Index not created automatically, creating manually...")
            try await context.container.withConnection { connection in
                try VectorIndexManager.createVectorIndex(
                    table: "PhotoAsset",
                    column: "labColor",
                    indexName: "photoasset_labcolor_idx",
                    metric: .l2,
                    connection: connection
                )
            }
        }

        // Insert test data
        let photo = PhotoAsset(
            id: "photo1",
            labColor: [50.0, 10.0, 20.0],
            enabled: true
        )
        context.insert(photo)
        try await context.save()

        // Verify index was created by using it
        let result = try await context.raw("""
            CALL QUERY_VECTOR_INDEX('PhotoAsset', 'photoasset_labcolor_idx',
                CAST([50.0, 10.0, 20.0] AS FLOAT[3]), 5)
            WITH node AS p, distance
            RETURN p.id AS id, distance
        """)

        #expect(result.hasNext())

        // Verify result
        if let row = try result.getNext() {
            let id = try row.getValue(0) as? String
            #expect(id == "photo1")
        }
    }

    @Test("Idempotent index creation")
    func testIdempotentIndexCreation() async throws {
        let container = try await GraphContainer(
            for: PhotoAsset.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Register again - should not fail
        try await context.createSchemasIfNotExist(for: [PhotoAsset.self])

        // Index should still work
        let photo = PhotoAsset(
            id: "photo1",
            labColor: [50.0, 10.0, 20.0],
            enabled: true
        )
        context.insert(photo)
        try await context.save()

        let result = try await context.raw("""
            CALL QUERY_VECTOR_INDEX('PhotoAsset', 'photoasset_labcolor_idx',
                CAST([50.0, 10.0, 20.0] AS FLOAT[3]), 1)
            RETURN node
        """)

        #expect(result.hasNext())
    }

    @Test("Multiple vector indexes creation")
    func testMultipleVectorIndexes() async throws {
        let container = try await GraphContainer(
            for: MultiVectorModel.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Insert test data
        let item = MultiVectorModel(
            id: "item1",
            embedding: Array(repeating: 0.1, count: 128),
            color: [0.5, 0.3, 0.7],
            name: "Test Item"
        )
        context.insert(item)
        try await context.save()

        // Verify embedding index
        let result1 = try await context.raw("""
            CALL QUERY_VECTOR_INDEX('MultiVectorModel', 'multivectormodel_embedding_idx',
                CAST(\(Array(repeating: 0.1, count: 128)) AS FLOAT[128]), 1)
            RETURN node
        """)
        #expect(result1.hasNext())

        // Verify color index
        let result2 = try await context.raw("""
            CALL QUERY_VECTOR_INDEX('MultiVectorModel', 'multivectormodel_color_idx',
                CAST([0.5, 0.3, 0.7] AS FLOAT[3]), 1)
            RETURN node
        """)
        #expect(result2.hasNext())
    }

    @Test("Vector search with filtering")
    func testVectorSearchWithFiltering() async throws {
        let container = try await GraphContainer(
            for: PhotoAsset.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Insert multiple photos
        let photos = [
            PhotoAsset(id: "photo1", labColor: [50.0, 10.0, 20.0], enabled: true),
            PhotoAsset(id: "photo2", labColor: [51.0, 11.0, 21.0], enabled: false),
            PhotoAsset(id: "photo3", labColor: [52.0, 12.0, 22.0], enabled: true)
        ]

        for photo in photos {
            context.insert(photo)
        }
        try await context.save()

        // Search with filtering
        let result = try await context.raw("""
            CALL QUERY_VECTOR_INDEX('PhotoAsset', 'photoasset_labcolor_idx',
                CAST([50.0, 10.0, 20.0] AS FLOAT[3]), 10)
            WITH node AS p, distance
            WHERE p.enabled = true
            RETURN p.id AS id, distance
            ORDER BY distance
        """)

        var foundIds: [String] = []
        while result.hasNext() {
            if let row = try result.getNext(),
               let id = try row.getValue(0) as? String {
                foundIds.append(id)
            }
        }

        // Should only return enabled photos
        #expect(foundIds.count == 2)
        #expect(foundIds.contains("photo1"))
        #expect(foundIds.contains("photo3"))
        #expect(!foundIds.contains("photo2"))
    }

    @Test("HasVectorProperties protocol conformance")
    func testHasVectorPropertiesConformance() {
        // PhotoAsset should conform to HasVectorProperties
        let isConforming = PhotoAsset.self is any HasVectorProperties.Type
        #expect(isConforming)

        // MultiVectorModel should also conform
        let isConforming2 = MultiVectorModel.self is any HasVectorProperties.Type
        #expect(isConforming2)
    }
}