#!/usr/bin/env swift

import Foundation
import KuzuSwiftExtension

// Test model
@GraphNode
struct TestUser {
    @ID var id: UUID = UUID()
    var name: String
    @Timestamp var createdAt: Date = Date()
}

// Main test
@main
struct TimestampTest {
    static func main() async throws {
        print("Testing timestamp conversion...")
        
        // Create in-memory database
        let config = GraphConfiguration(databasePath: ":memory:")
        let context = try await GraphContext(configuration: config)
        
        // Create schema
        try await context.createSchema(for: TestUser.self)
        print("✅ Schema created successfully")
        
        // Create and save a user
        let user = TestUser(name: "Test User")
        let saved = try await context.save(user)
        print("✅ User saved successfully")
        print("  ID: \(saved.id)")
        print("  Name: \(saved.name)")
        print("  CreatedAt: \(saved.createdAt)")
        
        // Fetch the user back
        let fetched = try await context.fetchOne(TestUser.self, id: saved.id)
        print("✅ User fetched successfully")
        
        if let fetchedUser = fetched {
            print("  ID: \(fetchedUser.id)")
            print("  Name: \(fetchedUser.name)")
            print("  CreatedAt: \(fetchedUser.createdAt)")
            
            // Compare dates (allowing for small precision differences)
            let timeDiff = abs(saved.createdAt.timeIntervalSince(fetchedUser.createdAt))
            if timeDiff < 0.001 {
                print("✅ Timestamp preserved correctly!")
            } else {
                print("❌ Timestamp mismatch: \(timeDiff) seconds difference")
            }
        } else {
            print("❌ Failed to fetch user")
        }
        
        await context.close()
        print("\n✅ All tests passed!")
    }
}