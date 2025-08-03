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
        
        // Query node tables
        let nodeTablesQuery = """
            CALL table_info('NODE_TABLE') RETURN *
        """
        
        do {
            let nodeResult = try await context.raw(nodeTablesQuery, bindings: [:])
            while nodeResult.hasNextQueryResult() {
                let next = try nodeResult.getNextQueryResult()
                // TODO: Parse node table info
            }
        } catch {
            // No existing tables
        }
        
        // Query rel tables
        let relTablesQuery = """
            CALL table_info('REL_TABLE') RETURN *
        """
        
        do {
            let relResult = try await context.raw(relTablesQuery, bindings: [:])
            while relResult.hasNextQueryResult() {
                let next = try relResult.getNextQueryResult()
                // TODO: Parse rel table info
            }
        } catch {
            // No existing tables
        }
        
        return GraphSchema(nodes: nodes, edges: edges)
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
            _ = try await context.rawTransaction(statements.joined(separator: "; "), bindings: [:])
        }
    }
}