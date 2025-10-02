import Foundation

public struct GraphSchema {
    public let nodes: [NodeSchema]
    public let edges: [EdgeSchema]
    
    public init(nodes: [NodeSchema] = [], edges: [EdgeSchema] = []) {
        self.nodes = nodes
        self.edges = edges
    }
    
    public static func discover(from types: [any _KuzuGraphModel.Type]) -> GraphSchema {
        var nodes: [NodeSchema] = []
        var edges: [EdgeSchema] = []
        var seenNodeNames = Set<String>()
        var seenEdgeNames = Set<String>()
        
        for type in types {
            let ddl = type._kuzuDDL
            let columns = type._kuzuColumns
            
            if ddl.contains("CREATE NODE TABLE") {
                let name = extractTableName(from: ddl)
                // Skip if already processed (duplicate model)
                guard !seenNodeNames.contains(name) else { continue }
                seenNodeNames.insert(name)
                
                nodes.append(NodeSchema(
                    name: name,
                    columns: columns.map { Column(name: $0.columnName, type: $0.type, constraints: $0.constraints) },
                    ddl: ddl
                ))
            } else if ddl.contains("CREATE REL TABLE") {
                let name = extractTableName(from: ddl)
                // Skip if already processed (duplicate model)
                guard !seenEdgeNames.contains(name) else { continue }
                seenEdgeNames.insert(name)

                let (from, to) = extractRelationship(from: ddl)
                edges.append(EdgeSchema(
                    name: name,
                    from: from,
                    to: to,
                    columns: columns.map { Column(name: $0.columnName, type: $0.type, constraints: $0.constraints) },
                    ddl: ddl
                ))
            }
        }
        
        return GraphSchema(nodes: nodes, edges: edges)
    }
    
    private static func extractTableName(from ddl: String) -> String {
        let pattern = "CREATE (?:NODE|REL) TABLE ([\\w]+)"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: ddl.count)
        
        if let match = regex?.firstMatch(in: ddl, range: range),
           let nameRange = Range(match.range(at: 1), in: ddl) {
            return String(ddl[nameRange])
        }
        
        return ""
    }
    
    private static func extractRelationship(from ddl: String) -> (from: String, to: String) {
        let pattern = "FROM ([\\w]+) TO ([\\w]+)"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: ddl.count)
        
        if let match = regex?.firstMatch(in: ddl, range: range),
           let fromRange = Range(match.range(at: 1), in: ddl),
           let toRange = Range(match.range(at: 2), in: ddl) {
            return (String(ddl[fromRange]), String(ddl[toRange]))
        }
        
        return ("", "")
    }
}

public struct NodeSchema {
    public let name: String
    public let columns: [Column]
    public let ddl: String
}

public struct EdgeSchema {
    public let name: String
    public let from: String
    public let to: String
    public let columns: [Column]
    public let ddl: String
}

public struct Column {
    public let name: String
    public let type: String
    public let constraints: [String]
    
    public var isPrimaryKey: Bool {
        constraints.contains("PRIMARY KEY")
    }
    
    public var isIndexed: Bool {
        constraints.contains("INDEX")
    }
    
    public var isFullTextSearchEnabled: Bool {
        constraints.contains("FTS")
    }
}