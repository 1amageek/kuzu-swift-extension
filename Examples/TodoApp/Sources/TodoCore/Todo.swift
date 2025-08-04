import Foundation
import KuzuSwiftExtension

@GraphNode
public struct Todo {
    @ID public var id: UUID
    public var title: String
    public var done: Bool
    @Timestamp public var createdAt: Date
    
    public init(
        id: UUID = UUID(),
        title: String,
        done: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.done = done
        self.createdAt = createdAt
    }
}