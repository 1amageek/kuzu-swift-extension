import Foundation
import KuzuSwiftExtension

// 1. モデル定義
@GraphNode
struct Todo: Codable {
    @ID var id: UUID = UUID()
    var title: String
    var done: Bool = false
    @Timestamp var createdAt: Date = Date()
}

// 2. 使い方（3行で動く！）
@main
struct QuickStart {
    static func main() async throws {
        // グラフDBの初期化（ファイルパス自動設定）
        let graph = try await GraphDatabase.shared.context()
        
        // Todoを保存
        let todo = Todo(title: "買い物")
        try await graph.save(todo)
        
        // 全件取得
        let todos = try await graph.fetch(Todo.self)
        print(todos) // [Todo(id: ..., title: "買い物", done: false)]
    }
}