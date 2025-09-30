import Foundation
import Kuzu

/// Manages vector index creation and verification
struct VectorIndexManager {
    /// Check if a vector index exists on a table
    /// - Parameters:
    ///   - table: The table name
    ///   - indexName: The index name
    ///   - context: The GraphContext to use for queries
    /// - Returns: true if the index exists, false otherwise
    static func hasVectorIndex(
        table: String,
        indexName: String,
        context: GraphContext
    ) async throws -> Bool {
        do {
            // Attempt to use the index with a dummy query
            // This will fail if the index doesn't exist
            let query = """
                CALL QUERY_VECTOR_INDEX('\(table)', '\(indexName)', CAST([0.0] AS FLOAT[1]), 1)
                RETURN node
                """
            _ = try await context.raw(query)
            return true
        } catch {
            // Check error message to determine if index doesn't exist
            let errorMessage = String(describing: error).lowercased()

            if errorMessage.contains("does not exist") ||
               errorMessage.contains("not found") ||
               errorMessage.contains("doesn't have an index") ||
               errorMessage.contains("unknown index") {
                return false
            }

            // For other errors (dimension mismatch, etc.), the index might exist
            // but we can't be sure. Better to return false and attempt creation
            // (creation will fail gracefully if it already exists)
            return false
        }
    }

    /// Create a vector index for a property
    /// - Parameters:
    ///   - table: The table name
    ///   - column: The column name
    ///   - indexName: The index name
    ///   - metric: The distance metric
    ///   - context: The GraphContext to use for index creation
    /// - Throws: GraphError if index creation fails
    static func createVectorIndex(
        table: String,
        column: String,
        indexName: String,
        metric: VectorMetric,
        context: GraphContext
    ) async throws {
        let query = """
            CALL CREATE_VECTOR_INDEX(
                '\(table)',
                '\(indexName)',
                '\(column)',
                metric := '\(metric.rawValue)'
            )
            """

        do {
            _ = try await context.raw(query)
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

    /// Create all vector indexes for a model type
    /// - Parameters:
    ///   - type: The model type conforming to HasVectorProperties
    ///   - context: The GraphContext to use for index creation
    /// - Throws: GraphError if index creation fails
    static func createVectorIndexes<T: _KuzuGraphModel & HasVectorProperties>(
        for type: T.Type,
        context: GraphContext
    ) async throws {
        let tableName = String(describing: type)

        for property in T._vectorProperties {
            let indexName = property.indexName(for: tableName)

            // Check if index already exists (idempotency)
            if try await hasVectorIndex(table: tableName, indexName: indexName, context: context) {
                continue
            }

            // Create the index
            try await createVectorIndex(
                table: tableName,
                column: property.propertyName,
                indexName: indexName,
                metric: property.metric,
                context: context
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