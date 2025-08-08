import Foundation

/// Represents different types of subqueries in Cypher
public enum Subquery: QueryComponent {
    /// A scalar subquery that returns a single value
    case scalar(Query)
    
    /// A list subquery that returns a collection
    case list(Query)
    
    /// An EXISTS subquery for checking existence
    case exists(Query)
    
    /// A CALL subquery for executing procedures
    case call(procedure: String, parameters: [String: any Sendable], yields: [String]?)
    
    /// A CALL subquery with a query block
    case callBlock(Query, yields: [String]?)
    
    // MARK: - Cypher Compilation
    
    public func toCypher() throws -> CypherFragment {
        switch self {
        case .scalar(let query):
            let compiled = try CypherCompiler.compile(query)
            return CypherFragment(
                query: "(\(compiled.query))",
                parameters: compiled.parameters
            )
            
        case .list(let query):
            let compiled = try CypherCompiler.compile(query)
            return CypherFragment(
                query: "[(\(compiled.query))]",
                parameters: compiled.parameters
            )
            
        case .exists(let query):
            let compiled = try CypherCompiler.compile(query)
            return CypherFragment(
                query: "EXISTS { \(compiled.query) }",
                parameters: compiled.parameters
            )
            
        case .call(let procedure, let parameters, let yields):
            var paramString = ""
            if !parameters.isEmpty {
                let paramList = parameters.map { "\($0.key): $\($0.key)" }.joined(separator: ", ")
                paramString = "(\(paramList))"
            }
            
            var query = "CALL \(procedure)\(paramString)"
            
            if let yields = yields, !yields.isEmpty {
                query += " YIELD \(yields.joined(separator: ", "))"
            }
            
            return CypherFragment(query: query, parameters: parameters)
            
        case .callBlock(let query, let yields):
            let compiled = try CypherCompiler.compile(query)
            var cypherQuery = "CALL { \(compiled.query) }"
            
            if let yields = yields, !yields.isEmpty {
                cypherQuery += " YIELD \(yields.joined(separator: ", "))"
            }
            
            return CypherFragment(query: cypherQuery, parameters: compiled.parameters)
        }
    }
}

// MARK: - Builder Methods

public extension Subquery {
    /// Creates a scalar subquery
    static func scalar(@QueryBuilder _ builder: () -> [QueryComponent]) -> Subquery {
        .scalar(Query(components: builder()))
    }
    
    /// Creates a list subquery
    static func list(@QueryBuilder _ builder: () -> [QueryComponent]) -> Subquery {
        .list(Query(components: builder()))
    }
    
    /// Creates an exists subquery
    static func exists(@QueryBuilder _ builder: () -> [QueryComponent]) -> Subquery {
        .exists(Query(components: builder()))
    }
    
    /// Creates a CALL block subquery
    static func callBlock(yields: [String]? = nil, @QueryBuilder _ builder: () -> [QueryComponent]) -> Subquery {
        .callBlock(Query(components: builder()), yields: yields)
    }
    
    /// Creates a CALL block subquery with typed yields
    static func callBlock<T: _KuzuGraphModel>(
        yielding type: T.Type,
        as alias: String? = nil,
        @QueryBuilder _ builder: () -> [QueryComponent]
    ) -> Subquery {
        let yieldAlias = alias ?? String(describing: type).lowercased()
        return .callBlock(Query(components: builder()), yields: [yieldAlias])
    }
}

// MARK: - LET Clause for Variable Assignment

/// Represents a LET clause for assigning subquery results to variables
public struct Let: QueryComponent {
    let variable: String
    let expression: LetExpression
    
    /// Types of expressions that can be assigned
    public enum LetExpression {
        case subquery(Subquery)
        case property(PropertyReference)
        case value(any Sendable)
        case aggregation(Aggregation)
        case custom(String, parameters: [String: any Sendable])
    }
    
    private init(variable: String, expression: LetExpression) {
        self.variable = variable
        self.expression = expression
    }
    
    // MARK: - Factory Methods
    
    /// Creates a LET clause with a scalar subquery
    public static func scalar(_ variable: String, @QueryBuilder _ builder: () -> [QueryComponent]) -> Let {
        Let(variable: variable, expression: .subquery(.scalar(Query(components: builder()))))
    }
    
    /// Creates a LET clause with a list subquery
    public static func list(_ variable: String, @QueryBuilder _ builder: () -> [QueryComponent]) -> Let {
        Let(variable: variable, expression: .subquery(.list(Query(components: builder()))))
    }
    
    /// Creates a LET clause with a property reference
    public static func property(_ variable: String, _ reference: PropertyReference) -> Let {
        Let(variable: variable, expression: .property(reference))
    }
    
