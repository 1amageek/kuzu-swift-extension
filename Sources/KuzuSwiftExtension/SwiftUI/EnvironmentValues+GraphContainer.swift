#if canImport(SwiftUI)
import SwiftUI

@available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, *)
public extension EnvironmentValues {
    /// The graph container for the current environment
    ///
    /// Access the container injected via `.graphContainer()` modifier:
    /// ```swift
    /// struct MyView: View {
    ///     @Environment(\.graphContainer) var container
    ///
    ///     var body: some View {
    ///         Text("Database: \(container?.configuration.databasePath ?? "none")")
    ///     }
    /// }
    /// ```
    var graphContainer: GraphContainer? {
        get { self[GraphContainerKey.self] }
        set { self[GraphContainerKey.self] = newValue }
    }

    /// The main context for the current environment's graph container
    ///
    /// Provides direct access to a @MainActor-bound GraphContext:
    /// ```swift
    /// struct MyView: View {
    ///     @Environment(\.graphContext) var context
    ///
    ///     var body: some View {
    ///         Button("Save User") {
    ///             context.insert(User(name: "Alice"))
    ///             try? context.save()
    ///         }
    ///     }
    /// }
    /// ```
    @MainActor
    var graphContext: GraphContext {
        guard let container = graphContainer else {
            fatalError("No GraphContainer found in environment. Use .graphContainer() modifier.")
        }
        return container.mainContext
    }
}
#endif
