import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - Common Diagnostic Types

/// A generic note message for macro expansions
public struct MacroExpansionNoteMessage: NoteMessage {
    public let message: String
    
    public init(_ message: String) {
        self.message = message
    }
    
    public var noteID: MessageID {
        MessageID(domain: "KuzuSwiftMacros", id: "note")
    }
}

/// A generic error message for macro expansions
public struct MacroExpansionErrorMessage: DiagnosticMessage {
    public let message: String
    
    public init(_ message: String) {
        self.message = message
    }
    
    public var diagnosticID: MessageID {
        MessageID(domain: "KuzuSwiftMacros", id: "custom-error")
    }
    
    public var severity: DiagnosticSeverity {
        .error
    }
}

// MARK: - Specific Diagnostic Types

enum GraphNodeDiagnostic: String, DiagnosticMessage {
    case mustBeAppliedToStruct = "graph-node-must-be-struct"
    case missingIDProperty = "graph-node-missing-id"
    case duplicatePrimaryKey = "graph-node-duplicate-primary-key"
    
    var message: String {
        switch self {
        case .mustBeAppliedToStruct:
            return "@GraphNode can only be applied to structs"
        case .missingIDProperty:
            return "@GraphNode requires at least one property marked with @ID"
        case .duplicatePrimaryKey:
            return "Only one property can be marked with @ID (PRIMARY KEY)"
        }
    }
    
    var diagnosticID: MessageID {
        MessageID(domain: "KuzuSwiftMacros", id: rawValue)
    }
    
    var severity: DiagnosticSeverity {
        .error
    }
}

enum GraphEdgeDiagnostic: String, DiagnosticMessage {
    case mustBeAppliedToStruct = "graph-edge-must-be-struct"
    case missingParameters = "graph-edge-missing-parameters"
    case invalidFromType = "graph-edge-invalid-from-type"
    case invalidToType = "graph-edge-invalid-to-type"
    
    var message: String {
        switch self {
        case .mustBeAppliedToStruct:
            return "@GraphEdge can only be applied to structs"
        case .missingParameters:
            return "@GraphEdge requires 'from' and 'to' type parameters"
        case .invalidFromType:
            return "The 'from' parameter must be a type annotated with @GraphNode"
        case .invalidToType:
            return "The 'to' parameter must be a type annotated with @GraphNode"
        }
    }
    
    var diagnosticID: MessageID {
        MessageID(domain: "KuzuSwiftMacros", id: rawValue)
    }
    
    var severity: DiagnosticSeverity {
        .error
    }
}

enum PropertyMacroDiagnostic: String, DiagnosticMessage {
    case mustBeAppliedToProperty = "property-macro-must-be-property"
    case invalidVectorDimensions = "vector-invalid-dimensions"
    case vectorRequiresArray = "vector-requires-array"
    
    var message: String {
        switch self {
        case .mustBeAppliedToProperty:
            return "Property macros can only be applied to stored properties"
        case .invalidVectorDimensions:
            return "@Vector requires a positive dimensions parameter"
        case .vectorRequiresArray:
            return "@Vector can only be applied to Array<Double> properties"
        }
    }
    
    var diagnosticID: MessageID {
        MessageID(domain: "KuzuSwiftMacros", id: rawValue)
    }
    
    var severity: DiagnosticSeverity {
        .error
    }
}