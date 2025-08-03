import Foundation

// MARK: - Full-Text Search Extension

public extension GraphContext {
    var fts: FullTextSearch {
        FullTextSearch(context: self)
    }
}

public struct FullTextSearch {
    private let context: GraphContext
    
    init(context: GraphContext) {
        self.context = context
    }
    
    // MARK: - Search Operations
    
    public func search<T: _KuzuGraphModel>(
        in type: T.Type,
        property: String,
        query: String,
        limit: Int = 100
    ) async throws -> [FTSResult<T>] {
        let indexName = "\(T._kuzuTableName)_\(property)_fts_idx"
        
        let cypher = """
            CALL fts.search('\(indexName)', $1)
            YIELD node, score
            ORDER BY score DESC
            LIMIT $2
            RETURN node, score
            """
        
        let bindings: [String: any Encodable] = [
            "1": query,
            "2": limit
        ]
        
        return try await context.raw(cypher, bindings: bindings)
    }
    
    // MARK: - Advanced Search
    
    public func advancedSearch<T: _KuzuGraphModel>(
        in type: T.Type,
        property: String,
        query: FTSQuery,
        limit: Int = 100
    ) async throws -> [FTSResult<T>] {
        let indexName = "\(T._kuzuTableName)_\(property)_fts_idx"
        let queryString = query.build()
        
        let cypher = """
            CALL fts.search('\(indexName)', $1)
            YIELD node, score
            ORDER BY score DESC
            LIMIT $2
            RETURN node, score
            """
        
        let bindings: [String: any Encodable] = [
            "1": queryString,
            "2": limit
        ]
        
        return try await context.raw(cypher, bindings: bindings)
    }
    
    // MARK: - Multi-field Search
    
    public func multiFieldSearch<T: _KuzuGraphModel>(
        in type: T.Type,
        fields: [(property: String, boost: Float?)],
        query: String,
        limit: Int = 100
    ) async throws -> [FTSResult<T>] {
        // Build a UNION query for multiple fields
        let subQueries = fields.map { field in
            let indexName = "\(T._kuzuTableName)_\(field.property)_fts_idx"
            let boost = field.boost ?? 1.0
            
            return """
                CALL fts.search('\(indexName)', $1)
                YIELD node, score
                RETURN node, score * \(boost) AS adjusted_score
                """
        }
        
        let cypher = """
            WITH $1 AS query_text
            \(subQueries.joined(separator: "\nUNION ALL\n"))
            ORDER BY adjusted_score DESC
            LIMIT $2
            RETURN node, adjusted_score AS score
            """
        
        let bindings: [String: any Encodable] = [
            "1": query,
            "2": limit
        ]
        
        return try await context.raw(cypher, bindings: bindings)
    }
    
    // MARK: - Index Management
    
    public func createIndex<T: _KuzuGraphModel>(
        on type: T.Type,
        property: String,
        analyzer: FTSAnalyzer = .standard
    ) async throws {
        let indexName = "\(T._kuzuTableName)_\(property)_fts_idx"
        
        let cypher = """
            CREATE FTS INDEX \(indexName)
            ON \(T._kuzuTableName) (\(property))
            WITH ANALYZER = '\(analyzer.rawValue)'
            """
        
        _ = try await context.rawQuery(cypher)
    }
    
    public func dropIndex<T: _KuzuGraphModel>(
        on type: T.Type,
        property: String
    ) async throws {
        let indexName = "\(T._kuzuTableName)_\(property)_fts_idx"
        let cypher = "DROP INDEX \(indexName)"
        _ = try await context.rawQuery(cypher)
    }
}

// MARK: - FTS Query Builder

public struct FTSQuery {
    private var components: [FTSQueryComponent] = []
    
    public init() {}
    
    public func term(_ term: String, field: String? = nil, boost: Float? = nil) -> FTSQuery {
        var query = self
        query.components.append(.term(term, field: field, boost: boost))
        return query
    }
    
    public func phrase(_ phrase: String, field: String? = nil, boost: Float? = nil) -> FTSQuery {
        var query = self
        query.components.append(.phrase(phrase, field: field, boost: boost))
        return query
    }
    
    public func prefix(_ prefix: String, field: String? = nil, boost: Float? = nil) -> FTSQuery {
        var query = self
        query.components.append(.prefix(prefix, field: field, boost: boost))
        return query
    }
    
    public func fuzzy(_ term: String, maxEdits: Int = 2, field: String? = nil, boost: Float? = nil) -> FTSQuery {
        var query = self
        query.components.append(.fuzzy(term, maxEdits: maxEdits, field: field, boost: boost))
        return query
    }
    
    public func wildcard(_ pattern: String, field: String? = nil, boost: Float? = nil) -> FTSQuery {
        var query = self
        query.components.append(.wildcard(pattern, field: field, boost: boost))
        return query
    }
    
    public func and(_ other: FTSQuery) -> FTSQuery {
        var query = self
        query.components.append(.and(other))
        return query
    }
    
    public func or(_ other: FTSQuery) -> FTSQuery {
        var query = self
        query.components.append(.or(other))
        return query
    }
    
    public func not(_ other: FTSQuery) -> FTSQuery {
        var query = self
        query.components.append(.not(other))
        return query
    }
    
    func build() -> String {
        components.map { $0.build() }.joined(separator: " ")
    }
}

private enum FTSQueryComponent {
    case term(String, field: String?, boost: Float?)
    case phrase(String, field: String?, boost: Float?)
    case prefix(String, field: String?, boost: Float?)
    case fuzzy(String, maxEdits: Int, field: String?, boost: Float?)
    case wildcard(String, field: String?, boost: Float?)
    case and(FTSQuery)
    case or(FTSQuery)
    case not(FTSQuery)
    
    func build() -> String {
        switch self {
        case .term(let term, let field, let boost):
            return buildFieldQuery(term, field: field, boost: boost)
        case .phrase(let phrase, let field, let boost):
            return buildFieldQuery("\"\(phrase)\"", field: field, boost: boost)
        case .prefix(let prefix, let field, let boost):
            return buildFieldQuery("\(prefix)*", field: field, boost: boost)
        case .fuzzy(let term, let maxEdits, let field, let boost):
            return buildFieldQuery("\(term)~\(maxEdits)", field: field, boost: boost)
        case .wildcard(let pattern, let field, let boost):
            return buildFieldQuery(pattern, field: field, boost: boost)
        case .and(let query):
            return "AND (\(query.build()))"
        case .or(let query):
            return "OR (\(query.build()))"
        case .not(let query):
            return "NOT (\(query.build()))"
        }
    }
    
    private func buildFieldQuery(_ query: String, field: String?, boost: Float?) -> String {
        var result = ""
        if let field = field {
            result += "\(field):"
        }
        result += query
        if let boost = boost {
            result += "^\(boost)"
        }
        return result
    }
}

// MARK: - FTS Analyzer

public enum FTSAnalyzer: String {
    case standard = "standard"
    case simple = "simple"
    case whitespace = "whitespace"
    case stop = "stop"
    case keyword = "keyword"
    case pattern = "pattern"
    case language = "language"
}

// MARK: - Result Types

public struct FTSResult<T: _KuzuGraphModel>: Decodable {
    public let node: T
    public let score: Float
    
    public init(node: T, score: Float) {
        self.node = node
        self.score = score
    }
    
    // Simplified decoding - in production, this would decode from Kuzu's result format
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.node = try container.decode(T.self, forKey: .node)
        self.score = try container.decode(Float.self, forKey: .score)
    }
    
    private enum CodingKeys: String, CodingKey {
        case node
        case score
    }
}