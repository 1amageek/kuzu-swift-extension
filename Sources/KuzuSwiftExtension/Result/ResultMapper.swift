import Foundation
import Kuzu
import Algorithms

/// Provides convenient mapping and transformation methods for query results
extension QueryResult {
    
    // MARK: - Basic Mapping
    
    /// Maps the result to an array of dictionaries
    public func mapRows() throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        let columnNames = getColumnNames()
        
        while hasNext() {
            guard let tuple = try getNext() else { break }
            var row: [String: Any] = [:]
            
            for (index, columnName) in columnNames.enumerated() {
                guard let value = try tuple.getValue(UInt64(index)) else {
                    row[columnName] = NSNull()
                    continue
                }

                // KuzuNode handling: when a node is returned, use its properties
                if let node = value as? KuzuNode {
                    row[columnName] = node.properties
                } else {
                    row[columnName] = try decodeValue(value)
                }
            }
            
            rows.append(row)
        }
        
        return rows
    }
    
    /// Maps the first row to a dictionary
    public func mapFirst() throws -> [String: Any]? {
        guard hasNext() else { return nil }
        
        guard let tuple = try getNext() else {
            throw GraphError.invalidOperation(message: "Failed to get next tuple")
        }
        let columnNames = getColumnNames()
        var row: [String: Any] = [:]
        
        for (index, columnName) in columnNames.enumerated() {
            let value = try tuple.getValue(UInt64(index))
            
            // KuzuNode handling: when a node is returned, use its properties
            if let node = value as? KuzuNode {
                row[columnName] = node.properties
            } else {
                row[columnName] = try decodeValue(value)
            }
        }
        
        return row
    }
    
    /// Maps the first row to a specific type at a given column index (required version)
    public func mapFirstRequired<T>(to type: T.Type, at columnIndex: Int) throws -> T {
        guard hasNext() else {
            throw GraphError.invalidOperation(message: "No rows returned from query")
        }
        
        guard let tuple = try getNext() else {
            throw GraphError.invalidOperation(message: "Failed to get next tuple")
        }
        let value = try decodeValue(tuple.getValue(UInt64(columnIndex)))
        return try castValue(value, to: type)
    }
    
    // MARK: - Type-Safe Mapping
    
    /// Maps rows to a specific Decodable type
    public func map<T: Decodable>(to type: T.Type) throws -> [T] {
        var results: [T] = []
        let decoder = KuzuDecoder()
        let columnNames = getColumnNames()
        
        while hasNext() {
            guard let tuple = try getNext() else { break }
            
            // Special handling for single column with KuzuNode
            if columnNames.count == 1 {
                let value = try tuple.getValue(0)
                if let node = value as? KuzuNode {
                    // Decode directly from node properties
                    let decoded = try decoder.decode(type, from: node.properties)
                    results.append(decoded)
                    continue
                }
            }
            
            // Standard processing: build dictionary from row
            var row: [String: Any] = [:]
            for (index, columnName) in columnNames.enumerated() {
                guard let value = try tuple.getValue(UInt64(index)) else {
                    row[columnName] = NSNull()
                    continue
                }

                // KuzuNode handling: when a node is returned, use its properties
                if let node = value as? KuzuNode {
                    row[columnName] = node.properties
                } else {
                    row[columnName] = try decodeValue(value)
                }
            }
            
            let decoded = try decoder.decode(type, from: row)
            results.append(decoded)
        }
        
        return results
    }
    
    /// Maps the first row to a specific Decodable type
    public func mapFirst<T: Decodable>(to type: T.Type) throws -> T? {
        guard hasNext() else { return nil }
        
        guard let tuple = try getNext() else { return nil }
        let decoder = KuzuDecoder()
        let columnNames = getColumnNames()
        
        // Special handling for single column with KuzuNode
        if columnNames.count == 1 {
            let value = try tuple.getValue(0)
            if let node = value as? KuzuNode {
                // Decode directly from node properties
                return try decoder.decode(type, from: node.properties)
            }
        }
        
        // Standard processing: build dictionary from row
        var row: [String: Any] = [:]
        for (index, columnName) in columnNames.enumerated() {
            let value = try tuple.getValue(UInt64(index))
            
            // KuzuNode handling: when a node is returned, use its properties
            if let node = value as? KuzuNode {
                row[columnName] = node.properties
            } else {
                row[columnName] = try decodeValue(value)
            }
        }
        
        return try decoder.decode(type, from: row)
    }
    
    // MARK: - Column Extraction
    
    /// Extracts values from a specific column
    public func column<T>(_ name: String, as type: T.Type) throws -> [T] {
        let rows = try mapRows()
        
        // Use swift-algorithms compactMap for efficient extraction
        return try rows.compactMap { row in
            guard let value = row[name] else { return nil }
            return try castValue(value, to: type)
        }
    }
    
    /// Extracts unique values from a specific column using swift-algorithms
    public func uniqueColumn<T: Hashable>(_ name: String, as type: T.Type) throws -> Set<T> {
        let rows = try mapRows()
        
        // Use swift-algorithms uniqued() for efficient unique extraction
        let values = try rows.compactMap { row -> T? in
            guard let value = row[name] else { return nil }
            return try castValue(value, to: type)
        }
        
        return Set(values.uniqued())
    }
    
    // MARK: - Aggregation
    
    /// Count rows
    public func count() throws -> Int {
        return try mapRows().count
    }
    
    /// Groups rows by a key using swift-algorithms
    public func grouped<Key: Hashable>(by keyPath: String, as keyType: Key.Type) throws -> [Key: [[String: Any]]] {
        let rows = try mapRows()
        
        // Use swift-algorithms' grouped(by:) for efficient grouping
        return Dictionary(grouping: rows) { row in
            try? castValue(row[keyPath], to: keyType)
        }.compactMapKeys { $0 }
    }
    
    /// Groups and aggregates using swift-algorithms
    public func groupedAndAggregated<Key: Hashable, Value>(
        by keyPath: String,
        as keyType: Key.Type,
        aggregate: String,
        with aggregator: ([Any]) -> Value
    ) throws -> [Key: Value] {
        let rows = try mapRows()
        
        // Use swift-algorithms for efficient grouping and aggregation
        let grouped = Dictionary(grouping: rows) { row -> Key? in
            try? castValue(row[keyPath], to: keyType)
        }.compactMapKeys { $0 }
        
        return grouped.mapValues { group in
            let values = group.compactMap { $0[aggregate] }
            return aggregator(values)
        }
    }
    
    // MARK: - Advanced Operations with swift-algorithms
    
    /// Finds the first row matching a predicate using swift-algorithms
    public func first(where predicate: ([String: Any]) throws -> Bool) throws -> [String: Any]? {
        let rows = try mapRows()
        return try rows.first(where: predicate)
    }
    
    /// Finds all rows matching a predicate with limit using swift-algorithms
    public func prefix(while predicate: ([String: Any]) throws -> Bool) throws -> [[String: Any]] {
        let rows = try mapRows()
        return try Array(rows.prefix(while: predicate))
    }
    
    /// Takes first n rows using swift-algorithms
    public func prefix(_ maxLength: Int) throws -> [[String: Any]] {
        let rows = try mapRows()
        return Array(rows.prefix(maxLength))
    }
    
    /// Drops first n rows using swift-algorithms
    public func dropFirst(_ count: Int) throws -> [[String: Any]] {
        let rows = try mapRows()
        return Array(rows.dropFirst(count))
    }
    
    /// Chunks rows into batches using swift-algorithms
    public func chunked(by size: Int) throws -> [[[String: Any]]] {
        let rows = try mapRows()
        return rows.chunks(ofCount: size).map(Array.init)
    }
    
    /// Returns rows in sliding windows using swift-algorithms
    public func windows(ofCount count: Int) throws -> [[[String: Any]]] {
        let rows = try mapRows()
        return rows.windows(ofCount: count).map(Array.init)
    }
    
    /// Combines two result sets using swift-algorithms
    public func zip<T>(with other: [T]) throws -> [(row: [String: Any], item: T)] {
        let rows = try mapRows()
        return Array(Swift.zip(rows, other))
    }
    
    /// Finds unique adjacent rows using swift-algorithms
    public func uniquedAdjacent(by keyPath: String) throws -> [[String: Any]] {
        let rows = try mapRows()
        return rows.uniqued(on: { $0[keyPath] as? AnyHashable })
    }
    
    /// Partitions rows based on a predicate using swift-algorithms
    public func partitioned(by predicate: ([String: Any]) throws -> Bool) throws -> (matching: [[String: Any]], notMatching: [[String: Any]]) {
        let rows = try mapRows()
        
        var matching: [[String: Any]] = []
        var notMatching: [[String: Any]] = []
        
        for row in rows {
            if try predicate(row) {
                matching.append(row)
            } else {
                notMatching.append(row)
            }
        }
        
        return (matching, notMatching)
    }
    
    /// Returns combinations of rows using swift-algorithms
    public func combinations(ofCount count: Int) throws -> [[[String: Any]]] {
        let rows = try mapRows()
        return rows.combinations(ofCount: count).map(Array.init)
    }
    
    /// Returns permutations of rows using swift-algorithms
    public func permutations(ofCount count: Int? = nil) throws -> [[[String: Any]]] {
        let rows = try mapRows()
        if let count = count {
            return rows.permutations(ofCount: count).map(Array.init)
        } else {
            return rows.permutations().map(Array.init)
        }
    }
    
    // MARK: - Statistical Operations with swift-algorithms
    
    /// Calculates min/max for a numeric column using swift-algorithms
    public func minMax<T: Comparable>(for column: String, as type: T.Type) throws -> (min: T, max: T)? {
        let values = try self.column(column, as: type)
        guard !values.isEmpty else { return nil }
        
        // Use swift-algorithms minAndMax for efficiency
        if let result = values.minAndMax() {
            return (min: result.min, max: result.max)
        }
        return nil
    }
    
    /// Samples random rows using swift-algorithms
    public func randomSample(count: Int) throws -> [[String: Any]] {
        let rows = try mapRows()
        return Array(rows.randomSample(count: count))
    }
    
    /// Finds adjacent pairs of rows using swift-algorithms
    public func adjacentPairs() throws -> [([String: Any], [String: Any])] {
        let rows = try mapRows()
        return rows.adjacentPairs().map { ($0, $1) }
    }
    
    // MARK: - Transformation Operations
    
    /// Transforms each row with a function
    public func map<T>(_ transform: ([String: Any]) throws -> T) throws -> [T] {
        let rows = try mapRows()
        return try rows.map(transform)
    }
    
    /// Filters rows based on a predicate
    public func filter(_ predicate: ([String: Any]) throws -> Bool) throws -> [[String: Any]] {
        let rows = try mapRows()
        return try rows.filter(predicate)
    }
    
    /// Transforms and filters in one operation using swift-algorithms
    public func compactMap<T>(_ transform: ([String: Any]) throws -> T?) throws -> [T] {
        let rows = try mapRows()
        return try rows.compactMap(transform)
    }
    
    /// FlatMaps rows using swift-algorithms
    public func flatMap<T>(_ transform: ([String: Any]) throws -> [T]) throws -> [T] {
        let rows = try mapRows()
        return try rows.flatMap(transform)
    }
    
    /// Reduces rows to a single value using swift-algorithms
    public func reduce<T>(_ initialResult: T, _ nextPartialResult: (T, [String: Any]) throws -> T) throws -> T {
        let rows = try mapRows()
        return try rows.reduce(initialResult, nextPartialResult)
    }
    
    /// Reduces rows into a result using swift-algorithms
    public func reduce<T>(into initialResult: T, _ updateAccumulatingResult: (inout T, [String: Any]) throws -> Void) throws -> T {
        let rows = try mapRows()
        return try rows.reduce(into: initialResult, updateAccumulatingResult)
    }
    
    // MARK: - Convenience Methods
    
    /// Checks if result is empty
    public var isEmpty: Bool {
        return !hasNext()
    }
    
    /// Returns all values as an array of arrays
    public func allValues() throws -> [[Any]] {
        var allRows: [[Any]] = []
        let columnCount = getColumnCount()
        
        while hasNext() {
            guard let tuple = try getNext() else { break }
            var row: [Any] = []
            
            for i in 0..<columnCount {
                row.append(try decodeValue(tuple.getValue(UInt64(i))))
            }
            
            allRows.append(row)
        }
        
        return allRows
    }
    
    // MARK: - Private Helpers
    
    private func decodeValue(_ value: Any) throws -> Any {
        // The value from tuple.getValue() is already decoded by Kuzu
        // We handle arrays and dictionaries recursively
        
        switch value {
        case let v as [Any]:
            return try v.map { try decodeValue($0) }
            
        case let v as [String: Any]:
            return try v.mapValues { try decodeValue($0) }
            
        default:
            // Return the value as-is for all other types
            // This includes primitive types and Kuzu's node/edge types
            return value
        }
    }
    
    private func castValue<T>(_ value: Any?, to type: T.Type) throws -> T {
        guard let value = value else {
            throw GraphError.conversionFailed(from: "nil", to: String(describing: type))
        }
        
        if let result = value as? T {
            return result
        }
        
        // Handle numeric conversions
        if type == Int.self {
            if let intVal = value as? Int64 {
                return Int(intVal) as! T
            }
            if let doubleVal = value as? Double {
                return Int(doubleVal) as! T
            }
        }
        
        if type == Int64.self {
            if let intVal = value as? Int {
                return Int64(intVal) as! T
            }
            if let doubleVal = value as? Double {
                return Int64(doubleVal) as! T
            }
        }
        
        if type == Double.self {
            if let intVal = value as? Int {
                return Double(intVal) as! T
            }
            if let intVal = value as? Int64 {
                return Double(intVal) as! T
            }
            if let floatVal = value as? Float {
                return Double(floatVal) as! T
            }
        }
        
        if type == Float.self {
            if let intVal = value as? Int {
                return Float(intVal) as! T
            }
            if let intVal = value as? Int64 {
                return Float(intVal) as! T
            }
            if let doubleVal = value as? Double {
                return Float(doubleVal) as! T
            }
        }
        
        throw GraphError.conversionFailed(
            from: String(describing: Swift.type(of: value)),
            to: String(describing: type)
        )
    }
}

// MARK: - Dictionary Extensions for swift-algorithms

extension Dictionary {
    /// Compact map keys while preserving values
    func compactMapKeys<T: Hashable>(_ transform: (Key) throws -> T?) rethrows -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            if let newKey = try transform(key) {
                result[newKey] = value
            }
        }
        return result
    }
}
