import Foundation

/// Internal utilities for macro implementations
internal struct MacroUtilities {
    /// Maps Swift types to Kuzu DDL types
    static func mapSwiftTypeToKuzuType(_ swiftType: String) -> String {
        let typeMapping: [String: String] = [
            "String": "STRING",
            "String?": "STRING",
            "Int": "INT64",
            "Int?": "INT64",
            "Int32": "INT32",
            "Int32?": "INT32",
            "Int64": "INT64",
            "Int64?": "INT64",
            "Double": "DOUBLE",
            "Double?": "DOUBLE",
            "Float": "FLOAT",
            "Float?": "FLOAT",
            "Bool": "BOOLEAN",
            "Bool?": "BOOLEAN",
            "Date": "TIMESTAMP",
            "Date?": "TIMESTAMP",
            "UUID": "STRING",
            "UUID?": "STRING",
            "Data": "BLOB",
            "Data?": "BLOB",
            "[String]": "STRING[]",
            "[Int]": "INT64[]",
            "[Double]": "DOUBLE[]",
            "[Float]": "FLOAT[]"
        ]
        
        return typeMapping[swiftType] ?? "STRING"
    }
}