import Testing
import Foundation
@testable import KuzuSwiftExtension

@Suite("KuzuCodable Graph Integration Tests")
struct KuzuCodableGraphIntegrationTests {
    
    // MARK: - Graph Models
    
    @GraphNode
    struct User: Codable, Sendable {
        @ID var id: UUID = UUID()
        var username: String
        var email: String
        var createdAt: Date
        var metadata: [String: String]?
        var tags: Set<String>
        var isActive: Bool
        var score: Double?
    }
    
    @GraphNode
    struct Post: Codable, Sendable {
        @ID var id: UUID = UUID()
        var title: String
        var content: String
        var publishedAt: Date
        var viewCount: Int64
        var tags: [String]
        var metadata: [String: String]?
    }
    
    @GraphNode
    struct Comment: Codable, Sendable {
        @ID var id: UUID = UUID()
        var text: String
        var createdAt: Date
        var likes: Int
        var replies: [String]?
    }
    
    @GraphEdge
    struct Author: Codable, Sendable {
        @Since(\User.id) var userID: String
        @Target(\Post.id) var postID: String
        var role: String
        var since: Date
        var permissions: Set<String>
    }

    @GraphEdge
    struct Wrote: Codable, Sendable {
        @Since(\User.id) var userID: String
        @Target(\Comment.id) var commentID: String
        var at: Date
        var device: String?
        var location: String?
    }

    @GraphEdge
    struct HasComment: Codable, Sendable {
        @Since(\Post.id) var postID: String
        @Target(\Comment.id) var commentID: String
        var order: Int
        var isPinned: Bool
    }
    
    // MARK: - Node Encoding/Decoding Tests
    
    @Test("Encode and decode GraphNode with all property types")
    func encodeDecodeGraphNode() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let user = User(
            id: UUID(),
            username: "testuser",
            email: "test@example.com",
            createdAt: Date(),
            metadata: ["role": "admin", "level": "5"],
            tags: Set(["swift", "database", "graph"]),
            isActive: true,
            score: 95.5
        )
        
        let encoded = try encoder.encode(user)
        
        // Verify all properties are encoded
        #expect(encoded["id"] != nil)
        #expect(encoded["username"] as? String == "testuser")
        #expect(encoded["email"] as? String == "test@example.com")
        #expect(encoded["createdAt"] != nil)
        #expect(encoded["metadata"] != nil)
        #expect(encoded["tags"] != nil)
        #expect(encoded["isActive"] as? Bool == true)
        #expect(encoded["score"] as? Double == 95.5)
        
        let decoded = try decoder.decode(User.self, from: encoded)
        
