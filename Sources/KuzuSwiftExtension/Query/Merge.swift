import Foundation

public struct Merge<T: _KuzuGraphModel> {
    internal var clause: MergeClause
    
    public init(
        _ type: T.Type,
        as variable: String? = nil,
        on matchProperties: [String: Any],
        onCreate: [String: Any] = [:],
        onMatch: [String: Any] = [:]
    ) {
        self.clause = MergeClause(
            variable: variable ?? type._kuzuTableName.lowercased(),
            type: type,
            matchProperties: matchProperties,
            onCreateProperties: onCreate,
            onMatchProperties: onMatch
        )
    }
    
    internal init(clause: MergeClause) {
        self.clause = clause
    }
}