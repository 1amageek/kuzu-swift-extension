import Testing
import Foundation
@testable import KuzuSwiftExtension

@Suite("Full-Text Search Index Tests")
struct FTSIndexTests {

    @GraphNode
    fileprivate struct Document: Codable {
        @ID var id: Int
        var title: String
        @Attribute(.spotlight) var content: String
    }

    @GraphNode
    fileprivate struct BlogPost: Codable {
        @ID var id: String
        @Attribute(.spotlight) var body: String
        var author: String
    }

    @Test("Full-Text Search metadata is generated correctly")
    func fullTextSearchMetadataGeneration() {
        let metadata = Document._metadata.fullTextSearchProperties

        #expect(metadata.count == 1)
        #expect(metadata[0].propertyName == "content")
        #expect(metadata[0].stemmer == "porter")
    }

    @Test("Full-Text Search index name generation")
    func fullTextSearchIndexNameGeneration() {
        let metadata = Document._metadata.fullTextSearchProperties[0]
        let indexName = metadata.indexName(for: "Document")

        #expect(indexName == "document_content_fts_idx")
    }

    @Test("Full-Text Search index is created automatically by GraphContainer")
    func fullTextSearchIndexCreation() throws {
        let container = try GraphContainer(
            for: Document.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Insert test data
        context.insert(Document(id: 1, title: "AI Research", content: "quantum computing and machine learning"))
        context.insert(Document(id: 2, title: "Database Systems", content: "graph database and relational models"))
        context.insert(Document(id: 3, title: "Algorithms", content: "sorting and searching algorithms"))
        try context.save()

        // FTS search for "quantum"
        let result = try context.raw("""
            CALL QUERY_FTS_INDEX('Document', 'document_content_fts_idx', 'quantum')
            RETURN node.id AS id, score
            ORDER BY score DESC
            """)

        #expect(result.hasNext())

        if let row = try result.getNext(),
           let id = try row.getValue(0) as? Int64 {
            #expect(id == 1)
        }
    }

    @Test("Full-Text Search with multiple keywords")
    func fullTextSearchMultiKeyword() throws {
        let container = try GraphContainer(
            for: Document.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        context.insert(Document(id: 1, title: "Science", content: "quantum physics and computing"))
        context.insert(Document(id: 2, title: "Tech", content: "quantum computing applications"))
        context.insert(Document(id: 3, title: "Math", content: "linear algebra and calculus"))
        try context.save()

        // Search for "quantum computing"
        let result = try context.raw("""
            CALL QUERY_FTS_INDEX('Document', 'document_content_fts_idx', 'quantum computing')
            RETURN node.id AS id, score
            ORDER BY score DESC
            """)

        // Should return documents with both keywords ranked higher
        #expect(result.hasNext())

        if let row = try result.getNext(),
           let id = try row.getValue(0) as? Int64 {
            // Document 2 has both "quantum" and "computing"
            #expect(id == 2 || id == 1)
        }
    }

    @Test("Multiple models with Full-Text Search indexes")
    func multipleFullTextSearchIndexes() throws {
        let container = try GraphContainer(
            for: Document.self, BlogPost.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        context.insert(Document(id: 1, title: "Doc", content: "database tutorial"))
        context.insert(BlogPost(id: "post1", body: "kuzu database guide", author: "Alice"))
        try context.save()

        // Search Document FTS index
        let docResult = try context.raw("""
            CALL QUERY_FTS_INDEX('Document', 'document_content_fts_idx', 'database')
            RETURN node.id AS id
            """)
        #expect(docResult.hasNext())

        // Search BlogPost FTS index
        let postResult = try context.raw("""
            CALL QUERY_FTS_INDEX('BlogPost', 'blogpost_body_fts_idx', 'database')
            RETURN node.id AS id
            """)
        #expect(postResult.hasNext())
    }

    @Test("Full-Text Search columns have FULLTEXT constraint")
    func fullTextSearchColumnConstraint() {
        // Verify FULLTEXT constraint is in columns metadata
        let contentColumn = Document._kuzuColumns.first { $0.columnName == "content" }
        #expect(contentColumn?.constraints.contains("FULLTEXT") == true)
    }
}
