import Foundation

/// Represents a SET clause in a Cypher query for updating properties
public struct SetClause: QueryComponent {
    let assignments: [PropertyAssignment]
    
    private init(assignments: [PropertyAssignment]) {
        self.assignments = assignments
    }
    
    /// Creates a SET clause with a single property assignment
    public static func property(_ assignment: PropertyAssignment) -> SetClause {
        SetClause(assignments: [assignment])
    }
    
    /// Creates a SET clause with multiple property assignments
    public static func properties(_ assignments: PropertyAssignment...) -> SetClause {
        SetClause(assignments: assignments)
    }
    
    /// Creates a SET clause from a dictionary of property updates
    public static func properties(
        on alias: String,
        values: [String: any Sendable]
    ) -> SetClause {
        let assignments = values.map { key, value in
            PropertyAssignment(
                property: PropertyReference(alias: alias, property: key),
                value: .literal(value)
            )
        }
        return SetClause(assignments: assignments)
    }
    
    /// Adds additional property assignments
    public func and(_ assignment: PropertyAssignment) -> SetClause {
        SetClause(assignments: assignments + [assignment])
    }
    
    /// Adds multiple additional property assignments
    public func and(_ newAssignments: PropertyAssignment...) -> SetClause {
        SetClause(assignments: assignments + newAssignments)
    }
    
    public func toCypher() throws -> CypherFragment {
        var parameters: [String: any Sendable] = [:]
        var setClauses: [String] = []
        
        for assignment in assignments {
            let fragment = try assignment.toCypher()
            setClauses.append(fragment.query)
            for (key, value) in fragment.parameters {
                parameters[key] = value
            }
        }
        
        let query = "SET " + setClauses.joined(separator: ", ")
        return CypherFragment(query: query, parameters: parameters)
    }
}

/// Represents a property assignment in a SET clause
public struct PropertyAssignment {
    let property: PropertyReference
    let value: AssignmentValue
    
    public init(property: PropertyReference, value: AssignmentValue) {
        self.property = property
        self.value = value
    }
    
    /// Creates an assignment from a property path and value
    public static func assign(_ propertyPath: String, to value: any Sendable) -> PropertyAssignment {
        let prop = prop(propertyPath)
        return PropertyAssignment(property: prop, value: .literal(value))
    }
    
    /// Creates an assignment that copies from another property
    public static func copy(_ targetPath: String, from sourcePath: String) -> PropertyAssignment {
        let target = prop(targetPath)
        let source = prop(sourcePath)
        return PropertyAssignment(property: target, value: .property(source))
    }
    
    func toCypher() throws -> CypherFragment {
        switch value {
        case .literal(let val):
            let paramName = OptimizedParameterGenerator.lightweight()
            return CypherFragment(
                query: "\(property.cypher) = $\(paramName)",
                parameters: [paramName: val]
            )
            
        case .property(let prop):
            return CypherFragment(query: "\(property.cypher) = \(prop.cypher)")
            
        case .expression(let expr):
            return CypherFragment(query: "\(property.cypher) = \(expr)")
            
        case .null:
            return CypherFragment(query: "\(property.cypher) = NULL")
            
        case .increment(let amount):
            let paramName = OptimizedParameterGenerator.lightweight()
            return CypherFragment(
                query: "\(property.cypher) = \(property.cypher) + $\(paramName)",
                parameters: [paramName: amount]
            )
            
        case .decrement(let amount):
            let paramName = OptimizedParameterGenerator.lightweight()
            return CypherFragment(
                query: "\(property.cypher) = \(property.cypher) - $\(paramName)",
                parameters: [paramName: amount]
            )
            
        case .append(let value):
            let paramName = OptimizedParameterGenerator.lightweight()
            return CypherFragment(
                query: "\(property.cypher) = \(property.cypher) + $\(paramName)",
                parameters: [paramName: value]
            )
        }
    }
}

/// Types of values that can be assigned
public enum AssignmentValue {
    case literal(any Sendable)
    case property(PropertyReference)
    case expression(String)
    case null
    case increment(Double)
    case decrement(Double)
    case append(String)
}

// MARK: - Convenience Extensions

extension PropertyReference {
    /// Creates an assignment that sets this property to a value
    public func set(to value: any Sendable) -> PropertyAssignment {
        PropertyAssignment(property: self, value: .literal(value))
    }
    
    /// Creates an assignment that sets this property to another property's value
    public func set(to property: PropertyReference) -> PropertyAssignment {
        PropertyAssignment(property: self, value: .property(property))
    }
    
    /// Creates an assignment that sets this property to NULL
    public var setToNull: PropertyAssignment {
        PropertyAssignment(property: self, value: .null)
    }
    
    /// Creates an assignment that increments this property
    public func increment(by amount: Double = 1) -> PropertyAssignment {
        PropertyAssignment(property: self, value: .increment(amount))
    }
    
    /// Creates an assignment that decrements this property
    public func decrement(by amount: Double = 1) -> PropertyAssignment {
        PropertyAssignment(property: self, value: .decrement(amount))
    }
    
    /// Creates an assignment that appends to this string property
    public func append(_ value: String) -> PropertyAssignment {
        PropertyAssignment(property: self, value: .append(value))
    }
}