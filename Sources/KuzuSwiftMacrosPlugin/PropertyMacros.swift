import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import Foundation

// MARK: - Base Property Macro

/// Base implementation for property-based macros
protocol BasePropertyMacro: PeerMacro {
    /// Validate specific requirements for this macro
    static func validate(
        _ node: AttributeSyntax,
        _ declaration: VariableDeclSyntax,
        in context: some MacroExpansionContext
    ) -> Bool
}

extension BasePropertyMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        
        guard let variableDecl = declaration.as(VariableDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: declaration,
                message: PropertyMacroDiagnostic.mustBeAppliedToProperty
            ))
            return []
        }
        
        // Perform specific validation for this macro type
        _ = validate(node, variableDecl, in: context)
        
        // Generate metadata comment (no actual code generation needed)
        return []
    }
}

// MARK: - Simple Property Macros

public struct IDMacro: BasePropertyMacro {
    static func validate(_ node: AttributeSyntax, _ declaration: VariableDeclSyntax, in context: some MacroExpansionContext) -> Bool {
        true // No additional validation needed
    }
}

public struct IndexMacro: BasePropertyMacro {
    static func validate(_ node: AttributeSyntax, _ declaration: VariableDeclSyntax, in context: some MacroExpansionContext) -> Bool {
        true // No additional validation needed
    }
}

public struct TimestampMacro: BasePropertyMacro {
    static func validate(_ node: AttributeSyntax, _ declaration: VariableDeclSyntax, in context: some MacroExpansionContext) -> Bool {
        true // No additional validation needed
    }
}

public struct UniqueMacro: BasePropertyMacro {
    static func validate(_ node: AttributeSyntax, _ declaration: VariableDeclSyntax, in context: some MacroExpansionContext) -> Bool {
        true // No additional validation needed
    }
}

// MARK: - Complex Property Macros

public struct VectorMacro: BasePropertyMacro {
    static func validate(_ node: AttributeSyntax, _ declaration: VariableDeclSyntax, in context: some MacroExpansionContext) -> Bool {
        // Validate Array<Float>, Array<Double>, [Float], or [Double] type
        guard let binding = declaration.bindings.first,
              let typeAnnotation = binding.typeAnnotation?.type else {
            return false
        }

        let typeString = typeAnnotation.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let isValidType = typeString.contains("Array<Double>") ||
                         typeString.contains("[Double]") ||
                         typeString.contains("Array<Double>?") ||
                         typeString.contains("[Double]?") ||
                         typeString.contains("Array<Float>") ||
                         typeString.contains("[Float]") ||
                         typeString.contains("Array<Float>?") ||
                         typeString.contains("[Float]?")

        if !isValidType {
            context.diagnose(Diagnostic(
                node: typeAnnotation,
                message: PropertyMacroDiagnostic.vectorRequiresArray
            ))
            return false
        }

        // Validate dimensions parameter
        guard case .argumentList(let arguments) = node.arguments,
              let dimensionsArg = arguments.first(where: { $0.label?.text == "dimensions" }),
              let dimensionsExpr = dimensionsArg.expression.as(IntegerLiteralExprSyntax.self),
              let dimensions = Int(dimensionsExpr.literal.text),
              dimensions > 0 else {
            context.diagnose(Diagnostic(
                node: node,
                message: PropertyMacroDiagnostic.invalidVectorDimensions
            ))
            return false
        }

        // Validate metric parameter if present
        if case .argumentList(let arguments) = node.arguments,
           let metricArg = arguments.first(where: { $0.label?.text == "metric" }) {
            // Metric is optional with default value, just check syntax if provided
            let metricExpr = metricArg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let validMetrics = [".l2", ".cosine", ".innerProduct", "VectorMetric.l2", "VectorMetric.cosine", "VectorMetric.innerProduct"]
            if !validMetrics.contains(where: { metricExpr.contains($0) }) {
                context.diagnose(Diagnostic(
                    node: metricArg.expression,
                    message: MacroExpansionErrorMessage("Invalid metric value. Use .l2, .cosine, or .innerProduct")
                ))
                return false
            }
        }

        return true
    }
}

public struct FullTextSearchMacro: BasePropertyMacro {
    static func validate(_ node: AttributeSyntax, _ declaration: VariableDeclSyntax, in context: some MacroExpansionContext) -> Bool {
        // Validate String type
        guard let binding = declaration.bindings.first,
              let typeAnnotation = binding.typeAnnotation?.type else {
            return false
        }
        
        let typeString = typeAnnotation.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let isStringType = typeString == "String" || typeString == "String?"
        
        if !isStringType {
            context.diagnose(Diagnostic(
                node: typeAnnotation,
                message: MacroExpansionErrorMessage("@FullTextSearch can only be applied to String properties")
            ))
            return false
        }
        
        return true
    }
}

public struct DefaultMacro: BasePropertyMacro {
    static func validate(_ node: AttributeSyntax, _ declaration: VariableDeclSyntax, in context: some MacroExpansionContext) -> Bool {
        // Extract default value from arguments
        guard case .argumentList(let arguments) = node.arguments,
              arguments.first != nil else {
            context.diagnose(Diagnostic(
                node: node,
                message: MacroExpansionErrorMessage("@Default requires a value argument")
            ))
            return false
        }
        
        return true
    }
}