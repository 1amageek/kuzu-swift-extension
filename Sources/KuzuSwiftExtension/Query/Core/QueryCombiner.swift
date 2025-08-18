import Foundation

/// Combines multiple query fragments into a single coherent Cypher query
public final class QueryCombiner {
    private var structure = QueryStructure()
    private var parameters: [String: any Sendable] = [:]
    private var aliasMapping: [String: String] = [:]  // Maps component aliases to unique aliases
    private var parameterCounter = 0  // For generating unique parameter names
    
    public init() {}
    
    // MARK: - Public API
    
    /// Adds a query fragment to the combiner
    public func add(_ fragment: CypherFragment) throws {
        // Use structured information if available
        if let fragmentStructure = fragment.structure {
            try mergeStructure(fragmentStructure)
        } else {
            // Fallback: parse the query string
            try parseAndAdd(fragment.query)
        }
        
        // Merge parameters with conflict detection
        try mergeParameters(fragment.parameters)
    }
    
    /// Builds the final combined query
    public func build() throws -> CypherFragment {
        // Validate the combined structure
        try structure.validate()
        
        // Generate the Cypher query string
        let query = try generateCypher()
        
        return CypherFragment(
            query: query,
            parameters: parameters,
            structure: structure
        )
    }
    
    // MARK: - Structure Merging
    
    private func mergeStructure(_ other: QueryStructure) throws {
        for orderedClause in other.clauses {
            // Handle different clause types appropriately
            switch orderedClause.clause {
            case .match(let match):
                try mergeMatchClause(match, scope: orderedClause.scope)
            case .where(let whereClause):
                try mergeWhereClause(whereClause, scope: orderedClause.scope)
            case .return(let returnClause):
                try mergeReturnClause(returnClause, scope: orderedClause.scope)
            default:
                // Add other clauses directly
                structure.addClause(orderedClause.clause, scope: orderedClause.scope)
            }
        }
    }
    
    private func mergeMatchClause(_ match: MatchClause, scope: QueryStructure.QueryScope) throws {
        // Check if we already have MATCH clauses
        let existingMatches = structure.clauses.compactMap { orderedClause -> MatchClause? in
            if case .match(let existing) = orderedClause.clause {
                return existing
            }
            return nil
        }
        
        if !existingMatches.isEmpty {
            // Combine with existing MATCH clause (comma-separated patterns)
            var combinedPatterns = existingMatches.first?.patterns ?? []
            
            // Add new patterns, avoiding duplicates
            for pattern in match.patterns {
                if !combinedPatterns.contains(where: { $0.alias == pattern.alias }) {
                    combinedPatterns.append(pattern)
                }
            }
            
            // Replace the first MATCH clause with combined version
            if let firstMatchIndex = structure.firstIndex(where: { 
                if case .match = $0.clause { return true }
                return false
            }) {
                structure.replaceClause(
                    at: firstMatchIndex,
                    with: .match(MatchClause(patterns: combinedPatterns)),
                    scope: scope
                )
            }
        } else {
            // Add as new MATCH clause
            structure.addClause(.match(match), scope: scope)
        }
    }
    
    private func mergeWhereClause(_ whereClause: WhereClause, scope: QueryStructure.QueryScope) throws {
        // Check if we already have WHERE clauses
        let existingWheres = structure.clauses.compactMap { orderedClause -> WhereClause? in
            if case .where(let existing) = orderedClause.clause {
                return existing
            }
            return nil
        }
        
        if !existingWheres.isEmpty {
            // Combine with AND
            let combinedCondition = existingWheres.map { $0.condition } + [whereClause.condition]
            let combinedAliases = existingWheres.flatMap { $0.referencedAliases } + whereClause.referencedAliases
            var combinedParameters = existingWheres.reduce(into: [:]) { result, clause in
                result.merge(clause.parameters) { _, new in new }
            }
            combinedParameters.merge(whereClause.parameters) { _, new in new }
            
            let combined = WhereClause(
                condition: "(" + combinedCondition.joined(separator: ") AND (") + ")",
                referencedAliases: Array(Set(combinedAliases)),
                parameters: combinedParameters
            )
            
            // Replace the first WHERE clause
            if let firstWhereIndex = structure.firstIndex(where: {
                if case .where = $0.clause { return true }
                return false
            }) {
                structure.replaceClause(
                    at: firstWhereIndex,
                    with: .where(combined),
                    scope: scope
                )
            }
        } else {
            // Add as new WHERE clause
            structure.addClause(.where(whereClause), scope: scope)
        }
    }
    
