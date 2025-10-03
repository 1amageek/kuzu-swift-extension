import Testing
import Foundation
import Kuzu

@Suite("Database Reopen Raw Query Tests")
struct DatabaseReopenRawQueryTests {

    /// Helper to list directory contents recursively
    func listDirectoryContents(at path: String, indent: String = "") {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)

        if !exists {
            print("\(indent)❌ Path does not exist: \(path)")
            return
        }

        if isDirectory.boolValue {
            print("\(indent)📁 Directory: \(path)")
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: path) {
                for item in contents.sorted() {
                    let itemPath = (path as NSString).appendingPathComponent(item)
                    listDirectoryContents(at: itemPath, indent: indent + "  ")
                }
            }
        } else {
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            let size = attributes?[.size] as? Int64 ?? 0
            print("\(indent)📄 File: \(path) (size: \(size) bytes)")
        }
    }

    @Test("Raw Query: Database with VectorIndex causes error code 1 on reopen")
    func rawQueryVectorIndexReopen() throws {
        let tempPath = NSTemporaryDirectory() + "raw_vector_\(UUID().uuidString).db"
        defer {
            try? FileManager.default.removeItem(atPath: tempPath)
        }

        print("\n========== FIRST LAUNCH (WITH VECTOR INDEX) ==========")
        print("📍 Database path: \(tempPath)")

        // Check initial state
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: tempPath) {
            print("⚠️  Database path already exists!")
        } else {
            print("ℹ️  Database path does not exist - Kuzu will create it")
        }

        // First launch: Create database with vector index
        do {
            let systemConfig = SystemConfig()
            let database = try Database(tempPath, systemConfig)
            let connection = try Connection(database)

            print("✅ Database opened successfully")

            // Create table with vector column
            let createTableQuery = """
            CREATE NODE TABLE VectorNode(
                id STRING PRIMARY KEY,
                embedding FLOAT[3]
            )
            """
            _ = try connection.query(createTableQuery)
            print("✅ Table created successfully")

            // Create vector index
            let createIndexQuery = """
            CALL CREATE_VECTOR_INDEX(
                'VectorNode',
                'embedding_idx',
                'embedding',
                metric := 'l2'
            )
            """
            _ = try connection.query(createIndexQuery)
            print("✅ Vector index created successfully")

            // Insert data
            let insertQuery = """
            CREATE (n:VectorNode {id: 'test1', embedding: CAST([1.0, 2.0, 3.0] AS FLOAT[3])})
            """
            _ = try connection.query(insertQuery)
            print("✅ Data inserted successfully")

            // Verify data
            let result = try connection.query("MATCH (n:VectorNode) RETURN count(n) AS count")
            if result.hasNext(), let tuple = try result.getNext(), let count = try tuple.getValue(0) as? Int64 {
                print("📊 Found \(count) nodes in database")
            }
        }

        // Analyze file structure after first launch
        print("\n📊 File structure after FIRST launch:")
        listDirectoryContents(at: tempPath)

        let exists = FileManager.default.fileExists(atPath: tempPath, isDirectory: &isDirectory)
        if exists {
            if isDirectory.boolValue {
                print("\n✅ Kuzu created a DIRECTORY (expected)")
            } else {
                print("\n❌ Kuzu created a FILE (unexpected - this causes error code 1)")
            }
        }

        print("\n========== SECOND LAUNCH (REOPEN) ==========")
        print("📍 Attempting to reopen database at: \(tempPath)")

        // Second launch: Reopen database - this should fail with error code 1
        do {
            let systemConfig = SystemConfig()
            let database = try Database(tempPath, systemConfig)
            let connection = try Connection(database)

            print("✅ Database reopened successfully (NO ERROR!)")

            // Verify data persisted
            let result = try connection.query("MATCH (n:VectorNode) RETURN count(n) AS count")
            if result.hasNext(), let tuple = try result.getNext(), let count = try tuple.getValue(0) as? Int64 {
                print("📊 Found \(count) nodes in reopened database")
            }
        } catch {
            print("❌ Database reopen FAILED")
            print("   Error: \(error)")
            print("   Error description: \(error.localizedDescription)")

            // Check error type
            if let kuzuError = error as NSError? {
                print("   Error domain: \(kuzuError.domain)")
                print("   Error code: \(kuzuError.code)")
            }

            // Analyze file structure when error occurs
            print("\n📊 File structure when ERROR occurred:")
            listDirectoryContents(at: tempPath)

            throw error
        }
    }

    @Test("Raw Query: Database WITHOUT VectorIndex - should work fine")
    func rawQuerySimpleNodeReopen() throws {
        let tempPath = NSTemporaryDirectory() + "raw_simple_\(UUID().uuidString).db"
        defer {
            try? FileManager.default.removeItem(atPath: tempPath)
        }

        print("\n========== FIRST LAUNCH (NO VECTOR INDEX) ==========")
        print("📍 Database path: \(tempPath)")

        // First launch: Create database WITHOUT vector index
        do {
            let systemConfig = SystemConfig()
            let database = try Database(tempPath, systemConfig)
            let connection = try Connection(database)

            print("✅ Database opened successfully")

            // Create simple table
            let createTableQuery = """
            CREATE NODE TABLE SimpleNode(
                id STRING PRIMARY KEY,
                value STRING
            )
            """
            _ = try connection.query(createTableQuery)
            print("✅ Table created successfully")

            // Insert data
            let insertQuery = """
            CREATE (n:SimpleNode {id: 'test1', value: 'hello'})
            """
            _ = try connection.query(insertQuery)
            print("✅ Data inserted successfully")
        }

        // Analyze file structure
        print("\n📊 File structure after FIRST launch (no vector index):")
        listDirectoryContents(at: tempPath)

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: tempPath, isDirectory: &isDirectory)
        if exists {
            if isDirectory.boolValue {
                print("\n✅ Kuzu created a DIRECTORY")
            } else {
                print("\n⚠️ Kuzu created a FILE")
            }
        }

        print("\n========== SECOND LAUNCH (REOPEN WITHOUT VECTOR INDEX) ==========")

        // Second launch: Reopen database
        do {
            let systemConfig = SystemConfig()
            let database = try Database(tempPath, systemConfig)
            let connection = try Connection(database)

            print("✅ Database reopened successfully")

            // Verify data persisted
            let result = try connection.query("MATCH (n:SimpleNode) RETURN count(n) AS count")
            if result.hasNext(), let tuple = try result.getNext(), let count = try tuple.getValue(0) as? Int64 {
                print("📊 Found \(count) nodes in reopened database")
            }
        } catch {
            print("❌ Database reopen FAILED: \(error)")
            throw error
        }
    }

    @Test("Raw Query: Create index AFTER table creation")
    func rawQueryDelayedIndexCreation() throws {
        let tempPath = NSTemporaryDirectory() + "raw_delayed_\(UUID().uuidString).db"
        defer {
            try? FileManager.default.removeItem(atPath: tempPath)
        }

        print("\n========== DELAYED INDEX CREATION TEST ==========")

        // First launch: Create table and insert data WITHOUT index
        do {
            let systemConfig = SystemConfig()
            let database = try Database(tempPath, systemConfig)
            let connection = try Connection(database)

            print("✅ Database opened")

            // Create table
            _ = try connection.query("""
            CREATE NODE TABLE VectorNode(
                id STRING PRIMARY KEY,
                embedding FLOAT[3]
            )
            """)
            print("✅ Table created")

            // Insert data BEFORE creating index
            _ = try connection.query("""
            CREATE (n:VectorNode {id: 'test1', embedding: CAST([1.0, 2.0, 3.0] AS FLOAT[3])})
            """)
            print("✅ Data inserted BEFORE index creation")

            // NOW create the vector index
            _ = try connection.query("""
            CALL CREATE_VECTOR_INDEX(
                'VectorNode',
                'embedding_idx',
                'embedding',
                metric := 'l2'
            )
            """)
            print("✅ Vector index created AFTER data insertion")
        }

        print("\n📊 File structure after delayed index creation:")
        listDirectoryContents(at: tempPath)

        print("\n========== REOPEN AFTER DELAYED INDEX ==========")

        // Reopen
        do {
            let systemConfig = SystemConfig()
            let database = try Database(tempPath, systemConfig)
            let connection = try Connection(database)

            print("✅ Database reopened successfully")

            let result = try connection.query("MATCH (n:VectorNode) RETURN count(n) AS count")
            if result.hasNext(), let tuple = try result.getNext(), let count = try tuple.getValue(0) as? Int64 {
                print("📊 Found \(count) nodes")
            }
        } catch {
            print("❌ Reopen FAILED: \(error)")
            throw error
        }
    }
}