    /// Creates a LET clause with a value
    public static func value(_ variable: String, _ value: any Sendable) -> Let {
        Let(variable: variable, expression: .value(value))
    }
    
    /// Creates a LET clause with an aggregation
    public static func aggregate(_ variable: String, _ aggregation: Aggregation) -> Let {
        Let(variable: variable, expression: .aggregation(aggregation))
    }
    
    /// Creates a LET clause with a custom expression
    public static func custom(_ variable: String, expression: String, parameters: [String: any Sendable] = [:]) -> Let {
        Let(variable: variable, expression: .custom(expression, parameters: parameters))
    }
    
    // MARK: - Cypher Compilation
    
    public func toCypher() throws -> CypherFragment {
        let expressionCypher: CypherFragment
        
        switch expression {
        case .subquery(let subquery):
            expressionCypher = try subquery.toCypher()
            
        case .property(let ref):
            expressionCypher = CypherFragment(query: ref.cypher)
            
        case .value(let value):
            let paramName = ParameterNameGenerator.generateUUID()
            expressionCypher = CypherFragment(
                query: "$\(paramName)",
                parameters: [paramName: value]
            )
            
        case .aggregation(let agg):
            expressionCypher = CypherFragment(query: agg.toCypher())
            
        case .custom(let expr, let params):
            expressionCypher = CypherFragment(query: expr, parameters: params)
        }
        
        return CypherFragment(
            query: "LET \(variable) = \(expressionCypher.query)",
            parameters: expressionCypher.parameters
        )
    }
}

// MARK: - Reference to Variables

/// Represents a reference to a variable created by LET
public struct Ref: QueryComponent, Sendable {
    let variable: String
    
    public init(_ variable: String) {
        self.variable = variable
    }
    
    public func toCypher() throws -> CypherFragment {
        CypherFragment(query: variable)
    }
}

// MARK: - Predicate Extensions for Subqueries

public extension Predicate {
    /// Creates a predicate with an EXISTS subquery
    static func exists(@QueryBuilder _ builder: () -> [QueryComponent]) -> Predicate {
        do {
            let query = Query(components: builder())
            let subquery = Subquery.exists(query)
            let cypher = try subquery.toCypher()
            return Predicate(node: .custom(cypher.query, parameters: cypher.parameters))
        } catch {
            return Predicate(node: .literal(false))
        }
    }
    
    /// Creates a predicate with a NOT EXISTS subquery
    static func notExists(@QueryBuilder _ builder: () -> [QueryComponent]) -> Predicate {
        do {
            let query = Query(components: builder())
            let subquery = Subquery.exists(query)
            let cypher = try subquery.toCypher()
            return Predicate(node: .custom("NOT \(cypher.query)", parameters: cypher.parameters))
        } catch {
            return Predicate(node: .literal(false))
        }
    }
}

// MARK: - Return Extensions for Subqueries

public extension Return {
    /// Returns a scalar subquery result
    static func scalar(as alias: String, @QueryBuilder _ builder: () -> [QueryComponent]) -> Return {
        do {
            let query = Query(components: builder())
            let subquery = Subquery.scalar(query)
            let cypher = try subquery.toCypher()
            return Return.items(.aliased(expression: cypher.query, alias: alias))
        } catch {
            return Return.items(.aliased(expression: "null", alias: alias))
        }
    }
    
    /// Returns a list subquery result
    static func list(as alias: String, @QueryBuilder _ builder: () -> [QueryComponent]) -> Return {
        do {
            let query = Query(components: builder())
            let subquery = Subquery.list(query)
            let cypher = try subquery.toCypher()
            return Return.items(.aliased(expression: cypher.query, alias: alias))
        } catch {
            return Return.items(.aliased(expression: "[]", alias: alias))
        }
    }
}

// MARK: - WITH Extensions for Subqueries

public extension With {
    /// Creates a WITH clause including a scalar subquery
    static func scalar(_ variable: String, @QueryBuilder _ builder: () -> [QueryComponent]) -> With {
        do {
            let query = Query(components: builder())
            let subquery = Subquery.scalar(query)
            let cypher = try subquery.toCypher()
            return With.items(.aliased(expression: cypher.query, alias: variable))
        } catch {
            return With.items(.aliased(expression: "null", alias: variable))
        }
    }
    
    /// Creates a WITH clause including a list subquery
    static func list(_ variable: String, @QueryBuilder _ builder: () -> [QueryComponent]) -> With {
        do {
            let query = Query(components: builder())
            let subquery = Subquery.list(query)
            let cypher = try subquery.toCypher()
            return With.items(.aliased(expression: cypher.query, alias: variable))
        } catch {
            return With.items(.aliased(expression: "[]", alias: variable))
        }
    }
}