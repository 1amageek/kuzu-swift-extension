import Foundation

public struct SchemaDiff {
    public let statements: [String]
    public let destructiveChanges: [(table: String, column: String?)]
    
    public var hasDestructiveChanges: Bool {
        !destructiveChanges.isEmpty
    }
    
    public init(statements: [String] = [], destructiveChanges: [(table: String, column: String?)] = []) {
        self.statements = statements
        self.destructiveChanges = destructiveChanges
    }
}