import Foundation
import Kuzu

public struct MigrationManager {
    private let context: GraphContext
    private let policy: MigrationPolicy
    
    public init(context: GraphContext, policy: MigrationPolicy) {
        self.context = context
        self.policy = policy
    }
    
    public func migrate(to schema: GraphSchema) async throws {
        let currentSchema = try await getCurrentSchema()
        let diff = SchemaDiff.compare(current: currentSchema, target: schema)
        
        try validateMigration(diff: diff)
        
        try await applyMigration(diff: diff)
    }
    
    public func migrate(types: [any _KuzuGraphModel.Type]) async throws {
        let schema = GraphSchema.discover(from: types)
        try await migrate(to: schema)
    }
    
    private func getCurrentSchema() async throws -> GraphSchema {
        var nodes: [NodeSchema] = []
        var edges: [EdgeSchema] = []
        
        // Use modern Kuzu API (>= 0.10)
        // First, get all tables using SHOW TABLES
        let showTablesQuery = "SHOW TABLES"
        
        do {
            let tablesResult = try await context.raw(showTablesQuery, bindings: [:])
            let tables = try tablesResult.mapRows()
            
            for tableRow in tables {
                guard let tableName = tableRow["name"] as? String else { continue }
                
                // Get detailed schema for each table using DESCRIBE
                let describeQuery = "DESCRIBE \(tableName)"
                let schemaResult = try await context.raw(describeQuery, bindings: [:])
                let schemaRows = try schemaResult.mapRows()
                
                // Parse the schema information
                let tableInfo = try parseTableSchema(
                    tableName: tableName,
                    tableRow: tableRow,
                    schemaRows: schemaRows
                )
                
                switch tableInfo.tableType {
                case .node:
                    nodes.append(NodeSchema(
                        name: tableName,
                        columns: tableInfo.columns.map { Column(name: $0.name, type: $0.type, constraints: $0.constraints) },
                        ddl: tableInfo.ddl
                    ))
                case .edge:
                    edges.append(EdgeSchema(
                        name: tableName,
                        from: tableInfo.fromType ?? "",
                        to: tableInfo.toType ?? "",
                        columns: tableInfo.columns.map { Column(name: $0.name, type: $0.type, constraints: $0.constraints) },
                        ddl: tableInfo.ddl
                    ))
                }
            }
        } catch {
            // If SHOW TABLES fails, it might be an older version or empty database
            // Return empty schema
            return GraphSchema(nodes: nodes, edges: edges)
        }
        
        return GraphSchema(nodes: nodes, edges: edges)
    }
    
    private struct TableInfo {
        enum TableType {
            case node
            case edge
        }
        
        let tableType: TableType
        let ddl: String
        let columns: [(name: String, type: String, constraints: [String])]
        let fromType: String?
        let toType: String?
    }
    
    private func parseTableSchema(
        tableName: String,
        tableRow: [String: Any],
        schemaRows: [[String: Any]]
    ) throws -> TableInfo {
        var columns: [(name: String, type: String, constraints: [String])] = []
        var tableType: TableInfo.TableType = .node
        var fromType: String?
        var toType: String?
        
        // Determine table type from SHOW TABLES result
        if let type = tableRow["type"] as? String {
            tableType = type.uppercased().contains("REL") ? .edge : .node
        }
        
        // For edge tables, extract source and target from the table row
        if tableType == .edge {
            fromType = tableRow["src"] as? String
            toType = tableRow["dst"] as? String
        }
        
        // Parse column information from DESCRIBE output
        for row in schemaRows {
            guard let columnName = row["property"] as? String ?? row["column"] as? String,
                  let dataType = row["type"] as? String else {
                continue
            }
            
            var constraints: [String] = []
            
            // Check for primary key constraint
            if let isPrimary = row["primary"] as? Bool, isPrimary {
                constraints.append("PRIMARY KEY")
            }
            
            // Check for other constraints
            if let isUnique = row["unique"] as? Bool, isUnique {
                constraints.append("UNIQUE")
            }
            
            if let isNotNull = row["not_null"] as? Bool, isNotNull {
                constraints.append("NOT NULL")
            }
            
            columns.append((
                name: columnName,
                type: dataType,
                constraints: constraints
            ))
        }
        
        // Reconstruct DDL based on parsed information
        let ddl = reconstructDDL(
            tableName: tableName,
            tableType: tableType,
            columns: columns,
            fromType: fromType,
            toType: toType
        )
        
        return TableInfo(
            tableType: tableType,
            ddl: ddl,
            columns: columns,
            fromType: fromType,
            toType: toType
        )
    }
    
