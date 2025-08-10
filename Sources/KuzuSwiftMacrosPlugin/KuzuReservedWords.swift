import Foundation

/// Kuzu SQL reserved words that need to be escaped with backticks
enum KuzuReservedWords {
    /// Complete list of Kuzu SQL reserved words
    /// Based on Kuzu documentation and Cypher/SQL standards
    static let reservedWords: Set<String> = [
        // Cypher/SQL Keywords
        "ADD", "ALL", "ALTER", "AND", "AS", "ASC", "ATTACH",
        "BEGIN", "BY",
        "CALL", "CASE", "CHECKPOINT", "COLUMN", "COMMENT", "COMMIT", "COPY", "COUNT", "CREATE",
        "DATABASE", "DEFAULT", "DELETE", "DESC", "DESCRIBE", "DETACH", "DISTINCT", "DROP",
        "ELSE", "END", "EXISTS", "EXPLAIN", "EXPORT", "EXTENSION",
        "FALSE", "FOR", "FORCE", "FROM", "FULL",
        "GRANT", "GROUP",
        "HAVING",
        "IF", "IMPORT", "IN", "INDEX", "INNER", "INSERT", "INSTALL", "INTO", "IS",
        "JOIN",
        "KEY",
        "LEFT", "LIMIT", "LOAD",
        "MATCH", "MERGE",
        "NODE", "NOT", "NULL",
        "ON", "OPTIONAL", "OR", "ORDER", "OUTER",
        "PRIMARY", "PROFILE",
        "REL", "REMOVE", "RENAME", "RETURN", "REVOKE", "RIGHT", "ROLLBACK",
        "SELECT", "SET", "SHOW",
        "TABLE", "THEN", "TO", "TRUE",
        "UNION", "UNIQUE", "UNINSTALL", "UNWIND", "UPDATE", "USE", "USING",
        "VALUES",
        "WHEN", "WHERE", "WITH",
        
        // Common problematic words
        "order", "group", "by", "limit", "exists", "count", "sum", "avg", "min", "max",
        "ORDER", "GROUP", "BY", "LIMIT", "EXISTS", "COUNT", "SUM", "AVG", "MIN", "MAX"
    ]
    
    /// Check if a word is reserved (case-insensitive)
    static func isReserved(_ word: String) -> Bool {
        return reservedWords.contains(word.uppercased()) || 
               reservedWords.contains(word.lowercased())
    }
    
    /// Escape a column name if it's a reserved word
    static func escapeIfNeeded(_ columnName: String) -> String {
        if isReserved(columnName) {
            return "`\(columnName)`"
        }
        return columnName
    }
    
    /// Escape multiple column names
    static func escapeColumnNames(_ names: [String]) -> [String] {
        return names.map { escapeIfNeeded($0) }
    }
}