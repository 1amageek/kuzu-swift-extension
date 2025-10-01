import Foundation

/// Marks a property as transient (not persisted to the database)
///
/// Use this macro on properties that should be excluded from database persistence.
/// This is compatible with SwiftData's @Transient macro.
///
/// Example:
/// ```swift
/// @GraphNode
/// struct User: Codable {
///     @ID var id: UUID
///     var name: String
///
///     @Transient
///     var displayName: String {
///         name.uppercased()
///     }
/// }
/// ```
@attached(peer)
public macro Transient() = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "TransientMacro"
)
