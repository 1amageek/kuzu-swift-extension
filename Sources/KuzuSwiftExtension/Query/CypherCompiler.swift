import Foundation

enum CypherCompiler {
    struct CompiledQuery {
        let cypher: String
        let bindings: [String: any Encodable]
    }
    
    static func compile<T>(_ query: Query<T>) throws -> CompiledQuery {
        var cypher = ""
        var bindings: [String: any Encodable] = [:]
        var paramCounter = 0
        var usedVariables: Set<String> = []
        
        for (index, component) in query.components.enumerated() {
            if index > 0 {
                cypher += " "
            }
            
            switch component {
            case .match(let clause):
                let compiled = try compileMatch(clause, bindings: &bindings, counter: &paramCounter, usedVariables: &usedVariables)
                cypher += compiled
                
            case .create(let clause):
                let compiled = try compileCreate(clause, bindings: &bindings, counter: &paramCounter, usedVariables: &usedVariables)
                cypher += compiled
                
            case .merge(let clause):
                let compiled = try compileMerge(clause, bindings: &bindings, counter: &paramCounter, usedVariables: &usedVariables)
                cypher += compiled
                
            case .set(let clause):
                let compiled = try compileSet(clause, bindings: &bindings, counter: &paramCounter)
                cypher += compiled
                
            case .delete(let clause):
                let compiled = compileDelete(clause)
                cypher += compiled
                
            case .return(let clause):
                let compiled = compileReturn(clause)
                cypher += compiled
                
            case .where(let clause):
                let compiled = try compileWhere(clause, bindings: &bindings, counter: &paramCounter)
                cypher += compiled
                
            case .orderBy(let clause):
                let compiled = compileOrderBy(clause)
                cypher += compiled
                
            case .limit(let count):
                cypher += "LIMIT \(count)"
                
            case .skip(let count):
                cypher += "SKIP \(count)"
            }
        }
        
        return CompiledQuery(cypher: cypher, bindings: bindings)
    }
    
    // MARK: - Match Compilation
    
    private static func compileMatch(
        _ clause: MatchClause,
        bindings: inout [String: any Encodable],
        counter: inout Int,
        usedVariables: inout Set<String>
    ) throws -> String {
        usedVariables.insert(clause.variable)
        
        var cypher = "MATCH (\(clause.variable):\(clause.type._kuzuTableName)"
        
        // Add inline WHERE conditions if any
        if !clause.predicates.isEmpty {
            cypher += " {"
            let conditions = try clause.predicates.map { condition in
                try compileInlineCondition(condition, variable: clause.variable, bindings: &bindings, counter: &counter)
            }
            cypher += conditions.joined(separator: ", ")
            cypher += "}"
        }
        
        cypher += ")"
        
        return cypher
    }
    
    // MARK: - Create Compilation
    
    private static func compileCreate(
        _ clause: CreateClause,
        bindings: inout [String: any Encodable],
        counter: inout Int,
        usedVariables: inout Set<String>
    ) throws -> String {
        usedVariables.insert(clause.variable)
        
        var cypher = "CREATE (\(clause.variable):\(clause.type._kuzuTableName)"
        
        if !clause.properties.isEmpty {
            cypher += " {"
            let props = clause.properties.map { key, value in
                counter += 1
                let paramName = "p\(counter)"
                if let encodableValue = value as? any Encodable {
                    bindings[paramName] = encodableValue
                }
                return "\(key): $\(paramName)"
            }
            cypher += props.joined(separator: ", ")
            cypher += "}"
        }
        
        cypher += ")"
        
        return cypher
    }
    
    // MARK: - Merge Compilation
    
    private static func compileMerge(
        _ clause: MergeClause,
        bindings: inout [String: any Encodable],
        counter: inout Int,
        usedVariables: inout Set<String>
    ) throws -> String {
        usedVariables.insert(clause.variable)
        
        var cypher = "MERGE (\(clause.variable):\(clause.type._kuzuTableName)"
        
        // Match properties
        if !clause.matchProperties.isEmpty {
            cypher += " {"
            let props = clause.matchProperties.map { key, value in
                counter += 1
                let paramName = "p\(counter)"
                if let encodableValue = value as? any Encodable {
                    bindings[paramName] = encodableValue
                }
                return "\(key): $\(paramName)"
            }
            cypher += props.joined(separator: ", ")
            cypher += "}"
        }
        
        cypher += ")"
        
        // ON CREATE
        if !clause.onCreateProperties.isEmpty {
            cypher += " ON CREATE SET "
            let props = clause.onCreateProperties.map { key, value in
                counter += 1
                let paramName = "p\(counter)"
                if let encodableValue = value as? any Encodable {
                    bindings[paramName] = encodableValue
                }
                return "\(clause.variable).\(key) = $\(paramName)"
            }
            cypher += props.joined(separator: ", ")
        }
        
        // ON MATCH
        if !clause.onMatchProperties.isEmpty {
            cypher += " ON MATCH SET "
            let props = clause.onMatchProperties.map { key, value in
                counter += 1
                let paramName = "p\(counter)"
                if let encodableValue = value as? any Encodable {
                    bindings[paramName] = encodableValue
                }
                return "\(clause.variable).\(key) = $\(paramName)"
            }
            cypher += props.joined(separator: ", ")
        }
        
        return cypher
    }
    
