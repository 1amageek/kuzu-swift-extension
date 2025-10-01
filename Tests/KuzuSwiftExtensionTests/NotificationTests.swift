import Testing
import Foundation
@testable import KuzuSwiftExtension

@GraphNode
fileprivate struct NotificationUser: Codable {
    @ID var id: Int
    var name: String
}

@Suite("Notification Tests")
struct NotificationTests {

    @Test("willSave notification is posted before save")
    func willSaveNotification() throws {
        let container = try GraphContainer(
            for: NotificationUser.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        nonisolated(unsafe) var willSaveReceived = false

        let observer = NotificationCenter.default.addObserver(
            forName: GraphContext.willSave,
            object: context,
            queue: nil
        ) { notification in
            willSaveReceived = true
            #expect(notification.object as? GraphContext === context)
        }

        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        context.insert(NotificationUser(id: 1, name: "Alice"))
        try context.save()

        #expect(willSaveReceived == true)
    }

    @Test("didSave notification is posted after save")
    func didSaveNotification() throws {
        let container = try GraphContainer(
            for: NotificationUser.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        nonisolated(unsafe) var didSaveReceived = false

        let observer = NotificationCenter.default.addObserver(
            forName: GraphContext.didSave,
            object: context,
            queue: nil
        ) { notification in
            didSaveReceived = true
            #expect(notification.object as? GraphContext === context)
        }

        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        context.insert(NotificationUser(id: 1, name: "Alice"))
        try context.save()

        #expect(didSaveReceived == true)
    }

    @Test("didSave notification contains inserted identifiers")
    func didSaveInsertedIdentifiers() throws {
        let container = try GraphContainer(
            for: NotificationUser.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        nonisolated(unsafe) var insertedIds: [String] = []

        let observer = NotificationCenter.default.addObserver(
            forName: GraphContext.didSave,
            object: context,
            queue: nil
        ) { notification in
            if let userInfo = notification.userInfo,
               let ids = userInfo[GraphContext.NotificationKey.insertedIdentifiers.rawValue] as? [String] {
                insertedIds = ids
            }
        }

        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        context.insert(NotificationUser(id: 1, name: "Alice"))
        context.insert(NotificationUser(id: 2, name: "Bob"))
        try context.save()

        #expect(insertedIds.count == 2)
        #expect(insertedIds.contains { $0.contains("NotificationUser:1") })
        #expect(insertedIds.contains { $0.contains("NotificationUser:2") })
    }

    @Test("didSave notification contains deleted identifiers")
    func didSaveDeletedIdentifiers() throws {
        let container = try GraphContainer(
            for: NotificationUser.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        let user1 = NotificationUser(id: 1, name: "Alice")
        let user2 = NotificationUser(id: 2, name: "Bob")

        context.insert(user1)
        context.insert(user2)
        try context.save()

        nonisolated(unsafe) var deletedIds: [String] = []

        let observer = NotificationCenter.default.addObserver(
            forName: GraphContext.didSave,
            object: context,
            queue: nil
        ) { notification in
            if let userInfo = notification.userInfo,
               let ids = userInfo[GraphContext.NotificationKey.deletedIdentifiers.rawValue] as? [String] {
                deletedIds = ids
            }
        }

        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        context.delete(user1)
        try context.save()

        #expect(deletedIds.count == 1)
        #expect(deletedIds.contains { $0.contains("NotificationUser:1") })
    }

    @Test("No notifications when save has no changes")
    func noNotificationsWithoutChanges() throws {
        let container = try GraphContainer(
            for: NotificationUser.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        nonisolated(unsafe) var willSaveReceived = false
        nonisolated(unsafe) var didSaveReceived = false

        let willSaveObserver = NotificationCenter.default.addObserver(
            forName: GraphContext.willSave,
            object: context,
            queue: nil
        ) { _ in
            willSaveReceived = true
        }

        let didSaveObserver = NotificationCenter.default.addObserver(
            forName: GraphContext.didSave,
            object: context,
            queue: nil
        ) { _ in
            didSaveReceived = true
        }

        defer {
            NotificationCenter.default.removeObserver(willSaveObserver)
            NotificationCenter.default.removeObserver(didSaveObserver)
        }

        // Save with no changes
        try context.save()

        #expect(willSaveReceived == false)
        #expect(didSaveReceived == false)
    }

    @Test("Notifications posted in correct order")
    func notificationOrder() throws {
        let container = try GraphContainer(
            for: NotificationUser.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        nonisolated(unsafe) var events: [String] = []

        let willSaveObserver = NotificationCenter.default.addObserver(
            forName: GraphContext.willSave,
            object: context,
            queue: nil
        ) { _ in
            events.append("willSave")
        }

        let didSaveObserver = NotificationCenter.default.addObserver(
            forName: GraphContext.didSave,
            object: context,
            queue: nil
        ) { _ in
            events.append("didSave")
        }

        defer {
            NotificationCenter.default.removeObserver(willSaveObserver)
            NotificationCenter.default.removeObserver(didSaveObserver)
        }

        context.insert(NotificationUser(id: 1, name: "Alice"))
        try context.save()

        #expect(events.count == 2)
        #expect(events[0] == "willSave")
        #expect(events[1] == "didSave")
    }

    @Test("Multiple contexts post separate notifications")
    func multipleContexts() throws {
        let container = try GraphContainer(
            for: NotificationUser.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context1 = GraphContext(container)
        let context2 = GraphContext(container)

        nonisolated(unsafe) var context1SaveCount = 0
        nonisolated(unsafe) var context2SaveCount = 0

        let observer1 = NotificationCenter.default.addObserver(
            forName: GraphContext.didSave,
            object: context1,
            queue: nil
        ) { _ in
            context1SaveCount += 1
        }

        let observer2 = NotificationCenter.default.addObserver(
            forName: GraphContext.didSave,
            object: context2,
            queue: nil
        ) { _ in
            context2SaveCount += 1
        }

        defer {
            NotificationCenter.default.removeObserver(observer1)
            NotificationCenter.default.removeObserver(observer2)
        }

        context1.insert(NotificationUser(id: 1, name: "Alice"))
        try context1.save()

        context2.insert(NotificationUser(id: 2, name: "Bob"))
        try context2.save()

        #expect(context1SaveCount == 1)
        #expect(context2SaveCount == 1)
    }

    @Test("Notification userInfo contains all required keys")
    func notificationUserInfoStructure() throws {
        let container = try GraphContainer(
            for: NotificationUser.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )
        let context = GraphContext(container)

        nonisolated(unsafe) var receivedUserInfo: [AnyHashable: Any]?

        let observer = NotificationCenter.default.addObserver(
            forName: GraphContext.didSave,
            object: context,
            queue: nil
        ) { notification in
            receivedUserInfo = notification.userInfo
        }

        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        context.insert(NotificationUser(id: 1, name: "Alice"))
        try context.save()

        #expect(receivedUserInfo != nil)

        if let userInfo = receivedUserInfo {
            #expect(userInfo[GraphContext.NotificationKey.insertedIdentifiers.rawValue] != nil)
            #expect(userInfo[GraphContext.NotificationKey.deletedIdentifiers.rawValue] != nil)
            #expect(userInfo[GraphContext.NotificationKey.updatedIdentifiers.rawValue] != nil)
        }
    }
}
