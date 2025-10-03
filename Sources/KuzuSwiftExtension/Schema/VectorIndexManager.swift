import Foundation
import Kuzu

/// Manages vector index creation and verification
struct VectorIndexManager {
    /// Check if a vector index exists on a table
    /// - Parameters:
    ///   - table: The table name
    ///   - indexName: The index name
    ///   - connection: The database connection to use
    /// - Returns: true if the index exists, false otherwise
    static func hasVectorIndex(
        table: String,
        indexName: String,
        connection: Connection
    ) throws -> Bool {
        // Query the catalog for existing indexes
        let result = try connection.query("CALL SHOW_INDEXES() RETURN *")

        while result.hasNext() {
            if let row = try result.getNext() {
                // Column structure: 0=table_name, 1=index_name, 2=index_type, ...
                if let tableName = try row.getValue(0) as? String,
                   let idxName = try row.getValue(1) as? String,
                   let indexType = try row.getValue(2) as? String {
                    if tableName == table &&
                       idxName == indexName &&
                       indexType == "HNSW" {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// Create a vector index for a property
    /// - Parameters:
    ///   - table: The table name
    ///   - column: The column name
    ///   - indexName: The index name
    ///   - metric: The distance metric
    ///   - connection: The database connection to use
    /// - Throws: GraphError if index creation fails
    static func createVectorIndex(
        table: String,
        column: String,
        indexName: String,
        metric: VectorMetric,
        connection: Connection
    ) throws {
        let query = """
            CALL CREATE_VECTOR_INDEX(
                '\(table)',
                '\(indexName)',
                '\(column)',
                metric := '\(metric.rawValue)'
            )
            """
        print(query)
        do {
            _ = try connection.query(query)
        } catch {
            // Check if it's an "already exists" error - if so, ignore
            let errorMessage = String(describing: error).lowercased()
            if errorMessage.contains("already exists") ||
               errorMessage.contains("duplicate") {
                // Index already exists - this is fine
                return
            }

            // Re-throw other errors
            throw GraphError.indexCreationFailed(
                table: table,
                indexName: indexName,
                underlying: error
            )
        }
    }

}

// MARK: - GraphError Extensions

extension GraphError {
    /// Error creating a vector index
    static func indexCreationFailed(
        table: String,
        indexName: String,
        underlying: Error
    ) -> GraphError {
        .executionFailed(
            query: "CREATE_VECTOR_INDEX",
            reason: "Failed to create vector index '\(indexName)' on table '\(table)': \(underlying.localizedDescription)"
        )
    }
}
