import Foundation
import Kuzu

/// Utility for mapping QueryResult to Swift types
public struct ResultMapper {
    
    /// Maps a single value from the first row
    public static func value<T>(_ result: QueryResult, at column: Int = 0) throws -> T {
        guard result.hasNext() else {
            throw ResultMappingError.noResults
        }
        
        guard let flatTuple = try result.getNext() else {
            throw ResultMappingError.noResults
        }
        
        // Check column bounds
        let columnCount = Int(result.getColumnCount())
        guard column < columnCount else {
            throw ResultMappingError.columnIndexOutOfBounds(index: column, columnCount: columnCount)
        }
        
        let value = try flatTuple.getValue(UInt64(column))
        
        // Check for null values on non-optional types
        guard let value = value else {
            let columnNames = result.getColumnNames()
            let fieldName = column < columnNames.count ? columnNames[column] : "column_\(column)"
            throw ResultMappingError.nullValueForNonOptionalType(
                field: fieldName,
                type: String(describing: T.self)
            )
        }
        
        return try cast(value, to: T.self, field: column < result.getColumnNames().count ? result.getColumnNames()[column] : nil)
    }
    
    /// Maps a single optional value from the first row
    public static func optionalValue<T>(_ result: QueryResult, at column: Int = 0) throws -> T? {
        guard result.hasNext() else {
            return nil
        }
        
        guard let flatTuple = try result.getNext() else {
            return nil
        }
        
        // Check column bounds
        let columnCount = Int(result.getColumnCount())
        guard column < columnCount else {
            throw ResultMappingError.columnIndexOutOfBounds(index: column, columnCount: columnCount)
        }
        
        let value = try flatTuple.getValue(UInt64(column))
        guard let value = value else {
            return nil
        }
        
        let columnNames = result.getColumnNames()
        let fieldName = column < columnNames.count ? columnNames[column] : nil
        return try cast(value, to: T.self, field: fieldName)
    }
    
    /// Maps all values from a column as an array
    /// - Warning: This method consumes the QueryResult iterator. Subsequent calls will return empty results.
    /// - Note: QueryResult can only be iterated once. Store the results if you need to access them multiple times.
    public static func column<T>(_ result: QueryResult, at column: Int = 0) throws -> [T] {
        var values: [T] = []
        let columnNames = result.getColumnNames()
        let fieldName = column < columnNames.count ? columnNames[column] : nil
        
        // Check column bounds early
        let columnCount = Int(result.getColumnCount())
        guard column < columnCount else {
            throw ResultMappingError.columnIndexOutOfBounds(index: column, columnCount: columnCount)
        }
        
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
        // Direct casting for most types
        if let casted = value as? T {
            return casted
        }
        
        // Special handling for type conversions
        switch (value, type) {
        // Date conversions
        case (let double as Double, is Date.Type):
            return Date(timeIntervalSince1970: double) as! T
        case (let int as Int, is Date.Type):
            return Date(timeIntervalSince1970: Double(int)) as! T
        case (let int64 as Int64, is Date.Type):
            return Date(timeIntervalSince1970: Double(int64)) as! T
        case (let string as String, is Date.Type):
            // Try to parse ISO8601 date string
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) {
                return date as! T
            }
            
        // UUID conversions
        case (let string as String, is UUID.Type):
            if let uuid = UUID(uuidString: string) {
                return uuid as! T
            }
            
        // Numeric conversions
        case (let int as Int, is Int64.Type):
            return Int64(int) as! T
        case (let int64 as Int64, is Int.Type):
            return Int(int64) as! T
        case (let int as Int, is Double.Type):
            return Double(int) as! T
        case (let float as Float, is Double.Type):
            return Double(float) as! T
        case (let double as Double, is Float.Type):
            return Float(double) as! T
        case (let int as Int, is Float.Type):
            return Float(int) as! T
        case (let int64 as Int64, is Float.Type):
            return Float(int64) as! T
            
        // String conversions
        case (_, is String.Type):
            return String(describing: value) as! T
            
        // NSNull handling
        case (is NSNull, _):
            throw ResultMappingError.nullValueForNonOptionalType(
                field: field ?? "unknown",
                type: String(describing: T.self)
            )
            
        default:
            break
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
                // Convert value to dictionary for decoding
                if let dict = value as? [String: Any?] {
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
            // Convert value to dictionary for decoding
            if let dict = value as? [String: Any?] {
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