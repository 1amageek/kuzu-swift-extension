import Foundation
import Kuzu

/// Utility for mapping QueryResult to Swift types
public struct ResultMapper {
    
    // MARK: - Private Validation Helpers
    
    private static func validateColumnBounds(_ result: QueryResult, column: Int) throws {
        let columnCount = Int(result.getColumnCount())
        guard column < columnCount else {
            throw ResultMappingError.columnIndexOutOfBounds(index: column, columnCount: columnCount)
        }
    }
    
    private static func getFieldName(_ result: QueryResult, column: Int) -> String? {
        let columnNames = result.getColumnNames()
        return column < columnNames.count ? columnNames[column] : nil
    }
    
    // MARK: - Public Methods
    
    /// Maps a single value from the first row
    public static func value<T>(_ result: QueryResult, at column: Int = 0) throws -> T {
        guard result.hasNext() else {
            throw ResultMappingError.noResults
        }
        
        guard let flatTuple = try result.getNext() else {
            throw ResultMappingError.noResults
        }
        
        try validateColumnBounds(result, column: column)
        
        let value = try flatTuple.getValue(UInt64(column))
        
        // Check for null values on non-optional types
        guard let value = value else {
            let fieldName = getFieldName(result, column: column) ?? "column_\(column)"
            throw ResultMappingError.nullValueForNonOptionalType(
                field: fieldName,
                type: String(describing: T.self)
            )
        }
        
        return try cast(value, to: T.self, field: getFieldName(result, column: column))
    }
    
    /// Maps a single optional value from the first row
    public static func optionalValue<T>(_ result: QueryResult, at column: Int = 0) throws -> T? {
        guard result.hasNext() else {
            return nil
        }
        
        guard let flatTuple = try result.getNext() else {
            return nil
        }
        
        try validateColumnBounds(result, column: column)
        
        let value = try flatTuple.getValue(UInt64(column))
        guard let value = value else {
            return nil
        }
        
        return try cast(value, to: T.self, field: getFieldName(result, column: column))
    }
    
    /// Maps all values from a column as an array
    /// - Warning: This method consumes the QueryResult iterator. Subsequent calls will return empty results.
    /// - Note: QueryResult can only be iterated once. Store the results if you need to access them multiple times.
    public static func column<T>(_ result: QueryResult, at column: Int = 0) throws -> [T] {
        try validateColumnBounds(result, column: column)
        
        var values: [T] = []
        let fieldName = getFieldName(result, column: column)
        
        while result.hasNext() {
            guard let flatTuple = try result.getNext() else {
                break
            }
            
            let value = try flatTuple.getValue(UInt64(column))
            if let value = value {
                values.append(try cast(value, to: T.self, field: fieldName))
            }
        }
        
        return values
    }
    
    /// Maps a row to a dictionary
    public static func row(_ result: QueryResult) throws -> [String: Any] {
        guard result.hasNext() else {
            throw ResultMappingError.noResults
        }
        
        guard let flatTuple = try result.getNext() else {
            throw ResultMappingError.noResults
        }
        
        return try flatTuple.getAsDictionary().compactMapValues { $0 }
    }
    
    /// Maps all rows to an array of dictionaries
    /// - Warning: This method consumes the QueryResult iterator. Subsequent calls will return empty results.
    /// - Note: QueryResult can only be iterated once. Store the results if you need to access them multiple times.
    public static func rows(_ result: QueryResult) throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        
        while result.hasNext() {
            guard let flatTuple = try result.getNext() else {
                break
            }
            
            let dict = try flatTuple.getAsDictionary().compactMapValues { $0 }
            rows.append(dict)
        }
        
        return rows
    }
    
    // MARK: - Private Helpers
    
    private static func cast<T>(_ value: Any, to type: T.Type, field: String? = nil) throws -> T {
        // NSNull handling
        if value is NSNull {
            throw ResultMappingError.nullValueForNonOptionalType(
                field: field ?? "unknown",
                type: String(describing: T.self)
            )
        }
        
        // Use shared type conversion utility
        if let converted = TypeConversion.convert(value, to: type) {
            return converted
        }
        
        throw ResultMappingError.typeMismatch(
            expected: String(describing: T.self),
            actual: String(describing: Swift.type(of: value)),
            field: field
        )
    }
}