    private func mergeReturnClause(_ returnClause: ReturnClause, scope: QueryStructure.QueryScope) throws {
        // Check if we already have RETURN clauses
        let existingReturns = structure.clauses.compactMap { orderedClause -> ReturnClause? in
            if case .return(let existing) = orderedClause.clause {
                return existing
            }
            return nil
        }
        
        if !existingReturns.isEmpty {
            // Combine return items
            var combinedItems = existingReturns.first?.items ?? []
            
            // Add new items, avoiding duplicates
            for item in returnClause.items {
                if !combinedItems.contains(where: { $0.expression == item.expression }) {
                    combinedItems.append(item)
                }
            }
            
            let combined = ReturnClause(
                items: combinedItems,
                distinct: existingReturns.first?.distinct ?? returnClause.distinct
            )
            
            // Replace the first RETURN clause
            if let firstReturnIndex = structure.firstIndex(where: {
                if case .return = $0.clause { return true }
                return false
            }) {
                structure.replaceClause(
                    at: firstReturnIndex,
                    with: .return(combined),
                    scope: scope
                )
            }
        } else {
            // Add as new RETURN clause
            structure.addClause(.return(returnClause), scope: scope)
        }
    }
    
    // MARK: - Parameter Merging
    
    private func mergeParameters(_ newParams: [String: any Sendable]) throws {
        for (key, value) in newParams {
            if let existingValue = parameters[key] {
                // Check if values are equal
                if !areValuesEqual(existingValue, value) {
                    throw KuzuError.parameterConversionFailed(
                        parameter: key,
                        valueType: String(describing: type(of: value)),
                        reason: "Parameter '\(key)' has conflicting values"
                    )
                }
            } else {
                parameters[key] = value
            }
        }
    }
    
    private func areValuesEqual(_ lhs: any Sendable, _ rhs: any Sendable) -> Bool {
        // Try to compare as AnyHashable
        if let lhsHashable = lhs as? AnyHashable,
           let rhsHashable = rhs as? AnyHashable {
            return lhsHashable == rhsHashable
        }
        
        // Fallback to string comparison
        return String(describing: lhs) == String(describing: rhs)
    }
    
    // MARK: - Cypher Generation
    
    private func generateCypher() throws -> String {
        var parts: [String] = []
        var currentScope: QueryStructure.QueryScope = .main
        
        for orderedClause in structure.clauses {
            // Handle scope changes
            if !isSameScope(orderedClause.scope, currentScope) {
                // Handle scope transition (e.g., entering subquery)
                parts.append(handleScopeTransition(from: currentScope, to: orderedClause.scope))
                currentScope = orderedClause.scope
            }
            
            // Generate clause string
            let clauseString = try generateClauseString(orderedClause.clause)
            if !clauseString.isEmpty {
                parts.append(clauseString)
            }
        }
        
        return parts.joined(separator: " ")
    }
    
    private func isSameScope(_ lhs: QueryStructure.QueryScope, _ rhs: QueryStructure.QueryScope) -> Bool {
        switch (lhs, rhs) {
        case (.main, .main):
            return true
        case (.subquery(let id1), .subquery(let id2)):
            return id1 == id2
        case (.union(let branch1), .union(let branch2)):
            return branch1 == branch2
        default:
            return false
        }
    }
    
    private func handleScopeTransition(from: QueryStructure.QueryScope, to: QueryStructure.QueryScope) -> String {
        switch (from, to) {
        case (.main, .subquery):
            return "CALL {"
        case (.subquery, .main):
            return "}"
        case (.main, .union(let branch)) where branch > 0:
            return "UNION"
        default:
            return ""
        }
    }
    
    private func generateClauseString(_ clause: CypherClause) throws -> String {
        switch clause {
        case .match(let match):
            let patterns = match.patterns.map { pattern in
                generatePatternString(pattern)
            }.joined(separator: ", ")
            return (match.isOptional ? "OPTIONAL MATCH " : "MATCH ") + patterns
            
        case .where(let whereClause):
            return "WHERE " + whereClause.condition
            
        case .create(let create):
            let patterns = create.patterns.map { pattern in
                generatePatternString(pattern)
            }.joined(separator: ", ")
            return "CREATE " + patterns
            
        case .merge(let merge):
            var result = "MERGE " + generatePatternString(merge.pattern)
            if let onCreate = merge.onCreate, !onCreate.isEmpty {
                let sets = onCreate.map { "\($0.alias).\($0.property) = $\(parameterName(for: $0.value))" }
                result += " ON CREATE SET " + sets.joined(separator: ", ")
            }
            if let onMatch = merge.onMatch, !onMatch.isEmpty {
                let sets = onMatch.map { "\($0.alias).\($0.property) = $\(parameterName(for: $0.value))" }
                result += " ON MATCH SET " + sets.joined(separator: ", ")
            }
            return result
            
        case .delete(let delete):
            return "DELETE " + delete.aliases.joined(separator: ", ")
            
        case .detachDelete(let delete):
            return "DETACH DELETE " + delete.aliases.joined(separator: ", ")
            
        case .set(let setClause):
            return "SET \(setClause.alias).\(setClause.property) = $\(parameterName(for: setClause.value))"
            
        case .remove(let remove):
            return "REMOVE \(remove.alias).\(remove.property)"
            
        case .return(let returnClause):
            let items = returnClause.items.map { item in
                if let alias = item.alias {
                    return "\(item.expression) AS \(alias)"
                } else {
                    return item.expression
                }
            }.joined(separator: ", ")
            return (returnClause.distinct ? "RETURN DISTINCT " : "RETURN ") + items
            
        case .with(let withClause):
            var result = "WITH " + withClause.items.joined(separator: ", ")
            if let whereCondition = withClause.whereCondition {
                result += " WHERE " + whereCondition.condition
            }
            return result
            
        case .orderBy(let orderBy):
            let items = orderBy.items.map { item in
                let direction = item.direction == .descending ? " DESC" : ""
                return item.expression + direction
            }.joined(separator: ", ")
            return "ORDER BY " + items
            
        case .skip(let skip):
            return "SKIP \(skip.count)"
            
        case .limit(let limit):
            return "LIMIT \(limit.count)"
            
        case .unwind(let unwind):
            return "UNWIND \(unwind.list) AS \(unwind.alias)"
            
        case .call(let call):
            var result = "CALL \(call.procedure)"
            if !call.arguments.isEmpty {
                let args = call.arguments.map { String(describing: $0) }.joined(separator: ", ")
                result += "(\(args))"
            }
            if let yields = call.yields, !yields.isEmpty {
                result += " YIELD " + yields.joined(separator: ", ")
            }
            return result
            
        case .union(let union):
            return union.all ? "UNION ALL" : "UNION"
            
        case .foreach(let foreach):
            let updates = foreach.updates.compactMap { update in
                try? generateClauseString(update)
            }.joined(separator: " ")
            return "FOREACH (\(foreach.variable) IN \(foreach.list) | \(updates))"
            
        default:
            return ""
        }
    }
    
