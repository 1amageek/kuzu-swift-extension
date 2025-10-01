import Testing
import Foundation
@testable import KuzuSwiftExtension

@GraphNode
fileprivate struct TestUser: Codable {
    @ID var id: Int
    var name: String
}

@GraphNode
fileprivate struct TestPost: Codable {
    @ID var id: Int
    var title: String
}

@Suite("Change Tracking Tests")
struct ChangeTrackingTests {

    @Test("hasChanges returns false initially")
    func initialState() throws {
        let container = try GraphContainer(
            for: TestUser.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        #expect(context.hasChanges == false)
    }

    @Test("hasChanges returns true after insert")
    func afterInsert() throws {
        let container = try GraphContainer(
            for: TestUser.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        let user = TestUser(id: 1, name: "Alice")
        context.insert(user)

        #expect(context.hasChanges == true)
    }

    @Test("hasChanges returns false after save")
    func afterSave() throws {
        let container = try GraphContainer(
            for: TestUser.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        let user = TestUser(id: 1, name: "Alice")
        context.insert(user)
        try context.save()

        #expect(context.hasChanges == false)
    }

    @Test("hasChanges returns true after delete")
    func afterDelete() throws {
        let container = try GraphContainer(
            for: TestUser.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        let user = TestUser(id: 1, name: "Alice")
        context.insert(user)
        try context.save()

        #expect(context.hasChanges == false)

        context.delete(user)
        #expect(context.hasChanges == true)
    }

    @Test("hasChanges returns false after rollback")
    func afterRollback() throws {
        let container = try GraphContainer(
            for: TestUser.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        let user = TestUser(id: 1, name: "Alice")
        context.insert(user)

        #expect(context.hasChanges == true)

        context.rollback()

        #expect(context.hasChanges == false)
    }

    @Test("hasChanges with multiple operations")
    func multipleOperations() throws {
        let container = try GraphContainer(
            for: TestUser.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Insert multiple users
        context.insert(TestUser(id: 1, name: "Alice"))
        context.insert(TestUser(id: 2, name: "Bob"))
        context.insert(TestUser(id: 3, name: "Charlie"))

        #expect(context.hasChanges == true)

        try context.save()

        #expect(context.hasChanges == false)

        // Delete one user
        context.delete(TestUser(id: 1, name: "Alice"))

        #expect(context.hasChanges == true)
    }

    @Test("insertedModelsArray returns pending inserts")
    func insertedModelsArray() throws {
        let container = try GraphContainer(
            for: TestUser.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        #expect(context.insertedModelsArray.isEmpty)

        let user1 = TestUser(id: 1, name: "Alice")
        let user2 = TestUser(id: 2, name: "Bob")

        context.insert(user1)
        context.insert(user2)

        #expect(context.insertedModelsArray.count == 2)

        try context.save()

        #expect(context.insertedModelsArray.isEmpty)
    }

    @Test("deletedModelsArray returns pending deletes")
    func deletedModelsArray() throws {
        let container = try GraphContainer(
            for: TestUser.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        let user1 = TestUser(id: 1, name: "Alice")
        let user2 = TestUser(id: 2, name: "Bob")

        context.insert(user1)
        context.insert(user2)
        try context.save()

        #expect(context.deletedModelsArray.isEmpty)

        context.delete(user1)
        context.delete(user2)

        #expect(context.deletedModelsArray.count == 2)

        try context.save()

        #expect(context.deletedModelsArray.isEmpty)
    }

    @Test("changedModelsArray returns empty array")
    func changedModelsArray() throws {
        let container = try GraphContainer(
            for: TestUser.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // changedModelsArray is not currently tracked in Kuzu
        // Updates are done via insert (MERGE operation)
        #expect(context.changedModelsArray.isEmpty)

        context.insert(TestUser(id: 1, name: "Alice"))

        #expect(context.changedModelsArray.isEmpty)
    }

    @Test("Multiple model types tracked separately")
    func multipleModelTypes() throws {
        let container = try GraphContainer(
            for: TestUser.self, TestPost.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        context.insert(TestUser(id: 1, name: "Alice"))
        context.insert(TestPost(id: 1, title: "First Post"))

        #expect(context.insertedModelsArray.count == 2)
        #expect(context.hasChanges == true)

        try context.save()

        #expect(context.insertedModelsArray.isEmpty)
        #expect(context.hasChanges == false)
    }

    @Test("Change tracking thread safety")
    func threadSafety() async throws {
        let container = try GraphContainer(
            for: TestUser.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        // Concurrent access from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for i in 1...50 {
                    context.insert(TestUser(id: i, name: "User \(i)"))
                }
            }

            group.addTask {
                for i in 51...100 {
                    context.insert(TestUser(id: i, name: "User \(i)"))
                }
            }
        }

        #expect(context.hasChanges == true)
        #expect(context.insertedModelsArray.count == 100)

        try context.save()

        #expect(context.hasChanges == false)
        #expect(context.insertedModelsArray.isEmpty)
    }
}
