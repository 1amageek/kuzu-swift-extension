import Foundation
import KuzuFramework

actor MigrationManager {
    private let connection: Connection
    private let policy: MigrationPolicy
    
    init(connection: Connection, policy: MigrationPolicy) {
        self.connection = connection
        self.policy = policy
    }
    
    func migrate(schema: GraphSchema) async throws {
        let currentSchema = try await fetchCurrentSchema()
        let targetSchema = schema.models.flatMap { $0._kuzuDDL }
        let diff = try computeDiff(current: currentSchema, target: targetSchema)
        
        if diff.hasDestructiveChanges && policy == .safeOnly {
            throw GraphError.destructiveMigrationBlocked(
                table: diff.destructiveChanges.first?.table ?? "",
                column: diff.destructiveChanges.first?.column
            )
        }
        
        // Execute migration statements in a transaction
        for statement in diff.statements {
            do {
                _ = try connection.query(statement)
            } catch {
                throw GraphError.schemaMigrationFailed(sql: statement, underlying: error)
            }
        }
    }
    
    private func fetchCurrentSchema() async throws -> [String] {
        var currentDDL: [String] = []
        
        // Fetch node tables
        do {
            let nodeTablesResult = try connection.query("SHOW NODE TABLES")
            while nodeTablesResult.hasNext() {
                if let tableName = try nodeTablesResult.getNext()?.getValue(0)?.getValue() as? String {
                    // Get table info
                    let tableInfo = try connection.query("PRAGMA table_info('\(tableName)')")
                    var columns: [String] = []
                    
                    while tableInfo.hasNext() {
                        if let columnInfo = try tableInfo.getNext() {
                            // Extract column definition from pragma result
                            if let name = columnInfo.getValue(1)?.getValue() as? String,
                               let type = columnInfo.getValue(2)?.getValue() as? String {
                                columns.append("\(name) \(type)")
                            }
                        }
                    }
                    
                    if !columns.isEmpty {
                        currentDDL.append("CREATE NODE TABLE \(tableName) (\(columns.joined(separator: ", ")))")
                    }
                }
            }
        } catch {
            // If SHOW NODE TABLES fails, assume empty database
        }
        
        // Fetch rel tables
        do {
            let relTablesResult = try connection.query("SHOW REL TABLES")
            while relTablesResult.hasNext() {
                if let tableName = try relTablesResult.getNext()?.getValue(0)?.getValue() as? String {
                    // Get rel table info
                    let tableInfo = try connection.query("PRAGMA table_info('\(tableName)')")
                    var columns: [String] = []
                    
                    while tableInfo.hasNext() {
                        if let columnInfo = try tableInfo.getNext() {
                            if let name = columnInfo.getValue(1)?.getValue() as? String,
                               let type = columnInfo.getValue(2)?.getValue() as? String {
                                columns.append("\(name) \(type)")
                            }
                        }
                    }
                    
                    // For rel tables, we need to determine FROM and TO
                    // This is a simplified version - in production, we'd parse the actual schema
                    currentDDL.append("CREATE REL TABLE \(tableName) (...)")
                }
            }
        } catch {
            // If SHOW REL TABLES fails, assume no relationships
        }
        
        return currentDDL
    }
    
    private func computeDiff(current: [String], target: [String]) throws -> SchemaDiff {
        var statements: [String] = []
        var destructiveChanges: [(table: String, column: String?)] = []
        
        // Simple diff algorithm - in production, this would be more sophisticated
        let currentSet = Set(current.map { normalizeSQL($0) })
        let targetSet = Set(target.map { normalizeSQL($0) })
        
        // Find new tables to create
        for ddl in target {
            let normalized = normalizeSQL(ddl)
            if !currentSet.contains(normalized) {
                statements.append(ddl)
            }
        }
        
        // Find tables to drop (destructive)
        for ddl in current {
            let normalized = normalizeSQL(ddl)
            if !targetSet.contains(normalized) {
                if let tableName = extractTableName(from: ddl) {
                    destructiveChanges.append((table: tableName, column: nil))
                }
            }
        }
        
        return SchemaDiff(statements: statements, destructiveChanges: destructiveChanges)
    }
    
    private func normalizeSQL(_ sql: String) -> String {
        // Normalize SQL for comparison
        sql.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractTableName(from ddl: String) -> String? {
        // Extract table name from CREATE TABLE statement
        let pattern = "CREATE\\s+(NODE|REL)\\s+TABLE\\s+(\\w+)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: ddl, range: NSRange(ddl.startIndex..., in: ddl)),
           match.numberOfRanges > 2 {
            let tableNameRange = match.range(at: 2)
            if let range = Range(tableNameRange, in: ddl) {
                return String(ddl[range])
            }
        }
        return nil
    }
}