        #expect(decoded.id == user.id)
        #expect(decoded.username == user.username)
        #expect(decoded.email == user.email)
        #expect(decoded.metadata == user.metadata)
        #expect(decoded.tags == user.tags)
        #expect(decoded.isActive == user.isActive)
        #expect(decoded.score == user.score)
    }
    
    @Test("GraphNode with nil optionals")
    func graphNodeWithNilOptionals() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let user = User(
            id: UUID(),
            username: "minimal",
            email: "minimal@test.com",
            createdAt: Date(),
            metadata: nil,
            tags: Set(),
            isActive: false,
            score: nil
        )
        
        let encoded = try encoder.encode(user)
        let decoded = try decoder.decode(User.self, from: encoded)
        
        #expect(decoded.metadata == nil)
        #expect(decoded.score == nil)
        #expect(decoded.tags.isEmpty)
    }
    
    // MARK: - Edge Encoding/Decoding Tests
    
    @Test("Encode and decode GraphEdge with properties")
    func encodeDecodeGraphEdge() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let author = Author(
            userID: "user-123",
            postID: "post-456",
            role: "primary",
            since: Date(),
            permissions: Set(["read", "write", "delete"])
        )
        
        let encoded = try encoder.encode(author)
        
        #expect(encoded["role"] as? String == "primary")
        #expect(encoded["since"] != nil)
        #expect(encoded["permissions"] != nil)
        
        let decoded = try decoder.decode(Author.self, from: encoded)
        
        #expect(decoded.role == author.role)
        #expect(decoded.permissions == author.permissions)
    }
    
    @Test("GraphEdge with optional properties")
    func graphEdgeWithOptionals() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let wrote = Wrote(
            userID: "user-123",
            commentID: "comment-456",
            at: Date(),
            device: "iPhone",
            location: nil
        )
        
        let encoded = try encoder.encode(wrote)
        let decoded = try decoder.decode(Wrote.self, from: encoded)
        
        #expect(decoded.device == "iPhone")
        #expect(decoded.location == nil)
    }
    
    // MARK: - Complex Graph Models Tests
    
    @Test("Node with nested collections")
    func nodeWithNestedCollections() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let post = Post(
            id: UUID(),
            title: "Test Post",
            content: "This is a test post with various content types.",
            publishedAt: Date(),
            viewCount: Int64(12345),
            tags: ["swift", "testing", "database"],
            metadata: [
                "author": "system",
                "version": "1.0",
                "category": "tech"
            ]
        )
        
        let encoded = try encoder.encode(post)
        let decoded = try decoder.decode(Post.self, from: encoded)
        
        #expect(decoded.title == post.title)
        #expect(decoded.viewCount == post.viewCount)
        #expect(decoded.tags == post.tags)
        #expect(decoded.metadata == post.metadata)
    }
    
    @Test("Node with array properties")
    func nodeWithArrayProperties() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let comment = Comment(
            id: UUID(),
            text: "Great post!",
            createdAt: Date(),
            likes: 42,
            replies: ["Thanks!", "Agreed", "Well said"]
        )
        
        let encoded = try encoder.encode(comment)
        let decoded = try decoder.decode(Comment.self, from: encoded)
        
        #expect(decoded.text == comment.text)
        #expect(decoded.likes == comment.likes)
        #expect(decoded.replies == comment.replies)
    }
    
    // MARK: - Database Type Compatibility Tests
    
    @Test("UUID to String conversion for database")
    func uuidToStringConversion() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let id = UUID()
        let user = User(
            id: id,
            username: "uuid_test",
            email: "uuid@test.com",
            createdAt: Date(),
            metadata: nil,
            tags: Set(),
            isActive: true,
            score: nil
        )
        
        let encoded = try encoder.encode(user)
        
        // UUID should be encoded as String for database
        #expect(encoded["id"] as? String == id.uuidString)
        
        // Should decode back to UUID
        let decoded = try decoder.decode(User.self, from: encoded)
        #expect(decoded.id == id)
    }
    
    @Test("Date to TIMESTAMP compatibility")
    func dateToTimestampCompatibility() throws {
        let encoder = KuzuEncoder()
        var decoder = KuzuDecoder()
        
        let now = Date()
        let user = User(
            id: UUID(),
            username: "date_test",
            email: "date@test.com",
            createdAt: now,
            metadata: nil,
            tags: Set(),
            isActive: true,
            score: nil
        )
        
        // Test different date strategies
        var config = encoder.configuration
        
        // ISO8601 (default for Kuzu)
        config.dateEncodingStrategy = .iso8601
        let encoder1 = KuzuEncoder(configuration: config)
        let encoded1 = try encoder1.encode(user)
        #expect(encoded1["createdAt"] is String)
        
        // Microseconds (alternative)
        config.dateEncodingStrategy = .microsecondsSince1970
        let encoder2 = KuzuEncoder(configuration: config)
        let encoded2 = try encoder2.encode(user)
        #expect(encoded2["createdAt"] is Int64)
        
        // Both should decode correctly
        decoder.configuration.dateDecodingStrategy = .iso8601
        let decoded1 = try decoder.decode(User.self, from: encoded1)
        #expect(abs(decoded1.createdAt.timeIntervalSince1970 - now.timeIntervalSince1970) < 0.001)
        
        // For microseconds, manually handle the conversion
        // Since KuzuDecoder doesn't have microsecondsSince1970 strategy yet
        // we'll just verify the encoding worked
        if let microseconds = encoded2["createdAt"] as? Int64 {
            let decodedDate = Date(timeIntervalSince1970: Double(microseconds) / 1_000_000)
            #expect(abs(decodedDate.timeIntervalSince1970 - now.timeIntervalSince1970) < 0.001)
        }
    }
    
    @Test("Int64 handling for database counts")
    func int64HandlingForCounts() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        // Simulate database returning Int64 for counts
        let post = Post(
            id: UUID(),
            title: "Popular Post",
            content: "Content",
            publishedAt: Date(),
            viewCount: Int64.max - 1000,  // Large Int64 value
            tags: [],
            metadata: nil
        )
        
        let encoded = try encoder.encode(post)
        let decoded = try decoder.decode(Post.self, from: encoded)
        
        #expect(decoded.viewCount == post.viewCount)
    }
    
    // MARK: - Round-trip Tests
    
    @Test("Round-trip with all node types")
    func roundTripAllNodeTypes() throws {
        let encoder = KuzuEncoder()
        let decoder = KuzuDecoder()
        
        let user = User(
            id: UUID(),
            username: "complete_user",
            email: "complete@test.com",
            createdAt: Date(),
            metadata: ["key": "value"],
            tags: Set(["tag1", "tag2"]),
            isActive: true,
            score: 88.5
        )
        
        let post = Post(
            id: UUID(),
            title: "Complete Post",
            content: "Complete content",
            publishedAt: Date(),
            viewCount: 999,
            tags: ["tag1", "tag2", "tag3"],
            metadata: ["meta": "data"]
        )
        
        let comment = Comment(
            id: UUID(),
            text: "Complete comment",
            createdAt: Date(),
            likes: 100,
            replies: ["reply1", "reply2"]
        )
        
        // Encode and decode each
        let encodedUser = try encoder.encode(user)
        let decodedUser = try decoder.decode(User.self, from: encodedUser)
        
        let encodedPost = try encoder.encode(post)
        let decodedPost = try decoder.decode(Post.self, from: encodedPost)
        
        let encodedComment = try encoder.encode(comment)
        let decodedComment = try decoder.decode(Comment.self, from: encodedComment)
        
        // Verify round-trip
        #expect(decodedUser.id == user.id)
        #expect(decodedUser.username == user.username)
        #expect(decodedUser.tags == user.tags)
        
        #expect(decodedPost.id == post.id)
        #expect(decodedPost.title == post.title)
        #expect(decodedPost.tags == post.tags)
        
        #expect(decodedComment.id == comment.id)
        #expect(decodedComment.text == comment.text)
        #expect(decodedComment.replies == comment.replies)
    }
}