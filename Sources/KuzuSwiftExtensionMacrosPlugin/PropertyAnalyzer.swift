import SwiftSyntax

struct PropertyInfo {
    let name: String
    let type: String
    let swiftType: TypeSyntax
    let isOptional: Bool
    let isID: Bool
    let isIndex: Bool
    let isUniqueIndex: Bool
    let isVector: Bool
    let vectorDimensions: Int?
    let isFTS: Bool
    let isTimestamp: Bool
    let hasDefaultNow: Bool
}

struct PropertyAnalyzer {
    func analyze(members: MemberBlockItemListSyntax) -> [PropertyInfo] {
        var properties: [PropertyInfo] = []
        
        for member in members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  let binding = variable.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeAnnotation = binding.typeAnnotation else {
                continue
            }
            
            let name = identifier.identifier.text
            let type = typeAnnotation.type
            
            // Check for property wrappers
            let attributes = variable.attributes
            let isID = hasAttribute(attributes, named: "ID")
            let isIndex = hasAttribute(attributes, named: "Index")
            let isUniqueIndex = hasUniqueIndexAttribute(attributes)
            let isVector = hasAttribute(attributes, named: "Vector")
            let vectorDimensions = extractVectorDimensions(attributes)
            let isFTS = hasAttribute(attributes, named: "FTS")
            let isTimestamp = hasAttribute(attributes, named: "Timestamp")
            let hasDefaultNow = hasTimestampDefaultNow(attributes)
            
            // Determine if optional
            let isOptional = type.is(OptionalTypeSyntax.self)
            
            // Extract base type
            let baseType = extractBaseType(type)
            
            properties.append(PropertyInfo(
                name: name,
                type: baseType,
                swiftType: type,
                isOptional: isOptional,
                isID: isID,
                isIndex: isIndex,
                isUniqueIndex: isUniqueIndex,
                isVector: isVector,
                vectorDimensions: vectorDimensions,
                isFTS: isFTS,
                isTimestamp: isTimestamp,
                hasDefaultNow: hasDefaultNow
            ))
        }
        
        return properties
    }
    
    private func hasAttribute(_ attributes: AttributeListSyntax, named name: String) -> Bool {
        attributes.contains { attribute in
            guard case .attribute(let attr) = attribute else { return false }
            return attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text == name
        }
    }
    
    private func hasUniqueIndexAttribute(_ attributes: AttributeListSyntax) -> Bool {
        for attribute in attributes {
            guard case .attribute(let attr) = attribute,
                  attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Index",
                  let arguments = attr.arguments?.as(LabeledExprListSyntax.self) else {
                continue
            }
            
            for arg in arguments {
                if arg.label?.text == "unique",
                   let boolExpr = arg.expression.as(BooleanLiteralExprSyntax.self),
                   boolExpr.literal.text == "true" {
                    return true
                }
            }
        }
        return false
    }
    
    private func extractVectorDimensions(_ attributes: AttributeListSyntax) -> Int? {
        for attribute in attributes {
            guard case .attribute(let attr) = attribute,
                  attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Vector",
                  let arguments = attr.arguments?.as(LabeledExprListSyntax.self) else {
                continue
            }
            
            for arg in arguments {
                if arg.label?.text == "dimensions",
                   let intExpr = arg.expression.as(IntegerLiteralExprSyntax.self) {
                    return Int(intExpr.literal.text)
                }
            }
        }
        return nil
    }
    
    private func hasTimestampDefaultNow(_ attributes: AttributeListSyntax) -> Bool {
        for attribute in attributes {
            guard case .attribute(let attr) = attribute,
                  attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Timestamp",
                  let arguments = attr.arguments?.as(LabeledExprListSyntax.self) else {
                continue
            }
            
            for arg in arguments {
                if arg.label?.text == "default",
                   let memberExpr = arg.expression.as(MemberAccessExprSyntax.self),
                   memberExpr.declName.baseName.text == "now" {
                    return true
                }
            }
        }
        return false
    }
    
    private func extractBaseType(_ type: TypeSyntax) -> String {
        if let optional = type.as(OptionalTypeSyntax.self) {
            return extractBaseType(optional.wrappedType)
        }
        
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        
        if let array = type.as(ArrayTypeSyntax.self) {
            return "[\(extractBaseType(array.element))]"
        }
        
        return type.description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}