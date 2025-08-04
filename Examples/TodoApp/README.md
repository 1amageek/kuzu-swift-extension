# Todo App Example

kuzu-swift-extensionを使用したフル機能のTodoアプリケーションのサンプルです。

## 特徴

- 🚀 **ゼロコンフィグ** - データベースパスの設定不要
- 💾 **永続化** - アプリを再起動してもデータが保持される
- 🎯 **型安全** - Swiftの型システムを活用
- 🔄 **CRUD操作** - 作成・読み取り・更新・削除の全操作を実装
- 🔍 **検索機能** - タイトルでTodoを検索
- 📊 **ソート機能** - 日付や完了状態でソート
- 🎬 **バルク操作** - 一括完了・削除
- 💾 **エクスポート/インポート** - JSON形式でデータの保存・復元
- 🧪 **テスト完備** - ユニットテスト・統合テスト付き

## 実行方法

### コマンドラインアプリ

```bash
cd Examples/TodoApp
swift run TodoCLI
```

### テスト実行

```bash
cd Examples/TodoApp
swift test
```

### 実装のポイント

```swift
// 1. モデル定義 - @GraphNodeマクロで簡単に定義
@GraphNode
struct Todo {
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

## 機能一覧

### 基本機能
- ✅ Todo作成・表示・更新・削除
- ✅ 完了状態の切り替え
- ✅ Todo統計表示（総数・完了・未完了）

### 高度な機能
- ✅ **検索** - タイトルの部分一致検索（CONTAINS）
- ✅ **ソート** - 作成日時（新しい順/古い順）、完了状態別
- ✅ **バルク操作**
  - 全Todo完了/未完了切り替え
  - 完了済みTodo一括削除
  - 全Todo削除
- ✅ **エクスポート/インポート**
  - JSON形式でのエクスポート
  - 既存データへの追加インポート
  - 全データ置換インポート

## 学習ポイント

1. **ゼロコンフィグ設計** - GraphDatabase.sharedで即座に利用開始
2. **SwiftDataライクなAPI** - 既存の知識を活かせる設計
3. **型安全なモデル定義** - マクロによる自動スキーマ生成
4. **非同期処理** - Swift Concurrencyを活用した設計
5. **Cypherクエリ** - 高度な検索・更新処理の実装
6. **テスト戦略** - ユニットテストと統合テストの分離

## 次のステップ

- リレーションシップを追加（タグ、カテゴリなど）
- グラフの可視化
- パフォーマンス最適化
- SwiftUIアプリへの組み込み