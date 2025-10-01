import Foundation
import KuzuSwiftProtocols

/// Configures attribute-level options for properties
///
/// Use this macro to customize property behavior with various options.
///
/// Available options:
/// - `.spotlight`: Enable Full-Text Search indexing (BM25-based)
/// - `.originalName(String)`: Custom column name in database
///
/// Example:
/// ```swift
/// @GraphNode
/// struct Article: Codable {
///     @ID var id: UUID
///
///     @Attribute(.spotlight)
///     var content: String  // Full-Text Search index
///
///     @Attribute(.originalName("article_title"))
///     var title: String
/// }
/// ```
@attached(peer)
public macro Attribute(_ options: AttributeOption...) = #externalMacro(
    module: "KuzuSwiftMacrosPlugin",
    type: "AttributeMacro"
)
