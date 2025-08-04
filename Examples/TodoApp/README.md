# Todo App Example

kuzu-swift-extensionを使用したシンプルなTodoアプリケーションのサンプルです。

## 特徴

- 🚀 **ゼロコンフィグ** - データベースパスの設定不要
- 💾 **永続化** - アプリを再起動してもデータが保持される
- 🎯 **型安全** - Swiftの型システムを活用
- 🔄 **CRUD操作** - 作成・読み取り・更新・削除の全操作を実装

## 実行方法

### コマンドラインアプリ

```bash
cd Examples/TodoApp
swift run TodoCLI
```

### 実装のポイント

```swift
// 1. モデル定義 - @GraphNodeマクロで簡単に定義
@GraphNode
struct Todo: Codable {
    @ID var id: UUID = UUID()
    var title: String
    var done: Bool = false
    @Timestamp var createdAt: Date = Date()
}

// 2. データベース初期化 - たった2行！
GraphDatabase.shared.register(models: [Todo.self])
let graph = try await GraphDatabase.shared.context()

// 3. CRUD操作 - SwiftDataライクなAPI
let todo = Todo(title: "買い物")
try await graph.save(todo)                    // 保存
let todos = try await graph.fetch(Todo.self)  // 全件取得
try await graph.delete(todo)                  // 削除
```

## iOS/macOSアプリへの組み込み

SwiftUIアプリケーションに組み込む場合：

```swift
import SwiftUI
import KuzuSwiftExtension

@main
struct TodoApp: App {
    init() {
        // アプリ起動時にモデルを登録
        GraphDatabase.shared.register(models: [Todo.self])
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var todos: [Todo] = []
    
    var body: some View {
        List(todos) { todo in
            HStack {
                Text(todo.title)
                Spacer()
                if todo.done {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
        }
        .task {
            // ビュー表示時にデータを読み込み
            let graph = try? await GraphDatabase.shared.context()
            todos = (try? await graph?.fetch(Todo.self)) ?? []
        }
    }
}
```

## 学習ポイント

1. **ゼロコンフィグ設計** - GraphDatabase.sharedで即座に利用開始
2. **SwiftDataライクなAPI** - 既存の知識を活かせる設計
3. **型安全なモデル定義** - マクロによる自動スキーマ生成
4. **非同期処理** - Swift Concurrencyを活用した設計

## 次のステップ

- リレーションシップを追加（タグ、カテゴリなど）
- 検索機能の実装
- グラフの可視化
- パフォーマンス最適化