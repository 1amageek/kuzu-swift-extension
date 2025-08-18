import Foundation

/// Represents the structure of a Cypher query with all its components
public struct QueryStructure: Sendable {
    // Ordered list of clauses maintaining Cypher's sequential semantics
    private(set) var clauses: [OrderedClause] = []
    
    /// A clause with its order and scope information
    public struct OrderedClause: Sendable {
        let order: Int
        let clause: CypherClause
        let scope: QueryScope
    }
    
    /// Query scope for managing subqueries and unions
    public enum QueryScope: Sendable {
        case main
        case subquery(id: String)
        case union(branch: Int)
        case foreach(id: String)
        case with(id: String)
    }
    
    // MARK: - Mutation
    
    mutating func addClause(_ clause: CypherClause, scope: QueryScope = .main) {
        let order = clauses.count
        clauses.append(OrderedClause(order: order, clause: clause, scope: scope))
    }
    
    mutating func replaceClause(at index: Int, with clause: CypherClause, scope: QueryScope) {
        guard index < clauses.count else { return }
        clauses[index] = OrderedClause(order: index, clause: clause, scope: scope)
    }
    
    func firstIndex(where predicate: (OrderedClause) -> Bool) -> Int? {
        clauses.firstIndex(where: predicate)
    }
    
    // MARK: - Validation
    
    /// Validates the query structure for correctness
    public func validate() throws {
        try validateClauseOrder()
        try validateRequiredClauses()
        try validateAliasConsistency()
    }
    
    private func validateClauseOrder() throws {
        var previousCategory: CypherClause.ClauseCategory?
        
        for orderedClause in clauses {
            let currentCategory = orderedClause.clause.category
            
            if let prev = previousCategory {
                // Validate transitions between clause categories
                switch (prev, currentCategory) {
                case (.result, .read), (.result, .write):
                    throw KuzuError.compilationFailed(
                        query: "",
                        reason: "Cannot have \(currentCategory) clause after \(prev) clause"
                    )
                case (.write, .read) where !isWithClause(orderedClause.clause):
                    throw KuzuError.compilationFailed(
                        query: "",
                        reason: "Read clause must be separated by WITH after write clause"
                    )
                default:
                    break
                }
            }
            
            previousCategory = currentCategory
        }
    }
    
    private func validateRequiredClauses() throws {
        let hasReadOrWrite = clauses.contains { clause in
            clause.clause.category == .read || clause.clause.category == .write
        }
        
        if !hasReadOrWrite && !clauses.isEmpty {
            throw KuzuError.compilationFailed(
                query: "",
                reason: "Query must have at least one MATCH, CREATE, or MERGE clause"
            )
        }
    }
    
    private func validateAliasConsistency() throws {
        var definedAliases = Set<String>()
        var usedAliases = Set<String>()
        
        for orderedClause in clauses {
            // Collect defined and used aliases
            let (defined, used) = extractAliases(from: orderedClause.clause)
            definedAliases.formUnion(defined)
            usedAliases.formUnion(used)
        }
        
        // Check for undefined aliases
        let undefinedAliases = usedAliases.subtracting(definedAliases)
        if !undefinedAliases.isEmpty {
            throw KuzuError.compilationFailed(
                query: "",
                reason: "Undefined aliases: \(undefinedAliases.joined(separator: ", "))"
            )
        }
    }
    
    private func isWithClause(_ clause: CypherClause) -> Bool {
        if case .with = clause {
            return true
        }
        return false
    }
    
    private func extractAliases(from clause: CypherClause) -> (defined: Set<String>, used: Set<String>) {
        switch clause {
        case .match(let match), .optionalMatch(let match):
            return (defined: Set(match.patterns.map { $0.alias }), used: [])
        case .where(let whereClause):
            return (defined: [], used: Set(whereClause.referencedAliases))
        case .create(let create):
            return (defined: Set(create.patterns.map { $0.alias }), used: [])
        case .merge(let merge):
            return (defined: Set([merge.pattern.alias]), used: merge.referencedAliases)
        case .delete(let delete), .detachDelete(let delete):
            return (defined: [], used: Set(delete.aliases))
        case .set(let setClause):
            return (defined: [], used: Set([setClause.alias]))
        case .return(let returnClause):
            return (defined: [], used: Set(returnClause.items.compactMap { $0.sourceAlias }))
        default:
            return (defined: [], used: [])
        }
    }
}

/// Represents all possible Cypher clauses
public enum CypherClause: Sendable {
    // Read operations
    case match(MatchClause)
    case optionalMatch(MatchClause)
    case `where`(WhereClause)
    case with(WithClause)
    case unwind(UnwindClause)
    case call(CallClause)
    
    // Write operations
    case create(CreateClause)
    case merge(MergeClause)
    case delete(DeleteClause)
    case detachDelete(DeleteClause)
    case set(SetClause)
    case remove(RemoveClause)
    
    // Result operations
    case `return`(ReturnClause)
    case orderBy(OrderByClause)
    case skip(SkipClause)
    case limit(LimitClause)
    case union(UnionClause)
    
    // Control flow
    case foreach(ForeachClause)
    
