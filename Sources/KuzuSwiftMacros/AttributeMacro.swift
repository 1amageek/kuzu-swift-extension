import Foundation
import KuzuSwiftProtocols

/// Configures attribute-level options for properties
///
/// Use this macro to customize property behavior with various options.
/// This is compatible with SwiftData's @Attribute macro.
///
/// Example:
/// ```swift
/// @GraphNode
/// struct User: Codable {
///     @ID var id: UUID
///
///     @Attribute(.unique)
///     var email: String
///
///     @Attribute(.spotlight)
///     var bio: String
///
///     @Attribute(.originalName("user_name"))
///     var name: String
/// }
/// ```
@attached(peer)
public macro Attribute(_ options: AttributeOption...) = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "AttributeMacro"
)