    private func reconstructDDL(
        tableName: String,
        tableType: TableInfo.TableType,
        columns: [(name: String, type: String, constraints: [String])],
        fromType: String?,
        toType: String?
    ) -> String {
        let columnDefs = columns.map { column in
            var def = "\(column.name) \(column.type)"
            if !column.constraints.isEmpty {
                def += " " + column.constraints.joined(separator: " ")
            }
            return def
        }.joined(separator: ", ")
        
        switch tableType {
        case .node:
            return "CREATE NODE TABLE \(tableName) (\(columnDefs))"
        case .edge:
            let fromTo = (fromType != nil && toType != nil) ? " FROM \(fromType!) TO \(toType!)" : ""
            return "CREATE REL TABLE \(tableName)\(fromTo) (\(columnDefs))"
        }
    }
    
    private func validateMigration(diff: SchemaDiff) throws {
        switch policy {
        case .none:
            if !diff.isEmpty {
                throw GraphError.migrationFailed(
                    reason: "Migration policy is set to .none but schema changes were detected"
                )
            }
            
        case .safeOnly:
            if !diff.droppedNodes.isEmpty || !diff.droppedEdges.isEmpty {
                throw GraphError.migrationFailed(
                    reason: "Destructive changes detected but migration policy is .safeOnly"
                )
            }
            
            // Check for type changes in modified nodes
            for (currentNode, targetNode) in diff.modifiedNodes {
                if SchemaDiff.hasTypeChanges(current: currentNode, target: targetNode) {
                    throw GraphError.migrationFailed(
                        reason: "Column type change detected in node '\(currentNode.name)' but migration policy is .safeOnly. Type changes require .allowDestructive policy."
                    )
                }
            }
            
            // Check for type changes in modified edges
            for (currentEdge, targetEdge) in diff.modifiedEdges {
                if SchemaDiff.hasTypeChanges(current: currentEdge, target: targetEdge) {
                    throw GraphError.migrationFailed(
                        reason: "Column type change detected in edge '\(currentEdge.name)' but migration policy is .safeOnly. Type changes require .allowDestructive policy."
                    )
                }
            }
            
        case .allowDestructive:
            // All changes allowed
            break
        }
    }
    
    private func applyMigration(diff: SchemaDiff) async throws {
        var statements: [String] = []
        
        // Add new nodes
        for node in diff.addedNodes {
            statements.append(node.ddl)
        }
        
        // Add new edges
        for edge in diff.addedEdges {
            statements.append(edge.ddl)
        }
        
        // Drop edges (must be done before dropping nodes due to foreign key constraints)
        if policy.allowsDroppingTables {
            for edge in diff.droppedEdges {
                statements.append("DROP TABLE \(edge.name)")
            }
        }
        
        // Drop nodes
        if policy.allowsDroppingTables {
            for node in diff.droppedNodes {
                statements.append("DROP TABLE \(node.name)")
            }
        }
        
        // Execute all statements in a transaction
        if !statements.isEmpty {
            let statementsToExecute = statements.joined(separator: "; ")
            _ = try await context.withTransaction { txCtx in
                return try txCtx.raw(statementsToExecute)
            }
        }
    }
}