// MARK: - QueryResult Extensions

extension QueryResult {
    // MARK: - Decodable Support
    
    /// Decodes results to an array of Decodable types from a specific column
    public func decode<T: Decodable>(_ type: T.Type, column: String) throws -> [T] {
        let decoder = KuzuDecoder()
        var results: [T] = []
        
        // Find column index
        let columnNames = getColumnNames()
        guard let columnIndex = columnNames.firstIndex(of: column) else {
            throw ResultMappingError.columnNotFound(column: column)
        }
        
        while hasNext() {
            guard let flatTuple = try getNext() else {
                break
            }
            
            if let value = try flatTuple.getValue(UInt64(columnIndex)) {
                // Check if value is a KuzuNode (graph node)
                if let nodeValue = value as? Kuzu.KuzuNode {
                    // Extract properties dictionary from KuzuNode
                    let properties = nodeValue.properties
                    let decoded = try decoder.decode(T.self, from: properties)
                    results.append(decoded)
                } else if let dict = value as? [String: Any?] {
                    // Direct dictionary decoding
                    let decoded = try decoder.decode(T.self, from: dict)
                    results.append(decoded)
                } else if let dict = value as? [String: Any] {
                    // Try without optional values
                    let decoded = try decoder.decode(T.self, from: dict)
                    results.append(decoded)
                } else {
                    // Try to decode as a simple value
                    if let casted = value as? T {
                        results.append(casted)
                    }
                }
            }
        }
        
        return results
    }
    
    /// Decodes the first result to a Decodable type from a specific column
    public func first<T: Decodable>(_ type: T.Type, column: String) throws -> T? {
        guard hasNext() else {
            return nil
        }
        
        let decoder = KuzuDecoder()
        
        // Find column index
        let columnNames = getColumnNames()
        guard let columnIndex = columnNames.firstIndex(of: column) else {
            throw ResultMappingError.columnNotFound(column: column)
        }
        
        guard let flatTuple = try getNext() else {
            return nil
        }
        
        if let value = try flatTuple.getValue(UInt64(columnIndex)) {
            // Check if value is a KuzuNode (graph node)
            if let nodeValue = value as? Kuzu.KuzuNode {
                // Extract properties dictionary from KuzuNode
                let properties = nodeValue.properties
                return try decoder.decode(T.self, from: properties)
            } else if let dict = value as? [String: Any?] {
                // Direct dictionary decoding
                return try decoder.decode(T.self, from: dict)
            } else if let dict = value as? [String: Any] {
                // Try without optional values
                return try decoder.decode(T.self, from: dict)
            } else {
                // Try to decode as a simple value
                return value as? T
            }
        }
        
        return nil
    }
    
    /// Decodes node and edge pairs from the result
    public func decodePairs<N: Decodable, E: Decodable>(
        nodeType: N.Type,
        edgeType: E.Type,
        nodeColumn: String = "n",
        edgeColumn: String = "e"
    ) throws -> [(node: N, edge: E)] {
        let decoder = KuzuDecoder()
        var results: [(node: N, edge: E)] = []
        
        // Find column indices
        let columnNames = getColumnNames()
        guard let nodeIndex = columnNames.firstIndex(of: nodeColumn) else {
            throw ResultMappingError.columnNotFound(column: nodeColumn)
        }
        guard let edgeIndex = columnNames.firstIndex(of: edgeColumn) else {
            throw ResultMappingError.columnNotFound(column: edgeColumn)
        }
        
        while hasNext() {
            guard let flatTuple = try getNext() else {
                break
            }
            
            if let nodeValue = try flatTuple.getValue(UInt64(nodeIndex)),
               let edgeValue = try flatTuple.getValue(UInt64(edgeIndex)) {
                // Convert values to dictionaries for decoding
                if let nodeDict = nodeValue as? [String: Any?],
                   let edgeDict = edgeValue as? [String: Any?] {
                    let node = try decoder.decode(N.self, from: nodeDict)
                    let edge = try decoder.decode(E.self, from: edgeDict)
                    results.append((node: node, edge: edge))
                }
            }
        }
        
        return results
    }
    
    // MARK: - Single Value Mapping
    
