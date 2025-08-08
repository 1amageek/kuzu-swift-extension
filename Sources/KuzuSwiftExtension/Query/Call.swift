import Foundation

/// Represents a CALL clause for stored procedures and algorithms
public struct Call: QueryComponent {
    let procedure: String
    let parameters: [String: any Sendable]
    let yields: [String]?
    let `where`: Predicate?
    
    private init(
        procedure: String,
        parameters: [String: any Sendable],
        yields: [String]?,
        `where`: Predicate? = nil
    ) {
        self.procedure = procedure
        self.parameters = parameters
        self.yields = yields
        self.`where` = `where`
    }
    
    // MARK: - Factory Methods
    
    /// Calls a stored procedure
    public static func procedure(
        _ name: String,
        parameters: [String: any Sendable] = [:],
        yields: [String]? = nil
    ) -> Call {
        Call(procedure: name, parameters: parameters, yields: yields)
    }
    
    /// Calls a procedure with typed yields
    public static func procedure<T: _KuzuGraphModel>(
        _ name: String,
        parameters: [String: any Sendable] = [:],
        yielding type: T.Type,
        as alias: String? = nil
    ) -> Call {
        let yieldAlias = alias ?? String(describing: type).lowercased()
        return Call(procedure: name, parameters: parameters, yields: [yieldAlias])
    }
    
    // MARK: - Modifiers
    
    /// Adds a WHERE clause to filter the CALL results
    public func `where`(_ predicate: Predicate) -> Call {
        Call(
            procedure: procedure,
            parameters: parameters,
            yields: yields,
            where: predicate
        )
    }
    
    /// Adds YIELD clauses
    public func yields(_ items: String...) -> Call {
        Call(
            procedure: procedure,
            parameters: parameters,
            yields: items,
            where: `where`
        )
    }
    
    // MARK: - Cypher Compilation
    
    public func toCypher() throws -> CypherFragment {
        var query = "CALL \(procedure)"
        
        // Add parameters
        if !parameters.isEmpty {
            let paramList = parameters.map { "\($0.key): $\($0.key)" }.joined(separator: ", ")
            query += "(\(paramList))"
        } else {
            query += "()"
        }
        
        // Add YIELD clause
        if let yields = yields, !yields.isEmpty {
            query += " YIELD \(yields.joined(separator: ", "))"
        }
        
        // Add WHERE clause
        var allParameters = parameters
        if let whereClause = `where` {
            let whereCypher = try whereClause.toCypher()
            query += " WHERE \(whereCypher.query)"
            allParameters.merge(whereCypher.parameters) { _, new in new }
        }
        
        return CypherFragment(query: query, parameters: allParameters)
    }
}

// MARK: - Common Procedures

public extension Call {
    /// Database schema procedures
    struct Schema {
        /// Shows all node tables
        public static func nodeTableNames() -> Call {
            Call.procedure("db.schema.nodeTableNames", yields: ["name"])
        }
        
        /// Shows all relationship tables
        public static func relTableNames() -> Call {
            Call.procedure("db.schema.relTableNames", yields: ["name"])
        }
        
        /// Shows columns for a table
        public static func tableColumns(tableName: String) -> Call {
            Call.procedure(
                "db.schema.tableColumns",
                parameters: ["tableName": tableName],
                yields: ["columnName", "dataType"]
            )
        }
    }
    
    /// Database statistics procedures
    struct Stats {
        /// Shows database statistics
        public static func database() -> Call {
            Call.procedure("db.stats.database", yields: ["nodeCount", "relCount"])
        }
        
        /// Shows table statistics
        public static func table(name: String) -> Call {
            Call.procedure(
                "db.stats.table",
                parameters: ["tableName": name],
                yields: ["numTuples", "numPages"]
            )
        }
    }
    
    /// Transaction management procedures
    struct Transaction {
        /// Begins a transaction
        public static func begin() -> Call {
            Call.procedure("db.transaction.begin")
        }
        
        /// Commits a transaction
        public static func commit() -> Call {
            Call.procedure("db.transaction.commit")
        }
        
        /// Rolls back a transaction
        public static func rollback() -> Call {
            Call.procedure("db.transaction.rollback")
        }
    }
}