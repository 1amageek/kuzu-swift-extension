import Foundation

struct DDLGenerator {
    func generateNodeTableDDL(tableName: String, properties: [PropertyInfo]) -> [String] {
        var ddl: [String] = []
        
        // Generate CREATE TABLE statement
        var columns: [String] = []
        
        for property in properties {
            let kuzuType = mapSwiftTypeToKuzuType(property)
            var columnDef = "\(property.name) \(kuzuType)"
            
            if property.isID {
                columnDef += " PRIMARY KEY"
            }
            
            if !property.isOptional && !property.isID {
                columnDef += " NOT NULL"
            }
            
            if property.hasDefaultNow {
                columnDef += " DEFAULT now()"
            }
            
            columns.append(columnDef)
        }
        
        let createTable = "CREATE NODE TABLE \(tableName) (\(columns.joined(separator: ", ")))"
        ddl.append(createTable)
        
        // Generate index statements
        for property in properties {
            if property.isIndex || property.isUniqueIndex {
                let indexType = property.isUniqueIndex ? "UNIQUE" : ""
                let indexName = "\(tableName)_\(property.name)_idx"
                ddl.append("CREATE \(indexType) INDEX \(indexName) ON \(tableName)(\(property.name))")
            }
            
            if property.isVector {
                let indexName = "\(tableName)_\(property.name)_vector_idx"
                ddl.append("CREATE VECTOR INDEX \(indexName) ON \(tableName)(\(property.name)) USING HNSW")
            }
            
            if property.isFTS {
                let indexName = "\(tableName)_\(property.name)_fts_idx"
                ddl.append("CREATE FTS INDEX \(indexName) ON \(tableName)(\(property.name))")
            }
        }
        
        return ddl
    }
    
    func generateEdgeTableDDL(tableName: String, fromType: String, toType: String, properties: [PropertyInfo]) -> [String] {
        var ddl: [String] = []
        
        // Generate CREATE REL TABLE statement
        var columns: [String] = []
        
        for property in properties {
            let kuzuType = mapSwiftTypeToKuzuType(property)
            var columnDef = "\(property.name) \(kuzuType)"
            
            if !property.isOptional {
                columnDef += " NOT NULL"
            }
            
            if property.hasDefaultNow {
                columnDef += " DEFAULT now()"
            }
            
            columns.append(columnDef)
        }
        
        var createTable = "CREATE REL TABLE \(tableName)(FROM \(fromType) TO \(toType)"
        if !columns.isEmpty {
            createTable += ", \(columns.joined(separator: ", "))"
        } else {
            createTable += ")"
        }
        
        ddl.append(createTable)
        
        // Generate index statements for edge properties
        for property in properties {
            if property.isIndex || property.isUniqueIndex {
                let indexType = property.isUniqueIndex ? "UNIQUE" : ""
                let indexName = "\(tableName)_\(property.name)_idx"
                ddl.append("CREATE \(indexType) INDEX \(indexName) ON \(tableName)(\(property.name))")
            }
        }
        
        return ddl
    }
    
    func generateColumnMeta(properties: [PropertyInfo]) -> String {
        let columns = properties.map { property in
            var modifiers: [String] = []
            
            if property.isID {
                modifiers.append("PRIMARY KEY")
            }
            if !property.isOptional && !property.isID {
                modifiers.append("NOT NULL")
            }
            if property.hasDefaultNow {
                modifiers.append("DEFAULT now()")
            }
            
            let modifiersString = modifiers.map { "\"\($0)\"" }.joined(separator: ", ")
            
            return """
            ColumnMeta(
                name: "\(property.name)",
                kuzuType: "\(mapSwiftTypeToKuzuType(property))",
                modifiers: [\(modifiersString)]
            )
            """
        }
        
        return "[\(columns.joined(separator: ", "))]"
    }
    
    private func mapSwiftTypeToKuzuType(_ property: PropertyInfo) -> String {
        let baseType = property.type
        
        switch baseType {
        case "Int", "Int32":
            return "INT32"
        case "Int64":
            return "INT64"
        case "Int16":
            return "INT16"
        case "Int8":
            return "INT8"
        case "UInt", "UInt32":
            return "UINT32"
        case "UInt64":
            return "UINT64"
        case "UInt16":
            return "UINT16"
        case "UInt8":
            return "UINT8"
        case "Float":
            return property.isVector ? "FLOAT[\(property.vectorDimensions ?? 0)]" : "FLOAT"
        case "Double":
            return property.isVector ? "DOUBLE[\(property.vectorDimensions ?? 0)]" : "DOUBLE"
        case "String":
            return "STRING"
        case "Bool":
            return "BOOLEAN"
        case "Date":
            return property.isTimestamp ? "TIMESTAMP" : "DATE"
        case "UUID":
            return "UUID"
        case "[Float]":
            return property.isVector ? "FLOAT[\(property.vectorDimensions ?? 0)]" : "FLOAT[]"
        case "[Double]":
            return property.isVector ? "DOUBLE[\(property.vectorDimensions ?? 0)]" : "DOUBLE[]"
        case "[Int]", "[Int32]":
            return "INT32[]"
        case "[Int64]":
            return "INT64[]"
        case "[String]":
            return "STRING[]"
        default:
            // For custom types, assume they will be serialized as JSON
            return "STRING"
        }
    }
}