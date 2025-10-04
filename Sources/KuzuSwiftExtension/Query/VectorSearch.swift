import Foundation
import Kuzu

/// A type-safe vector search query component using HNSW index
///
/// VectorSearch automatically generates CALL QUERY_VECTOR_INDEX queries with proper type casting
/// and parameter binding, eliminating common bugs from manual Cypher construction.
///
/// Usage:
/// ```swift
/// let results = try await context.queryArray(PhotoAsset.self) {
///     VectorSearch(\.labColor, query: queryVector, k: 10)
///     Where(\.enabled == true)
/// }
/// ```
@dynamicMemberLookup
public struct VectorSearch<Model: GraphNodeModel & Decodable>: QueryComponent {
    public typealias Result = [(model: Model, distance: Double)]

    /// The KeyPath to the vector property
    let vectorKeyPath: PartialKeyPath<Model>

    /// The query vector
    let queryVector: [Float]

    /// Number of nearest neighbors to return
    let k: Int

    /// Optional alias for the returned node (defaults to "node")
    public let alias: String

    /// Optional filter predicate (applied via WHERE clause after vector search)
    let predicate: Predicate?

    /// Optional ORDER BY clause
    fileprivate let orderByClause: VectorOrderBy?

    /// Optional LIMIT clause (overrides k parameter if set)
    let limit: Int?

    /// Create a vector search query
    /// - Parameters:
    ///   - vectorKeyPath: KeyPath to the @Vector property
    ///   - query: The query vector to search for
    ///   - k: Number of nearest neighbors to return (default: 10)
    ///   - alias: Alias for the returned node (default: "node")
    public init(
        _ vectorKeyPath: KeyPath<Model, [Float]>,
        query: [Float],
        k: Int = 10,
        alias: String = "node"
    ) {
        self.vectorKeyPath = vectorKeyPath
        self.queryVector = query
        self.k = k
        self.alias = alias
        self.predicate = nil
        self.orderByClause = nil
        self.limit = nil
    }

    /// Private initializer for builder pattern
    private init(
        vectorKeyPath: PartialKeyPath<Model>,
        queryVector: [Float],
        k: Int,
        alias: String,
        predicate: Predicate?,
        orderByClause: VectorOrderBy?,
        limit: Int?
    ) {
        self.vectorKeyPath = vectorKeyPath
        self.queryVector = queryVector
        self.k = k
        self.alias = alias
        self.predicate = predicate
        self.orderByClause = orderByClause
        self.limit = limit
    }

    // MARK: - Query Modifiers

    /// Add a WHERE filter to the vector search results
    public func `where`(_ predicate: Predicate) -> VectorSearch {
        let combined = self.predicate.map { $0.and(predicate) } ?? predicate
        return VectorSearch(
            vectorKeyPath: vectorKeyPath,
            queryVector: queryVector,
            k: k,
            alias: alias,
            predicate: combined,
            orderByClause: orderByClause,
            limit: limit
        )
    }

    /// Add a WHERE filter using KeyPath
    public func `where`<Value: Sendable>(_ keyPath: KeyPath<Model, Value>, _ op: ComparisonOperator, _ value: Value) -> VectorSearch {
        let columnName = KeyPathUtilities.columnName(from: keyPath)
        let propRef = PropertyReference(alias: alias, property: columnName)
        let comparison = ComparisonExpression(lhs: propRef, op: op, rhs: .value(value))
        let predicate = Predicate(node: .comparison(comparison))
        return self.where(predicate)
    }

    /// Order results by a property (in addition to distance ordering)
    public func orderBy<Value>(_ keyPath: KeyPath<Model, Value>, _ direction: SortDirection = .ascending) -> VectorSearch {
        let columnName = KeyPathUtilities.columnName(from: keyPath)
        let clause = VectorOrderBy(property: columnName, direction: direction)
        return VectorSearch(
            vectorKeyPath: vectorKeyPath,
            queryVector: queryVector,
            k: k,
            alias: alias,
            predicate: predicate,
            orderByClause: clause,
            limit: limit
        )
    }

    /// Limit the number of results
    public func limit(_ count: Int) -> VectorSearch {
        VectorSearch(
            vectorKeyPath: vectorKeyPath,
            queryVector: queryVector,
            k: k,
            alias: alias,
            predicate: predicate,
            orderByClause: orderByClause,
            limit: count
        )
    }

