import Foundation
import Kuzu

/// Manages Full-Text Search index creation and verification
///
/// Full-Text Search (FTS) enables efficient text searching with features like
/// stemming, stopword removal, and relevance scoring using the BM25 algorithm.
struct FullTextSearchIndexManager {
    /// Create a Full-Text Search index for a property
    /// - Parameters:
    ///   - table: The table name
    ///   - column: The column name
    ///   - indexName: The index name
    ///   - stemmer: The stemmer to use (default: "porter")
    ///   - connection: The database connection to use
    /// - Throws: GraphError if index creation fails
    static func createFullTextSearchIndex(
        table: String,
        column: String,
        indexName: String,
        stemmer: String = "porter",
        connection: Connection
    ) throws {
        let query = """
            CALL CREATE_FTS_INDEX(
                '\(table)',
                '\(indexName)',
                ['\(column)'],
                stemmer := '\(stemmer)'
            )
            """

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
    /// Error creating a Full-Text Search index
    static func fullTextSearchIndexCreationFailed(
        table: String,
        indexName: String,
        underlying: Error
    ) -> GraphError {
        .executionFailed(
            query: "CREATE_FTS_INDEX",
            reason: "Failed to create Full-Text Search index '\(indexName)' on table '\(table)': \(underlying.localizedDescription)"
        )
    }
}
