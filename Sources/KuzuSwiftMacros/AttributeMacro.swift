import Foundation
import KuzuSwiftProtocols

/// Configures attribute-level options for properties
///
/// Use this macro to customize property behavior with various options.
///
/// Available options:
/// - `.spotlight`: Enable Full-Text Search indexing (BM25-based)
///
/// Example:
/// ```swift
/// @GraphNode
/// struct Article: Codable {
///     @ID var id: UUID
///
///     @Attribute(.spotlight)
///     var content: String  // Full-Text Search index
/// }
/// ```
///
/// For custom column names, use CodingKeys:
/// ```swift
/// @GraphNode
/// struct Article: Codable {
///     enum CodingKeys: String, CodingKey {
///         case id
///         case articleTitle = "title"  // Database column: "title"
///     }
///
///     @ID var id: UUID
///     var articleTitle: String
/// }
/// ```
@attached(peer)
public macro Attribute(_ options: AttributeOption...) = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "AttributeMacro"
)