    /// The category of this clause
    public var category: ClauseCategory {
        switch self {
        case .match, .optionalMatch, .where, .with, .unwind, .call:
            return .read
        case .create, .merge, .delete, .detachDelete, .set, .remove:
            return .write
        case .return, .orderBy, .skip, .limit, .union:
            return .result
        case .foreach:
            return .control
        }
    }
    
    public enum ClauseCategory: Sendable {
        case read, write, result, control
    }
}

// MARK: - Clause Definitions

public struct MatchClause: Sendable {
    public let patterns: [PatternElement]
    public let isOptional: Bool
    
    public init(patterns: [PatternElement], isOptional: Bool = false) {
        self.patterns = patterns
        self.isOptional = isOptional
    }
    
    public struct PatternElement: Sendable {
        public let alias: String
        public let label: String?
        public let properties: [String: any Sendable]?
        
        public init(alias: String, label: String? = nil, properties: [String: any Sendable]? = nil) {
            self.alias = alias
            self.label = label
            self.properties = properties
        }
    }
}

public struct WhereClause: Sendable {
    public let condition: String
    public let referencedAliases: [String]
    public let parameters: [String: any Sendable]
    
    public init(condition: String, referencedAliases: [String], parameters: [String: any Sendable] = [:]) {
        self.condition = condition
        self.referencedAliases = referencedAliases
        self.parameters = parameters
    }
}

public struct CreateClause: Sendable {
    public let patterns: [MatchClause.PatternElement]
    
    public init(patterns: [MatchClause.PatternElement]) {
        self.patterns = patterns
    }
}

public struct MergeClause: Sendable {
    public let pattern: MatchClause.PatternElement
    public let onCreate: [SetClause]?
    public let onMatch: [SetClause]?
    public let referencedAliases: Set<String>
    
    public init(
        pattern: MatchClause.PatternElement,
        onCreate: [SetClause]? = nil,
        onMatch: [SetClause]? = nil,
        referencedAliases: Set<String> = []
    ) {
        self.pattern = pattern
        self.onCreate = onCreate
        self.onMatch = onMatch
        self.referencedAliases = referencedAliases
    }
}

public struct DeleteClause: Sendable {
    public let aliases: [String]
    public let detach: Bool
    
    public init(aliases: [String], detach: Bool = false) {
        self.aliases = aliases
        self.detach = detach
    }
}

public struct SetClause: Sendable {
    public let alias: String
    public let property: String
    public let value: any Sendable
    
    public init(alias: String, property: String, value: any Sendable) {
        self.alias = alias
        self.property = property
        self.value = value
    }
}

public struct RemoveClause: Sendable {
    public let alias: String
    public let property: String
    
    public init(alias: String, property: String) {
        self.alias = alias
        self.property = property
    }
}

public struct ReturnClause: Sendable {
    public let items: [ReturnItem]
    public let distinct: Bool
    
    public init(items: [ReturnItem], distinct: Bool = false) {
        self.items = items
        self.distinct = distinct
    }
    
    public struct ReturnItem: Sendable {
        public let expression: String
        public let alias: String?
        public let sourceAlias: String?  // The alias referenced in the expression
        
        public init(expression: String, alias: String? = nil, sourceAlias: String? = nil) {
            self.expression = expression
            self.alias = alias
            self.sourceAlias = sourceAlias
        }
    }
}

public struct WithClause: Sendable {
    public let items: [String]
    public let whereCondition: WhereClause?
    
    public init(items: [String], whereCondition: WhereClause? = nil) {
        self.items = items
        self.whereCondition = whereCondition
    }
}

public struct OrderByClause: Sendable {
    public let items: [OrderByItem]
    
    public init(items: [OrderByItem]) {
        self.items = items
    }
    
    public struct OrderByItem: Sendable {
        public let expression: String
        public let direction: Direction
        
        public enum Direction: Sendable {
            case ascending, descending
        }
        
        public init(expression: String, direction: Direction = .ascending) {
            self.expression = expression
            self.direction = direction
        }
    }
}

public struct SkipClause: Sendable {
    public let count: Int
    
    public init(count: Int) {
        self.count = count
    }
}

public struct LimitClause: Sendable {
    public let count: Int
    
    public init(count: Int) {
        self.count = count
    }
}

public struct UnwindClause: Sendable {
    public let list: String
    public let alias: String
    
    public init(list: String, alias: String) {
        self.list = list
        self.alias = alias
    }
}

public struct CallClause: Sendable {
    public let procedure: String
    public let arguments: [any Sendable]
    public let yields: [String]?
    
    public init(procedure: String, arguments: [any Sendable] = [], yields: [String]? = nil) {
        self.procedure = procedure
        self.arguments = arguments
        self.yields = yields
    }
}

public struct UnionClause: Sendable {
    public let all: Bool
    
    public init(all: Bool = false) {
        self.all = all
    }
}

public struct ForeachClause: Sendable {
    public let variable: String
    public let list: String
    public let updates: [CypherClause]
    
    public init(variable: String, list: String, updates: [CypherClause]) {
        self.variable = variable
        self.list = list
        self.updates = updates
    }
}