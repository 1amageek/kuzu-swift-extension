import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// @Since macro marks a property as the source node in an edge relationship
///
/// The property must reference a GraphNodeModel and specify a KeyPath to identify the node.
///
/// Example:
/// ```swift
/// @GraphEdge
/// struct Authored: Codable {
///     @Since(\User.id) var author: User
///     @Target(\Post.id) var post: Post
/// }
/// ```
public struct SinceMacro: PeerMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // @Since properties are metadata only - no code generation needed
        // The GraphEdgeMacro reads these annotations to generate DDL
        return []
    }
}

/// Diagnostic messages for @Since macro
enum SinceMacroDiagnostic: String, DiagnosticMessage {
    case missingKeyPath = "@Since requires a KeyPath argument, e.g., @Since(\\User.id)"
    case invalidKeyPath = "KeyPath must be in the format \\NodeType.property"

    var severity: DiagnosticSeverity { .error }

    var message: String { self.rawValue }

    var diagnosticID: MessageID {
        MessageID(domain: "KuzuSwiftMacros", id: rawValue)
    }
}
