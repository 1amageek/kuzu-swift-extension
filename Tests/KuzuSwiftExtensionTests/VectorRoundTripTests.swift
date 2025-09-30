import Testing
import Foundation
@testable import KuzuSwiftExtension

@GraphNode
struct RoundTripPhoto: Codable {
    @ID var id: String
    @Vector(dimensions: 3) var labColor: [Float]
    var name: String
    var enabled: Bool
}

@GraphNode
struct RoundTripDocument: Codable {
    @ID var id: String
    @Vector(dimensions: 128) var embedding: [Float]
    var title: String
}

@GraphNode
struct RoundTripImage: Codable {
    @ID var id: String
    @Vector(dimensions: 512) var features: [Float]
    var filename: String
}

@Suite("Vector Round Trip Tests")
struct VectorRoundTripTests {

    @Test("Complete round trip: create, save, and retrieve with vector search")
    func testCompleteRoundTrip() throws {
        // 1. Create context with model registration
        let container = try GraphContainer(
            for: RoundTripPhoto.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // 2. Create test data
        let photos = [
            RoundTripPhoto(id: "photo1", labColor: [50.0, 10.0, 20.0], name: "Red Photo", enabled: true),
            RoundTripPhoto(id: "photo2", labColor: [51.0, 11.0, 21.0], name: "Pink Photo", enabled: true),
            RoundTripPhoto(id: "photo3", labColor: [30.0, 40.0, 50.0], name: "Blue Photo", enabled: false),
            RoundTripPhoto(id: "photo4", labColor: [49.0, 9.0, 19.0], name: "Dark Red Photo", enabled: true),
        ]

        // 3. Save data
        for photo in photos {
            context.insert(photo)
        }
        try context.save()

        // 4. Retrieve with vector search (find photos similar to [50.0, 10.0, 20.0])
        let result = try context.raw("""
            CALL QUERY_VECTOR_INDEX('RoundTripPhoto', 'roundtripphoto_labcolor_idx',
                CAST([50.0, 10.0, 20.0] AS FLOAT[3]), 10)
            WITH node AS p, distance
            WHERE p.enabled = true
            RETURN p.id AS id, p.name AS name, p.labColor AS labColor, p.enabled AS enabled, distance
            ORDER BY distance
        """)

        // 5. Verify results
        var retrievedPhotos: [(id: String, name: String, distance: Double)] = []
        while result.hasNext() {
            guard let row = try result.getNext() else { break }
            let id = try row.getValue(0) as? String ?? ""
            let name = try row.getValue(1) as? String ?? ""
            let distance = try row.getValue(4) as? Double ?? 0.0
            retrievedPhotos.append((id, name, distance))
        }

        // Verify we got results
        #expect(retrievedPhotos.count > 0, "Should retrieve at least one photo")

        // Verify order (closest should be photo1 with distance ~0, then photo4)
        #expect(retrievedPhotos[0].id == "photo1", "Closest photo should be photo1")
        #expect(retrievedPhotos[0].name == "Red Photo")

        // Verify filtering worked (photo3 should not be in results)
        let ids = retrievedPhotos.map { $0.id }
        #expect(!ids.contains("photo3"), "Disabled photo should not be in results")

        print("✅ Round trip successful!")
        print("Retrieved \(retrievedPhotos.count) photos in order:")
        for (index, photo) in retrievedPhotos.enumerated() {
            print("  \(index + 1). \(photo.name) (id: \(photo.id), distance: \(photo.distance))")
        }
    }

    @Test("Vector search returns correct data types")
    func testVectorSearchDataTypes() throws {
        let container = try GraphContainer(
            for: RoundTripPhoto.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Insert a photo
        let photo = RoundTripPhoto(
            id: "test1",
            labColor: [100.0, 50.0, 25.0],
            name: "Test Photo",
            enabled: true
        )
        context.insert(photo)
        try context.save()

        // Retrieve with vector search
        let result = try context.raw("""
            CALL QUERY_VECTOR_INDEX('RoundTripPhoto', 'roundtripphoto_labcolor_idx',
                CAST([100.0, 50.0, 25.0] AS FLOAT[3]), 1)
            WITH node AS p, distance
            RETURN p.id AS id, p.name AS name, p.labColor AS labColor, p.enabled AS enabled
        """)

        #expect(result.hasNext())

        if let row = try result.getNext() {
            // Verify data types
            let id = try row.getValue(0) as? String
            let name = try row.getValue(1) as? String
            let labColor = try row.getValue(2) as? [Float]
            let enabled = try row.getValue(3) as? Bool

            #expect(id == "test1")
            #expect(name == "Test Photo")
            #expect(labColor == [100.0, 50.0, 25.0])
            #expect(enabled == true)

            print("✅ All data types preserved correctly!")
        }
    }

    @Test("Update existing photo with vector property",
          .disabled("KuzuDB vector index may not update immediately after DELETE+CREATE"))
    func testUpdateWithVectorProperty() throws {
        let container = try GraphContainer(
            for: RoundTripPhoto.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Insert initial photo
        let photo1 = RoundTripPhoto(
            id: "photo1",
            labColor: [50.0, 10.0, 20.0],
            name: "Original",
            enabled: true
        )
        context.insert(photo1)
        try context.save()

        // Update the same photo (should use DELETE + CREATE)
        let photo2 = RoundTripPhoto(
            id: "photo1",
            labColor: [60.0, 20.0, 30.0],
            name: "Updated",
            enabled: false
        )
        context.insert(photo2)
        try context.save()

        // First verify with normal query that update worked
        let checkResult = try context.raw("""
            MATCH (p:RoundTripPhoto {id: 'photo1'})
            RETURN p.id AS id, p.name AS name, p.labColor AS labColor, p.enabled AS enabled
        """)

        #expect(checkResult.hasNext(), "Should find updated photo with normal query")

        if let row = try checkResult.getNext() {
            let id = try row.getValue(0) as? String
            let name = try row.getValue(1) as? String
            let labColor = try row.getValue(2) as? [Float]
            let enabled = try row.getValue(3) as? Bool

            #expect(id == "photo1")
            #expect(name == "Updated", "Name should be updated")
            #expect(labColor == [60.0, 20.0, 30.0], "Vector should be updated")
            #expect(enabled == false, "Enabled should be updated")
        }

        // Now verify with vector search
        let vectorResult = try context.raw("""
            CALL QUERY_VECTOR_INDEX('RoundTripPhoto', 'roundtripphoto_labcolor_idx',
                CAST([60.0, 20.0, 30.0] AS FLOAT[3]), 1)
            WITH node AS p, distance
            RETURN p.id AS id, p.name AS name, distance
        """)

        #expect(vectorResult.hasNext(), "Should find updated photo with vector search")

        if let row = try vectorResult.getNext() {
            let id = try row.getValue(0) as? String
            #expect(id == "photo1", "Vector search should find the updated photo")
            print("✅ Update with vector property successful!")
        }
    }

    @Test("Multiple models with vectors can coexist")
    func testMultipleModelsWithVectors() throws {
        let container = try GraphContainer(
            for: RoundTripDocument.self, RoundTripImage.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Insert document
        let doc = RoundTripDocument(
            id: "doc1",
            embedding: Array(repeating: 0.1, count: 128),
            title: "Test Document"
        )
        context.insert(doc)

        // Insert image
        let img = RoundTripImage(
            id: "img1",
            features: Array(repeating: 0.2, count: 512),
            filename: "test.jpg"
        )
        context.insert(img)

        try context.save()

        // Search documents
        let docResult = try context.raw("""
            CALL QUERY_VECTOR_INDEX('RoundTripDocument', 'roundtripdocument_embedding_idx',
                CAST(\(Array(repeating: 0.1, count: 128)) AS FLOAT[128]), 1)
            WITH node AS d, distance
            RETURN d.id AS id, d.title AS title
        """)

        #expect(docResult.hasNext())
        if let row = try docResult.getNext() {
            let id = try row.getValue(0) as? String
            #expect(id == "doc1")
        }

        // Search images
        let imgResult = try context.raw("""
            CALL QUERY_VECTOR_INDEX('RoundTripImage', 'roundtripimage_features_idx',
                CAST(\(Array(repeating: 0.2, count: 512)) AS FLOAT[512]), 1)
            WITH node AS i, distance
            RETURN i.id AS id, i.filename AS filename
        """)

        #expect(imgResult.hasNext())
        if let row = try imgResult.getNext() {
            let id = try row.getValue(0) as? String
            #expect(id == "img1")
        }

        print("✅ Multiple models with vectors work correctly!")
    }

    @Test("Vector search with K-nearest neighbors")
    func testKNearestNeighbors() throws {
        let container = try GraphContainer(
            for: RoundTripPhoto.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Create a cluster of photos with similar colors
        let photos = [
            RoundTripPhoto(id: "p1", labColor: [50.0, 10.0, 20.0], name: "Center", enabled: true),
            RoundTripPhoto(id: "p2", labColor: [51.0, 11.0, 21.0], name: "Close 1", enabled: true),
            RoundTripPhoto(id: "p3", labColor: [49.0, 9.0, 19.0], name: "Close 2", enabled: true),
            RoundTripPhoto(id: "p4", labColor: [52.0, 12.0, 22.0], name: "Close 3", enabled: true),
            RoundTripPhoto(id: "p5", labColor: [100.0, 100.0, 100.0], name: "Far", enabled: true),
        ]

        for photo in photos {
            context.insert(photo)
        }
        try context.save()

        // Search for 3 nearest neighbors to [50.0, 10.0, 20.0]
        let result = try context.raw("""
            CALL QUERY_VECTOR_INDEX('RoundTripPhoto', 'roundtripphoto_labcolor_idx',
                CAST([50.0, 10.0, 20.0] AS FLOAT[3]), 3)
            WITH node AS p, distance
            RETURN p.id AS id, p.name AS name, distance
            ORDER BY distance
        """)

        var results: [(id: String, name: String, distance: Double)] = []
        while result.hasNext() {
            guard let row = try result.getNext() else { break }
            let id = try row.getValue(0) as? String ?? ""
            let name = try row.getValue(1) as? String ?? ""
            let distance = try row.getValue(2) as? Double ?? 0.0
            results.append((id, name, distance))
        }

        // Should get exactly 3 results
        #expect(results.count == 3, "Should return 3 nearest neighbors")

        // First should be exact match
        #expect(results[0].id == "p1", "First should be exact match")

        // "Far" photo should not be in top 3
        let ids = results.map { $0.id }
        #expect(!ids.contains("p5"), "Far photo should not be in top 3")

        print("✅ K-nearest neighbors search works correctly!")
        print("Top 3 results:")
        for (index, result) in results.enumerated() {
            print("  \(index + 1). \(result.name) (distance: \(result.distance))")
        }
    }
}