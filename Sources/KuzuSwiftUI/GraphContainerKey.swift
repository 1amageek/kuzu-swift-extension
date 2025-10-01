#if canImport(SwiftUI)
import SwiftUI
import KuzuSwiftExtension

/// Environment key for accessing GraphContainer in SwiftUI views
///
/// This key enables SwiftData-style container injection:
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
@available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, *)
struct GraphContainerKey: EnvironmentKey {
    static let defaultValue: GraphContainer? = nil
}
#endif