    /// Dynamic member lookup for property access on results
    public subscript<Value>(dynamicMember keyPath: KeyPath<Model, Value>) -> PropertyReference {
        let columnName = KeyPathUtilities.columnName(from: keyPath)
        return PropertyReference(alias: alias, property: columnName)
    }

    // MARK: - Cypher Generation

    public func toCypher() throws -> CypherFragment {
        // Get metadata to find vector property info
        let metadata = Model._metadata
        let propertyName = KeyPathUtilities.propertyName(from: vectorKeyPath, on: Model.self)

        guard let vectorProp = metadata.vectorProperties.first(where: { $0.propertyName == propertyName }) else {
            throw KuzuError.invalidOperation(
                message: "Property '\(propertyName)' is not marked with @Vector macro on \(String(describing: Model.self))"
            )
        }

        // Validate vector dimensions
        guard queryVector.count == vectorProp.dimensions else {
            throw KuzuError.invalidOperation(
                message: "Query vector dimensions (\(queryVector.count)) do not match property dimensions (\(vectorProp.dimensions)) for '\(propertyName)'"
            )
        }

        let tableName = Model.name
        let indexName = vectorProp.indexName(for: tableName)
        let dimensions = vectorProp.dimensions

        // Generate parameters
        var parameters: [String: any Sendable] = [:]
        let kParam = "k"

        parameters[kParam] = k

        // Build query with vector literal (Kuzu doesn't support CAST on parameters)
        let vectorLiteral = "[" + queryVector.map { String($0) }.joined(separator: ", ") + "]"
        var query = """
            CALL QUERY_VECTOR_INDEX('\(tableName)', '\(indexName)',
                CAST(\(vectorLiteral) AS FLOAT[\(dimensions)]), $\(kParam))
            WITH node AS \(alias), distance
            """

        // Add WHERE clause if predicate exists
        if let predicate = predicate {
            let predicateCypher = try predicate.toCypher()
            query += "\nWHERE \(predicateCypher.query)"
            parameters.merge(predicateCypher.parameters) { _, new in new }
        }

        // Add RETURN clause with both node and distance
        query += "\nRETURN \(alias), distance"

        // Add ORDER BY clause (if specified, in addition to distance ordering)
        if let orderByClause = orderByClause {
            let dir = orderByClause.direction == .ascending ? "ASC" : "DESC"
            query += "\nORDER BY \(alias).\(orderByClause.property) \(dir)"
        } else {
            // Default: order by distance
            query += "\nORDER BY distance ASC"
        }

        // Add LIMIT clause
        if let limit = limit {
            query += "\nLIMIT \(limit)"
        }

        return CypherFragment(query: query, parameters: parameters)
    }

    // MARK: - Result Mapping

    public func mapResult(_ result: QueryResult, decoder: KuzuDecoder) throws -> Result {
        var results: [(model: Model, distance: Double)] = []

        while result.hasNext() {
            guard let row = try result.getNext() else { continue }

            // Column 0: node (KuzuNode)
            // Column 1: distance (Double)
            let nodeValue = try row.getValue(0)
            let distanceValue = try row.getValue(1)

            guard let kuzuNode = nodeValue as? KuzuNode else {
                throw KuzuError.typeMismatch(
                    expected: "KuzuNode",
                    actual: String(describing: type(of: nodeValue)),
                    field: "column 0"
                )
            }

            guard let distance = distanceValue as? Double else {
                throw KuzuError.typeMismatch(
                    expected: "Double",
                    actual: String(describing: type(of: distanceValue)),
                    field: "distance (column 1)"
                )
            }

            // Decode node to Model
            let model = try decoder.decode(Model.self, from: kuzuNode.properties)
            results.append((model: model, distance: distance))
        }

        return results
    }
}

// MARK: - VectorOrderBy

fileprivate struct VectorOrderBy {
    let property: String
    let direction: SortDirection
}

// MARK: - GraphNodeModel Extension

public extension GraphNodeModel where Self: Decodable {

    /// Perform a vector search on a @Vector property
    /// - Parameters:
    ///   - keyPath: KeyPath to the @Vector property
    ///   - query: The query vector
    ///   - k: Number of nearest neighbors to return
    ///   - alias: Alias for the returned node
    /// - Returns: VectorSearch query component
    static func vectorSearch(
        _ keyPath: KeyPath<Self, [Float]>,
        query: [Float],
        k: Int = 10,
        alias: String = "node"
    ) -> VectorSearch<Self> {
        VectorSearch(keyPath, query: query, k: k, alias: alias)
    }
}
