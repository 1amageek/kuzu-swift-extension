# Kuzu Swift Extension

**SQLite並みに簡単に使えるグラフデータベース** - Swift開発者のための型安全なグラフDB拡張ライブラリ

![Swift 6.1+](https://img.shields.io/badge/Swift-6.1+-orange.svg)
![Platform](https://img.shields.io/badge/platform-macOS%20|%20iOS%20|%20tvOS%20|%20watchOS-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)

## 特徴

- ✨ **ゼロコンフィグ** - `GraphDatabase.shared` で即座に開始
- 🎯 **SwiftDataライクなAPI** - `save()`, `fetch()`, `delete()` の直感的なメソッド
- 🔄 **自動スキーマ管理** - モデルを定義するだけでDDLを自動生成
- 🏗️ **型安全** - Swiftマクロによるコンパイル時のエラー検出
- 🚀 **モダンSwift** - async/await完全対応

## インストール

### Swift Package Manager

Xcodeでプロジェクトを開き、File → Add Package Dependencies で以下のURLを追加：

```
https://github.com/1amageek/kuzu-swift-extension
```

または `Package.swift` に追加：

```swift
.package(url: "https://github.com/1amageek/kuzu-swift-extension", from: "0.2.0")
```

## 一行目から動く！クイックスタート

### 1. モデル定義（Todo.swift）

```swift
import KuzuSwiftExtension

@GraphNode
struct Todo: Codable {
    @ID var id: UUID = UUID()
    var title: String
    var done: Bool = false
    @Timestamp var createdAt: Date = Date()
}
```

### 2. 使い方（3行で動く！）

```swift
// グラフDBの初期化（ファイルパス自動設定）
let graph = try await GraphDatabase.shared.context()

// Todoを保存
let todo = Todo(title: "買い物")
try await graph.save(todo)

// 全件取得
let todos = try await graph.fetch(Todo.self)
print(todos) // [Todo(id: ..., title: "買い物", done: false)]
```

### 3. もう少し実践的な例

```swift
import SwiftUI
import KuzuSwiftExtension

// SwiftUIで使う場合
struct ContentView: View {
    @State private var todos: [Todo] = []
    @State private var newTodoTitle = ""
    
    var body: some View {
        VStack {
            // Todo入力
            HStack {
                TextField("新しいTodo", text: $newTodoTitle)
                Button("追加") {
                    Task {
                        let todo = Todo(title: newTodoTitle)
                        let graph = try await GraphDatabase.shared.context()
                        try await graph.save(todo)
                        todos = try await graph.fetch(Todo.self)
                        newTodoTitle = ""
                    }
                }
            }
            
            // Todoリスト
            List(todos, id: \.id) { todo in
                HStack {
                    Text(todo.title)
                    Spacer()
                    if todo.done {
                        Image(systemName: "checkmark")
                    }
                }
                .onTapGesture {
                    Task {
                        var updatedTodo = todo
                        updatedTodo.done.toggle()
                        let graph = try await GraphDatabase.shared.context()
                        try await graph.save(updatedTodo)
                        todos = try await graph.fetch(Todo.self)
                    }
                }
            }
        }
        .task {
            let graph = try await GraphDatabase.shared.context()
            todos = try await graph.fetch(Todo.self)
        }
    }
}
```

## より高度な使い方

### SwiftDataライクなCRUD操作

```swift
let graph = try await GraphDatabase.shared.context()

// 1件取得
if let todo = try await graph.fetchOne(Todo.self, id: todoId) {
    print(todo)
}

// 条件検索
let completedTodos = try await graph.fetch(Todo.self, where: "done", equals: true)

// 削除
try await graph.delete(todo)
try await graph.deleteAll(Todo.self)

// カウント
let count = try await graph.count(Todo.self)
```

### リレーションシップ（フォロー機能）

```swift
@GraphNode 
struct User: Codable {
    @ID var id: UUID = UUID()
    var name: String
}

@GraphEdge(from: User.self, to: User.self)
struct Follows: Codable {
    @Timestamp var since: Date = Date()
}

// フォロー関係を作成
let alice = User(name: "Alice")
let bob = User(name: "Bob")

try await graph.save([alice, bob])
try await graph.createRelationship(
    from: alice,
    to: bob, 
    edge: Follows()
)
```

## 従来の高度な機能

### プロパティアノテーション

```swift
@GraphNode
struct Document: Codable {
    @ID var id: UUID = UUID()
    @Index var title: String
    @FTS var content: String  // 全文検索
    @Vector(dimensions: 1536) var embedding: [Double]  // ベクトル検索
    @Timestamp var createdAt: Date = Date()  // 自動タイムスタンプ
}
```

### 複雑なクエリ（Query DSL）

```swift
// 共通の興味を持つユーザーを検索
let result = try await graph.query {
    Match.node(User.self, alias: "u1")
    Match.node(Interest.self, alias: "i")
    Match.node(User.self, alias: "u2", where: property("u2", "id") != property("u1", "id"))
    Match.edge(HasInterest.self).from("u1").to("i")
    Match.edge(HasInterest.self).from("u2").to("i")
    Return.items(.alias("u1"), .alias("u2"), .alias("i"))
        .orderBy("i.name")
        .limit(10)
}
```

### 生のCypherクエリ

```swift
// パラメータバインディング付きCypher実行
let result = try await graph.raw(
    """
    MATCH (u:User {name: $name})-[:FOLLOWS]->(f:User)
    RETURN f
    """,
    bindings: ["name": "Alice"]
)
```

### トランザクション

```swift
// トランザクション内での操作
try await graph.transaction { ctx in
    let charlie = User(name: "Charlie")
    try await ctx.save(charlie)
    
    try await ctx.createRelationship(
        from: alice,
        to: charlie,
        edge: Follows()
    )
}
```

### スキーマの自動マイグレーション

```swift
// モデルを登録しておけば、初回起動時に自動でスキーマ作成
GraphDatabase.shared.register(models: [
    Todo.self,
    User.self,
    Follows.self
])

// 手動でマイグレーション実行も可能
let graph = try await GraphDatabase.shared.context()
try await graph.createSchema(for: [Todo.self])
```

## なぜグラフデータベース？

- **関係性の表現が自然** - フォロー、いいね、友達関係などを直感的にモデル化
- **高速なグラフ探索** - 共通の友達、推薦、最短経路などの計算が高速
- **柔軟なスキーマ** - ノードやエッジに自由にプロパティを追加可能

## 要件

- Swift 6.1+
- macOS 14+, iOS 17+, tvOS 17+, watchOS 10+

## ライセンス

MIT License

## 謝辞

[Kuzu](https://kuzudb.com) グラフデータベースと[Swift bindings](https://github.com/kuzudb/kuzu-swift)の素晴らしいプロジェクトの上に構築されています。