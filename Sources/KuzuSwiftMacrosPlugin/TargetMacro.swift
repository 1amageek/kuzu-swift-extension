import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// @Target macro marks a property as the destination node in an edge relationship
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
public struct TargetMacro: PeerMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // @Target properties are metadata only - no code generation needed
        // The GraphEdgeMacro reads these annotations to generate DDL
        return []
    }
}

/// Diagnostic messages for @Target macro
enum TargetMacroDiagnostic: String, DiagnosticMessage {
    case missingKeyPath = "@Target requires a KeyPath argument, e.g., @Target(\\Post.id)"
    case invalidKeyPath = "KeyPath must be in the format \\NodeType.property"

    var severity: DiagnosticSeverity { .error }

    var message: String { self.rawValue }

    var diagnosticID: MessageID {
        MessageID(domain: "KuzuSwiftMacros", id: rawValue)
    }
}
