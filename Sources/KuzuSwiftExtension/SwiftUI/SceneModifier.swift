#if canImport(SwiftUI)
import SwiftUI

@available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, *)
public extension Scene {
    /// Injects a GraphContainer into the environment for this scene
    ///
    /// SwiftData-compatible API for graph database integration.
    ///
    /// Usage:
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     let container = try! GraphContainer(for: User.self, Post.self)
    ///
    ///     var body: some Scene {
    ///         WindowGroup {
    ///             ContentView()
    ///         }
    ///         .graphContainer(container)
    ///     }
    /// }
    /// ```
    ///
    /// Views can then access the container or context:
    /// ```swift
    /// struct ContentView: View {
    ///     @Environment(\.graphContext) var context
    ///
    ///     var body: some View {
    ///         Button("Add User") {
    ///             context.insert(User(name: "Alice"))
    ///             try? context.save()
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter container: The GraphContainer to inject into the environment
    /// - Returns: A scene with the container available in the environment
    func graphContainer(_ container: GraphContainer) -> some Scene {
        environment(\.graphContainer, container)
    }
}

@available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, *)
public extension View {
    /// Injects a GraphContainer into the environment for this view hierarchy
    ///
    /// Use this modifier when you need to inject a container at the view level
    /// rather than the scene level.
    ///
    /// Usage:
    /// ```swift
    /// struct ParentView: View {
    ///     let container = try! GraphContainer(for: User.self)
    ///
    ///     var body: some View {
    ///         ChildView()
    ///             .graphContainer(container)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter container: The GraphContainer to inject into the environment
    /// - Returns: A view with the container available in the environment
    func graphContainer(_ container: GraphContainer) -> some View {
        environment(\.graphContainer, container)
    }
}
#endif
