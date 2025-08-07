import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import Foundation

public struct IDMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        
        guard declaration.is(VariableDeclSyntax.self) else {
            let diagnostic = Diagnostic(
                node: declaration,
                message: PropertyMacroDiagnostic.mustBeAppliedToProperty
            )
            context.diagnose(diagnostic)
            return []
        }
        
        // Generate metadata comment (no actual code generation needed)
        return []
    }
}

public struct IndexMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        
        guard declaration.is(VariableDeclSyntax.self) else {
            let diagnostic = Diagnostic(
                node: declaration,
                message: PropertyMacroDiagnostic.mustBeAppliedToProperty
            )
            context.diagnose(diagnostic)
            return []
        }
        
        // Generate metadata comment (no actual code generation needed)
        return []
    }
}

public struct VectorMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        
        guard let variableDecl = declaration.as(VariableDeclSyntax.self) else {
            let diagnostic = Diagnostic(
                node: declaration,
                message: PropertyMacroDiagnostic.mustBeAppliedToProperty
            )
            context.diagnose(diagnostic)
            return []
        }
        
        // Validate Array<Double> or [Double] type
        guard let binding = variableDecl.bindings.first,
              let typeAnnotation = binding.typeAnnotation?.type else {
            return []
        }
        
        let typeString = typeAnnotation.description.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let isValidType = typeString.contains("Array<Double>") || 
                         typeString.contains("[Double]") ||
                         typeString.contains("Array<Double>?") ||
                         typeString.contains("[Double]?")
        
        if !isValidType {
            let diagnostic = Diagnostic(
                node: typeAnnotation,
                message: PropertyMacroDiagnostic.vectorRequiresArray
            )
            context.diagnose(diagnostic)
            return []
        }
        
        // Validate dimensions parameter
        guard case .argumentList(let arguments) = node.arguments,
              let dimensionsArg = arguments.first(where: { $0.label?.text == "dimensions" }),
              let dimensionsExpr = dimensionsArg.expression.as(IntegerLiteralExprSyntax.self),
              let dimensions = Int(dimensionsExpr.literal.text),
              dimensions > 0 else {
            let diagnostic = Diagnostic(
                node: node,
                message: PropertyMacroDiagnostic.invalidVectorDimensions
            )
            context.diagnose(diagnostic)
            return []
        }
        
        // Generate metadata comment for debugging (no actual code generation needed)
        return []
    }
}

public struct FullTextSearchMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        
        guard let variableDecl = declaration.as(VariableDeclSyntax.self) else {
            let diagnostic = Diagnostic(
                node: declaration,
                message: PropertyMacroDiagnostic.mustBeAppliedToProperty
            )
            context.diagnose(diagnostic)
            return []
        }
        
        // Validate String type
        guard let binding = variableDecl.bindings.first,
              let typeAnnotation = binding.typeAnnotation?.type else {
            return []
        }
        
        let typeString = typeAnnotation.description.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let isStringType = typeString == "String" || typeString == "String?"
        
        if !isStringType {
            let diagnostic = Diagnostic(
                node: typeAnnotation,
                message: MacroExpansionErrorMessage("@FullTextSearch can only be applied to String properties")
            )
            context.diagnose(diagnostic)
            return []
        }
        
        // Generate metadata comment (no actual code generation needed)
        return []
    }
}

public struct TimestampMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        
        guard declaration.is(VariableDeclSyntax.self) else {
            let diagnostic = Diagnostic(
                node: declaration,
                message: PropertyMacroDiagnostic.mustBeAppliedToProperty
            )
            context.diagnose(diagnostic)
            return []
        }
        
        // Generate metadata comment (no actual code generation needed)
        return []
    }
}

public struct UniqueMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        
        guard declaration.is(VariableDeclSyntax.self) else {
            let diagnostic = Diagnostic(
                node: declaration,
                message: PropertyMacroDiagnostic.mustBeAppliedToProperty
            )
            context.diagnose(diagnostic)
            return []
        }
        
        // Generate metadata comment (no actual code generation needed)
        return []
    }
}

public struct DefaultMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        
        guard declaration.is(VariableDeclSyntax.self) else {
            let diagnostic = Diagnostic(
                node: declaration,
                message: PropertyMacroDiagnostic.mustBeAppliedToProperty
            )
            context.diagnose(diagnostic)
            return []
        }
        
        // Extract default value from arguments
        guard case .argumentList(let arguments) = node.arguments,
              let firstArg = arguments.first else {
            let diagnostic = Diagnostic(
                node: node,
                message: MacroExpansionErrorMessage("@Default requires a value argument")
            )
            context.diagnose(diagnostic)
            return []
        }
        
        let _ = firstArg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Generate metadata comment (no actual code generation needed)
        return []
    }
}

