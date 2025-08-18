import Testing
@testable import KuzuSwiftExtension
import Kuzu

struct ParameterPackTests {
    
    @Test("TupleQuery stores values correctly")
    func tupleQueryStructure() throws {
        // Test that TupleQuery properly stores values
        
        // TupleQuery is a simple container
        let tuple1 = TupleQuery("test")
        #expect(tuple1.value == "test")
        
        let tuple2 = TupleQuery((1, 2, 3))
        #expect(tuple2.value.0 == 1)
        #expect(tuple2.value.1 == 2)
        #expect(tuple2.value.2 == 3)
        
        // The real power comes from QueryBuilder creating TupleQuery with parameter packs
    }
    
    @Test("QueryBuilder creates TupleQuery with parameter packs")
    func queryBuilderWithParameterPacks() throws {
        // Test that QueryBuilder properly creates TupleQuery with parameter packs
        
        struct TestComponent: QueryComponent {
            typealias Result = String
            let id: Int
            func toCypher() throws -> CypherFragment {
                CypherFragment(query: "MATCH (n:Node\(id))")
            }
        }
        
        // Test with @QueryBuilder
        @QueryBuilder
        func buildQuery() -> some QueryComponent {
            TestComponent(id: 1)
            TestComponent(id: 2)
            TestComponent(id: 3)
        }
        
        let query = buildQuery()
        let cypher = try query.toCypher()
        
        #expect(cypher.query.contains("MATCH (n:Node1)"))
        #expect(cypher.query.contains("MATCH (n:Node2)"))
        #expect(cypher.query.contains("MATCH (n:Node3)"))
    }
    
    @Test("TupleQuery with 2 components")
    func tupleQuery2Components() throws {
        struct Component1: QueryComponent {
            typealias Result = Int
            func toCypher() throws -> CypherFragment {
                CypherFragment(query: "MATCH (a:A)")
            }
        }
        
        struct Component2: QueryComponent {
            typealias Result = String
            func toCypher() throws -> CypherFragment {
                CypherFragment(query: "MATCH (b:B)")
            }
        }
        
        // With parameter packs, we pass components individually, not as a tuple
        let tuple = TupleQuery(Component1(), Component2())
        let cypher = try tuple.toCypher()
        
        #expect(cypher.query.contains("MATCH (a:A)"))
        #expect(cypher.query.contains("MATCH (b:B)"))
    }
    
    @Test("TupleQuery with 3 components")
    func tupleQuery3Components() throws {
        struct Component1: QueryComponent {
            typealias Result = Int
            func toCypher() throws -> CypherFragment {
                CypherFragment(query: "MATCH (a:A)")
            }
        }
        
        struct Component2: QueryComponent {
            typealias Result = String
            func toCypher() throws -> CypherFragment {
                CypherFragment(query: "MATCH (b:B)")
            }
        }
        
        struct Component3: QueryComponent {
            typealias Result = Bool
            func toCypher() throws -> CypherFragment {
                CypherFragment(query: "MATCH (c:C)")
            }
        }
        
        // With parameter packs, we pass components individually, not as a tuple
        let tuple = TupleQuery(Component1(), Component2(), Component3())
        let cypher = try tuple.toCypher()
        
        #expect(cypher.query.contains("MATCH (a:A)"))
        #expect(cypher.query.contains("MATCH (b:B)"))
        #expect(cypher.query.contains("MATCH (c:C)"))
    }
}