    // MARK: - Set Compilation
    
    private static func compileSet(
        _ clause: SetClause,
        bindings: inout [String: any Encodable],
        counter: inout Int
    ) throws -> String {
        counter += 1
        let paramName = "p\(counter)"
        
        if let encodableValue = clause.value as? any Encodable {
            bindings[paramName] = encodableValue
        }
        
        return "SET \(clause.variable).\(clause.property) = $\(paramName)"
    }
    
    // MARK: - Delete Compilation
    
    private static func compileDelete(_ clause: DeleteClause) -> String {
        if clause.detach {
            return "DETACH DELETE \(clause.variable)"
        } else {
            return "DELETE \(clause.variable)"
        }
    }
    
    // MARK: - Return Compilation
    
    private static func compileReturn(_ clause: ReturnClause) -> String {
        let items = clause.items.map { item in
            switch item {
            case .variable(let name):
                return name
            case .property(let variable, let property):
                return "\(variable).\(property)"
            case .alias(let expression, let alias):
                return "\(expression) AS \(alias)"
            case .count(let variable):
                return "COUNT(\(variable))"
            case .all:
                return "*"
            }
        }
        
        return "RETURN \(items.joined(separator: ", "))"
    }
    
    // MARK: - Where Compilation
    
    private static func compileWhere(
        _ clause: WhereClause,
        bindings: inout [String: any Encodable],
        counter: inout Int
    ) throws -> String {
        guard !clause.conditions.isEmpty else {
            return ""
        }
        
        let conditions = try clause.conditions.map { condition in
            try compileCondition(condition, bindings: &bindings, counter: &counter)
        }
        
        return "WHERE \(conditions.joined(separator: " AND "))"
    }
    
    // MARK: - OrderBy Compilation
    
    private static func compileOrderBy(_ clause: OrderByClause) -> String {
        let items = clause.items.map { item in
            var expr = item.variable
            if let property = item.property {
                expr += ".\(property)"
            }
            
            switch item.direction {
            case .ascending:
                return "\(expr) ASC"
            case .descending:
                return "\(expr) DESC"
            }
        }
        
        return "ORDER BY \(items.joined(separator: ", "))"
    }
    
    // MARK: - Condition Compilation Helpers
    
    private static func compileInlineCondition(
        _ condition: WhereCondition,
        variable: String,
        bindings: inout [String: any Encodable],
        counter: inout Int
    ) throws -> String {
        // For inline conditions in MATCH patterns, we use property: value syntax
        let propertyName = extractPropertyName(from: condition.keyPath)
        
        // For now, we only support simple equality in inline conditions
        // This is a simplified implementation
        counter += 1
        let paramName = "p\(counter)"
        
        // Extract value from the predicate (simplified)
        if let value = extractSimpleValue(from: condition.predicate) {
            bindings[paramName] = value
            return "\(propertyName): $\(paramName)"
        }
        
        throw QueryError.compileFailure(
            message: "Only equality conditions are supported in MATCH patterns",
            location: "compileInlineCondition"
        )
    }
    
    private static func compileCondition(
        _ condition: WhereCondition,
        bindings: inout [String: any Encodable],
        counter: inout Int
    ) throws -> String {
        // This is a simplified implementation
        // In production, we'd handle all predicate types properly
        return "1 = 1" // Placeholder
    }
    
    private static func extractPropertyName(from keyPath: AnyKeyPath) -> String {
        // This is a simplified version - in production, we'd use proper reflection
        let pathString = String(describing: keyPath)
        return pathString.components(separatedBy: ".").last ?? "unknown"
    }
    
    private static func extractSimpleValue(from predicate: Any) -> (any Encodable)? {
        // This is a simplified implementation
        // In production, we'd properly extract values from different predicate types
        
        // For now, return nil to indicate we can't extract the value
        return nil
    }
}