    private func generatePatternString(_ pattern: MatchClause.PatternElement) -> String {
        var result = "(\(pattern.alias)"
        
        if let label = pattern.label {
            result += ":\(label)"
        }
        
        if let properties = pattern.properties, !properties.isEmpty {
            let props = properties.map { key, value in
                "\(key): $\(parameterName(for: value))"
            }.joined(separator: ", ")
            result += " {\(props)}"
        }
        
        result += ")"
        return result
    }
    
    private func parameterName(for value: any Sendable) -> String {
        // Generate unique parameter name
        parameterCounter += 1
        let name = "p\(parameterCounter)"
        parameters[name] = value
        return name
    }
    
    // MARK: - Fallback Parsing
    
    private func parseAndAdd(_ query: String) throws {
        // This is a simplified fallback parser
        // In production, this would need more robust parsing
        
        if query.contains("MATCH") {
            // Extract MATCH pattern
            if let matchRange = query.range(of: "MATCH") {
                let afterMatch = String(query[matchRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                
                // Simple pattern extraction (this is very basic)
                if let whereRange = afterMatch.range(of: "WHERE") {
                    let pattern = String(afterMatch[..<whereRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    
                    // Create a basic pattern element
                    let alias = extractAlias(from: pattern)
                    let label = extractLabel(from: pattern)
                    
                    let match = MatchClause(patterns: [
                        MatchClause.PatternElement(alias: alias, label: label)
                    ])
                    structure.addClause(.match(match))
                    
                    // Parse WHERE clause
                    let whereCondition = String(afterMatch[whereRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !whereCondition.isEmpty {
                        let whereClause = WhereClause(
                            condition: whereCondition,
                            referencedAliases: [alias]
                        )
                        structure.addClause(.where(whereClause))
                    }
                } else {
                    // No WHERE clause
                    let alias = extractAlias(from: afterMatch)
                    let label = extractLabel(from: afterMatch)
                    
                    let match = MatchClause(patterns: [
                        MatchClause.PatternElement(alias: alias, label: label)
                    ])
                    structure.addClause(.match(match))
                }
            }
        }
        
        if query.contains("RETURN") {
            // Extract RETURN items
            if let returnRange = query.range(of: "RETURN") {
                let afterReturn = String(query[returnRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                let items = afterReturn.split(separator: ",").map { item in
                    ReturnClause.ReturnItem(expression: String(item).trimmingCharacters(in: .whitespaces))
                }
                structure.addClause(.return(ReturnClause(items: items)))
            }
        }
    }
    
    private func extractAlias(from pattern: String) -> String {
        // Extract alias from pattern like "(n:Label)"
        if let start = pattern.firstIndex(of: "("),
           let colonIndex = pattern.firstIndex(of: ":") ?? pattern.firstIndex(of: ")") {
            let aliasRange = pattern.index(after: start)..<colonIndex
            return String(pattern[aliasRange]).trimmingCharacters(in: .whitespaces)
        }
        return "n"  // Default alias
    }
    
    private func extractLabel(from pattern: String) -> String? {
        // Extract label from pattern like "(n:Label)"
        if let colonIndex = pattern.firstIndex(of: ":"),
           let endIndex = pattern.firstIndex(of: ")") {
            let labelRange = pattern.index(after: colonIndex)..<endIndex
            let label = String(pattern[labelRange]).trimmingCharacters(in: .whitespaces)
            return label.isEmpty ? nil : label
        }
        return nil
    }
}