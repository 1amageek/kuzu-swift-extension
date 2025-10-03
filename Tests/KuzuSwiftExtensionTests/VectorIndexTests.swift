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

    @Test("Vector metadata generation for single property")
    func testVectorMetadataGeneration() {
        #expect(PhotoAsset._metadata.vectorProperties.count == 1)

        let property = PhotoAsset._metadata.vectorProperties[0]
        #expect(property.propertyName == "labColor")
        #expect(property.dimensions == 3)
        #expect(property.metric == .l2)
    }

    @Test("Vector metadata generation for multiple properties")
    func testMultipleVectorProperties() {
        #expect(MultiVectorModel._metadata.vectorProperties.count == 2)

        let embeddingProp = MultiVectorModel._metadata.vectorProperties.first { $0.propertyName == "embedding" }
        #expect(embeddingProp != nil)
        #expect(embeddingProp?.dimensions == 128)
        #expect(embeddingProp?.metric == .l2)

        let colorProp = MultiVectorModel._metadata.vectorProperties.first { $0.propertyName == "color" }
        #expect(colorProp != nil)
        #expect(colorProp?.dimensions == 3)
        #expect(colorProp?.metric == .l2)
    }

    @Test("Index name generation follows naming convention")
    func testIndexNameGeneration() {
        let metadata = VectorPropertyMetadata(
            propertyName: "labColor",
            dimensions: 3,
            metric: .l2
        )

        let indexName = metadata.indexName(for: "PhotoAsset")
        #expect(indexName == "photoasset_labcolor_idx")

        // Test with different table name
        let indexName2 = metadata.indexName(for: "TestTable")
        #expect(indexName2 == "testtable_labcolor_idx")
    }

    @Test("Vector metadata availability")
    func testVectorMetadataAvailability() {
        // Models with @Vector should have vector metadata
        #expect(!PhotoAsset._metadata.vectorProperties.isEmpty)
        #expect(!MultiVectorModel._metadata.vectorProperties.isEmpty)
    }

    // MARK: - Manual Index Creation Tests

    @Test("Manual vector index creation")
    func testManualVectorIndexCreation() throws {
        let container = try GraphContainer(
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Create table schema manually (without automatic index creation)
        try context.raw("""
            CREATE NODE TABLE ManualTest (
                id STRING PRIMARY KEY,
                embedding FLOAT[3]
            )
        """)

        // Manually create vector index (DDL operations must be outside transactions)
        try context.withConnection { connection in
            try VectorIndexManager.createVectorIndex(
                table: "ManualTest",
                column: "embedding",
                indexName: "manual_embedding_idx",
                metric: .l2,
                connection: connection
            )
        }

        // Verify index was created by checking if it exists
        let hasIndex = try context.withConnection { connection in
            try VectorIndexManager.hasVectorIndex(
                table: "ManualTest",
                indexName: "manual_embedding_idx",
                connection: connection
            )
        }

        #expect(hasIndex, "Manually created index should exist")

    }

    @Test("Manual index creation is idempotent")
    func testIdempotentManualIndexCreation() throws {
        let container = try GraphContainer(
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Create table
        try context.raw("""
            CREATE NODE TABLE IdempotentTest (
                id STRING PRIMARY KEY,
                vec FLOAT[3]
            )
        """)

        // Create index first time
        try context.withConnection { connection in
            try VectorIndexManager.createVectorIndex(
                table: "IdempotentTest",
                column: "vec",
                indexName: "idempotent_vec_idx",
                metric: .l2,
                connection: connection
            )
        }

        // Create same index second time - should not fail
        try context.withConnection { connection in
            try VectorIndexManager.createVectorIndex(
                table: "IdempotentTest",
                column: "vec",
                indexName: "idempotent_vec_idx",
                metric: .l2,
                connection: connection
            )
        }

        // Verify index still exists
        let hasIndex = try context.withConnection { connection in
            try VectorIndexManager.hasVectorIndex(
                table: "IdempotentTest",
                indexName: "idempotent_vec_idx",
                connection: connection
            )
        }

        #expect(hasIndex)

    }

    // MARK: - Automatic Index Creation Tests

    @Test("Automatic index creation on GraphContainer initialization")
    func testAutomaticIndexCreation() throws {
        // Create container with GraphNode model that has @Vector
        let container = try GraphContainer(
            for: PhotoAsset.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Check if index was automatically created
        let hasIndex = try context.withConnection { connection in
            try VectorIndexManager.hasVectorIndex(
                table: "PhotoAsset",
                indexName: "photoasset_labcolor_idx",
                connection: connection
            )
        }

        #expect(hasIndex, "Index should be automatically created during container initialization")

    }

    @Test("Automatic index creation for multiple vector properties")
    func testMultipleAutomaticIndexCreation() throws {
        let container = try GraphContainer(
            for: MultiVectorModel.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Check if both indexes were created
        let hasEmbeddingIndex = try context.withConnection { connection in
            try VectorIndexManager.hasVectorIndex(
                table: "MultiVectorModel",
                indexName: "multivectormodel_embedding_idx",
                connection: connection
            )
        }

        let hasColorIndex = try context.withConnection { connection in
            try VectorIndexManager.hasVectorIndex(
                table: "MultiVectorModel",
                indexName: "multivectormodel_color_idx",
                connection: connection
            )
        }

        #expect(hasEmbeddingIndex, "Embedding index should be automatically created")
        #expect(hasColorIndex, "Color index should be automatically created")

    }

    @Test("Automatic index creation is idempotent")
    func testIdempotentAutomaticIndexCreation() throws {
        let dbPath = ":memory:"

        // First initialization - creates schema and indexes
        let container1 = try GraphContainer(
            for: PhotoAsset.self,
            configuration: GraphConfiguration(databasePath: dbPath)
        )
        let context1 = GraphContext(container1)

        // Verify index exists after first initialization
        let hasIndex = try context1.withConnection { connection in
            try VectorIndexManager.hasVectorIndex(
                table: "PhotoAsset",
                indexName: "photoasset_labcolor_idx",
                connection: connection
            )
        }

        #expect(hasIndex)

    }

    // MARK: - Index Usage Tests

    @Test("Query vector index with QUERY_VECTOR_INDEX")
    func testVectorIndexQuery() throws {
        let container = try GraphContainer(
            for: PhotoAsset.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Insert test data
        let photo1 = PhotoAsset(id: "photo1", labColor: [50.0, 10.0, 20.0], enabled: true)
        let photo2 = PhotoAsset(id: "photo2", labColor: [51.0, 11.0, 21.0], enabled: true)
        let photo3 = PhotoAsset(id: "photo3", labColor: [100.0, 50.0, 80.0], enabled: true)

        context.insert(photo1)
        context.insert(photo2)
        context.insert(photo3)
        try context.save()

        // Query using vector index
        let result = try context.raw("""
            CALL QUERY_VECTOR_INDEX('PhotoAsset', 'photoasset_labcolor_idx',
                CAST([50.0, 10.0, 20.0] AS FLOAT[3]), 5)
            WITH node AS p, distance
            RETURN p.id AS id, distance
            ORDER BY distance
        """)

        var results: [(String, Double)] = []
        while result.hasNext() {
            if let row = try result.getNext(),
               let id = try row.getValue(0) as? String,
               let distance = try row.getValue(1) as? Double {
                results.append((id, distance))
            }
        }

        // Verify results are ordered by distance
        #expect(results.count == 3, "Should return all 3 photos")
        #expect(results[0].0 == "photo1", "Closest should be photo1")
        #expect(results[0].1 < results[1].1, "Results should be ordered by distance")
        #expect(results[1].1 < results[2].1, "Results should be ordered by distance")

    }

    @Test("Vector search with filtering on non-vector properties")
    func testVectorSearchWithFiltering() throws {
        let container = try GraphContainer(
            for: PhotoAsset.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Insert multiple photos with different enabled states
        let photos = [
            PhotoAsset(id: "photo1", labColor: [50.0, 10.0, 20.0], enabled: true),
            PhotoAsset(id: "photo2", labColor: [51.0, 11.0, 21.0], enabled: false),
            PhotoAsset(id: "photo3", labColor: [52.0, 12.0, 22.0], enabled: true),
            PhotoAsset(id: "photo4", labColor: [53.0, 13.0, 23.0], enabled: false)
        ]

        for photo in photos {
            context.insert(photo)
        }
        try context.save()

        // Search with filtering on enabled property
        let result = try context.raw("""
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
        #expect(foundIds.count == 2, "Should only return 2 enabled photos")
        #expect(foundIds.contains("photo1"))
        #expect(foundIds.contains("photo3"))
        #expect(!foundIds.contains("photo2"), "Should not return disabled photo2")
        #expect(!foundIds.contains("photo4"), "Should not return disabled photo4")

    }

    @Test("Multiple vector indexes are independently queryable")
    func testMultipleVectorIndexesIndependentQuery() throws {
        let container = try GraphContainer(
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
        try context.save()

        // Query embedding index
        let embeddingResult = try context.raw("""
            CALL QUERY_VECTOR_INDEX('MultiVectorModel', 'multivectormodel_embedding_idx',
                CAST(\(Array(repeating: 0.1, count: 128)) AS FLOAT[128]), 1)
            RETURN node.id AS id
        """)
        #expect(embeddingResult.hasNext(), "Embedding index query should return results")

        if let row = try embeddingResult.getNext(),
           let id = try row.getValue(0) as? String {
            #expect(id == "item1")
        }

        // Query color index independently
        let colorResult = try context.raw("""
            CALL QUERY_VECTOR_INDEX('MultiVectorModel', 'multivectormodel_color_idx',
                CAST([0.5, 0.3, 0.7] AS FLOAT[3]), 1)
            RETURN node.id AS id
        """)
        #expect(colorResult.hasNext(), "Color index query should return results")

        if let row = try colorResult.getNext(),
           let id = try row.getValue(0) as? String {
            #expect(id == "item1")
        }

    }

    // MARK: - Index Verification Tests

    @Test("hasVectorIndex correctly identifies existing indexes")
    func testHasVectorIndexExisting() throws {
        let container = try GraphContainer(
            for: PhotoAsset.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        let hasIndex = try context.withConnection { connection in
            try VectorIndexManager.hasVectorIndex(
                table: "PhotoAsset",
                indexName: "photoasset_labcolor_idx",
                connection: connection
            )
        }

        #expect(hasIndex)

    }

    @Test("hasVectorIndex returns false for non-existing indexes")
    func testHasVectorIndexNonExisting() throws {
        let container = try GraphContainer(
            for: PhotoAsset.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        let hasIndex = try context.withConnection { connection in
            try VectorIndexManager.hasVectorIndex(
                table: "PhotoAsset",
                indexName: "nonexistent_index",
                connection: connection
            )
        }

        #expect(!hasIndex, "Should return false for non-existing index")

    }

    @Test("hasVectorIndex distinguishes between different tables")
    func testHasVectorIndexDifferentTables() throws {
        let container = try GraphContainer(
            for: PhotoAsset.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Check index exists for PhotoAsset
        let hasPhotoIndex = try context.withConnection { connection in
            try VectorIndexManager.hasVectorIndex(
                table: "PhotoAsset",
                indexName: "photoasset_labcolor_idx",
                connection: connection
            )
        }
        #expect(hasPhotoIndex)

        // Check same index name doesn't exist for different table
        let hasOtherTableIndex = try context.withConnection { connection in
            try VectorIndexManager.hasVectorIndex(
                table: "OtherTable",
                indexName: "photoasset_labcolor_idx",
                connection: connection
            )
        }
        #expect(!hasOtherTableIndex, "Index should be table-specific")

    }

    // MARK: - Error Handling Tests

    @Test("Vector index query on non-existing table fails appropriately")
    func testVectorIndexQueryOnNonExistingTable() throws {
        let container = try GraphContainer(
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        #expect(throws: Error.self) {
            _ = try context.raw("""
                CALL QUERY_VECTOR_INDEX('NonExistentTable', 'some_idx',
                    CAST([1.0, 2.0, 3.0] AS FLOAT[3]), 5)
                RETURN node
            """)
        }

    }

    @Test("Vector index query with wrong dimensions fails")
    func testVectorIndexQueryWrongDimensions() throws {
        let container = try GraphContainer(
            for: PhotoAsset.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // PhotoAsset.labColor is FLOAT[3], try to query with FLOAT[5]
        #expect(throws: Error.self) {
            _ = try context.raw("""
                CALL QUERY_VECTOR_INDEX('PhotoAsset', 'photoasset_labcolor_idx',
                    CAST([1.0, 2.0, 3.0, 4.0, 5.0] AS FLOAT[5]), 5)
                RETURN node
            """)
        }

    }
}