    /// Maps the first result to a value
    public func mapFirst<T>(to type: T.Type, at column: Int = 0) throws -> T? {
        guard hasNext() else {
            return nil
        }
        return try ResultMapper.value(self, at: column)
    }
    
    /// Maps the first result to a value, throwing if no results
    public func mapFirstRequired<T>(to type: T.Type, at column: Int = 0) throws -> T {
        return try ResultMapper.value(self, at: column)
    }
    
    // MARK: - Collection Mapping
    
    /// Maps all results to an array of values
    /// - Warning: This method consumes the QueryResult iterator. Subsequent calls will return empty results.
    /// - Note: QueryResult can only be iterated once. Store the results if you need to access them multiple times.
    /// - TODO: When kuzu-swift supports result cloning, implement proper iterator reset functionality
    public func mapAll<T>(to type: T.Type, at column: Int = 0) throws -> [T] {
        let results: [T] = try ResultMapper.column(self, at: column)
        
        // Check if we've consumed an already-consumed iterator
        // This helps developers identify the issue quickly
        if results.isEmpty && !isEmpty {
            // Note: isEmpty also consumes the iterator, so we can't reliably detect this case
            // TODO: Remove this when kuzu-swift supports result.clone() or reset()
        }
        
        return results
    }
    
    /// Maps results to an array of dictionaries
    /// - Warning: This method consumes the QueryResult iterator. Subsequent calls will return empty results.
    /// - Note: QueryResult can only be iterated once. Store the results if you need to access them multiple times.
    public func mapRows() throws -> [[String: Any]] {
        return try ResultMapper.rows(self)
    }
    
    /// Maps the first row to a dictionary
    public func mapFirstRow() throws -> [String: Any]? {
        guard hasNext() else {
            return nil
        }
        return try ResultMapper.row(self)
    }
    
    // MARK: - Fluent API
    
    /// Maps each row with a transform function
    public func map<T>(_ transform: ([String: Any]) throws -> T) throws -> [T] {
        var results: [T] = []
        let rows = try mapRows()
        
        for row in rows {
            results.append(try transform(row))
        }
        
        return results
    }
    
    /// Filters rows based on a predicate
    public func filter(_ predicate: ([String: Any]) throws -> Bool) throws -> [[String: Any]] {
        let rows = try mapRows()
        return try rows.filter(predicate)
    }
    
    /// Transforms and filters in one operation
    public func compactMap<T>(_ transform: ([String: Any]) throws -> T?) throws -> [T] {
        var results: [T] = []
        let rows = try mapRows()
        
        for row in rows {
            if let transformed = try transform(row) {
                results.append(transformed)
            }
        }
        
        return results
    }
    
    // MARK: - Convenience Methods
    
    /// Returns true if the query has any results
    public var isEmpty: Bool {
        return !hasNext()
    }
    
    /// Counts the number of results
    /// - Warning: This method consumes the QueryResult iterator. The QueryResult cannot be used after calling this method.
    public func count() throws -> Int {
        var count = 0
        while hasNext() {
            _ = try getNext()
            count += 1
        }
        return count
    }
    
    /// Iterates over results with a closure
    public func forEach(_ body: ([String: Any]) throws -> Void) throws {
        let rows = try mapRows()
        for row in rows {
            try body(row)
        }
    }
    
    /// Returns the first N results
    public func limit(_ count: Int) throws -> [[String: Any]] {
        var results: [[String: Any]] = []
        var current = 0
        
        while hasNext() && current < count {
            results.append(try ResultMapper.row(self))
            current += 1
        }
        
        return results
    }
}

// MARK: - Typed Extensions for Common Cases

extension QueryResult {
    /// Maps a single-column result to an array of strings
    public func mapStrings(at column: Int = 0) throws -> [String] {
        return try mapAll(to: String.self, at: column)
    }
    
    /// Maps a single-column result to an array of integers
    public func mapInts(at column: Int = 0) throws -> [Int] {
        return try mapAll(to: Int.self, at: column)
    }
    
    /// Maps a single-column result to an array of doubles
    public func mapDoubles(at column: Int = 0) throws -> [Double] {
        return try mapAll(to: Double.self, at: column)
    }
    
    /// Maps a single-column result to an array of booleans
    public func mapBools(at column: Int = 0) throws -> [Bool] {
        return try mapAll(to: Bool.self, at: column)
    }
}