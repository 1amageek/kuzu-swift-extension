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
        // Try using ValueConverter first
        if let converted = ValueConverter.fromKuzuValue(value, to: type) {
            return converted
        }
        
        // Fallback to direct casting
        if let casted = value as? T {
            return casted
        }
        
        // If T is String, convert any value to string
        if T.self == String.self {
            return String(describing: value) as! T
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
    public func mapAll<T>(to type: T.Type, at column: Int = 0) throws -> [T] {
        return try ResultMapper.column(self, at: column)
    }
    
    /// Maps results to an array of dictionaries
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
    
    /// Counts the number of results (consumes the iterator)
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