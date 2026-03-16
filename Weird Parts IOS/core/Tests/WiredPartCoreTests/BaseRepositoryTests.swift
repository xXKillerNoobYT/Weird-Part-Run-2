import Testing
import GRDB
@testable import WiredPartCore

@Suite("BaseRepository Tests")
struct BaseRepositoryTests {

    private func freshDB() throws -> AppDatabase {
        try AppDatabase.openInMemoryDatabase()
    }

    // MARK: - Insert

    @Test("insert creates record and returns ID")
    func testInsert() throws {
        let db = try freshDB()
        let repo = BaseRepository(db: db, tableName: "users")

        let id = try repo.insert([
            "display_name": "Alice".databaseValue,
            "pin_hash": "fakehash".databaseValue,
            "is_active": 1.databaseValue,
        ], track: false)

        #expect(id > 0)
    }

    @Test("insert with tracking creates change log entry")
    func testInsertWithTracking() throws {
        let db = try freshDB()
        let repo = BaseRepository(db: db, tableName: "users")

        let id = try repo.insert([
            "display_name": "Bob".databaseValue,
            "pin_hash": "fakehash".databaseValue,
            "is_active": 1.databaseValue,
        ], track: true, deviceId: "test-device")

        let changes = try ChangeTracker.getPendingChanges(db: db)
        #expect(changes.count == 1)
        #expect(changes[0].tableName == "users")
        #expect(changes[0].recordId == id)
        #expect(changes[0].operation == "INSERT")
    }

    @Test("insert with null values")
    func testInsertNulls() throws {
        let db = try freshDB()
        let repo = BaseRepository(db: db, tableName: "users")

        let id = try repo.insert([
            "display_name": "Charlie".databaseValue,
            "pin_hash": "fakehash".databaseValue,
            "email": DatabaseValue.null,
            "is_active": 1.databaseValue,
        ], track: false)

        let row = try repo.getById(id)
        #expect(row != nil)
        // email should be NULL
        let email: String? = row?["email"]
        #expect(email == nil)
    }

    // MARK: - GetById

    @Test("getById returns record")
    func testGetById() throws {
        let db = try freshDB()
        let repo = BaseRepository(db: db, tableName: "users")

        let id = try repo.insert([
            "display_name": "Alice".databaseValue,
            "pin_hash": "fakehash".databaseValue,
            "is_active": 1.databaseValue,
        ], track: false)

        let row = try repo.getById(id)
        #expect(row != nil)
        let name: String = row!["display_name"]
        #expect(name == "Alice")
    }

    @Test("getById returns nil for non-existent ID")
    func testGetByIdMissing() throws {
        let db = try freshDB()
        let repo = BaseRepository(db: db, tableName: "users")

        let row = try repo.getById(9999)
        #expect(row == nil)
    }

    // MARK: - FindAll

    @Test("findAll returns all records")
    func testFindAll() throws {
        let db = try freshDB()
        let repo = BaseRepository(db: db, tableName: "users")

        for i in 1...3 {
            try repo.insert([
                "display_name": "User \(i)".databaseValue,
                "pin_hash": "hash\(i)".databaseValue,
                "is_active": 1.databaseValue,
            ], track: false)
        }

        let rows = try repo.findAll()
        #expect(rows.count == 3)
    }

    @Test("findAll with WHERE clause")
    func testFindAllWhere() throws {
        let db = try freshDB()
        let repo = BaseRepository(db: db, tableName: "users")

        try repo.insert(["display_name": "Active".databaseValue, "pin_hash": "hash1".databaseValue, "is_active": 1.databaseValue], track: false)
        try repo.insert(["display_name": "Inactive".databaseValue, "pin_hash": "hash2".databaseValue, "is_active": 0.databaseValue], track: false)

        let active = try repo.findAll(where: "is_active = ?", params: [1])
        #expect(active.count == 1)
        let name: String = active[0]["display_name"]
        #expect(name == "Active")
    }

    @Test("findAll with orderBy, limit, offset")
    func testFindAllPagination() throws {
        let db = try freshDB()
        let repo = BaseRepository(db: db, tableName: "users")

        for i in 1...5 {
            try repo.insert([
                "display_name": "User \(i)".databaseValue,
                "pin_hash": "hash\(i)".databaseValue,
                "is_active": 1.databaseValue,
            ], track: false)
        }

        let page = try repo.findAll(orderBy: "id ASC", limit: 2, offset: 2)
        #expect(page.count == 2)
    }

    // MARK: - Count

    @Test("count returns correct total")
    func testCount() throws {
        let db = try freshDB()
        let repo = BaseRepository(db: db, tableName: "users")

        for i in 1...4 {
            try repo.insert([
                "display_name": "User \(i)".databaseValue,
                "pin_hash": "hash\(i)".databaseValue,
                "is_active": (i <= 2 ? 1 : 0).databaseValue,
            ], track: false)
        }

        let total = try repo.count()
        #expect(total == 4)

        let activeCount = try repo.count(where: "is_active = ?", params: [1])
        #expect(activeCount == 2)
    }

    // MARK: - Update

    @Test("update modifies record")
    func testUpdate() throws {
        let db = try freshDB()
        let repo = BaseRepository(db: db, tableName: "users")

        let id = try repo.insert([
            "display_name": "Before".databaseValue,
            "pin_hash": "fakehash".databaseValue,
            "is_active": 1.databaseValue,
        ], track: false)

        let changed = try repo.update(id, data: [
            "display_name": "After".databaseValue,
        ], track: false)

        #expect(changed)

        let row = try repo.getById(id)
        let name: String = row!["display_name"]
        #expect(name == "After")
    }

    @Test("update with tracking creates change log with old values")
    func testUpdateWithTracking() throws {
        let db = try freshDB()
        let repo = BaseRepository(db: db, tableName: "users")

        let id = try repo.insert([
            "display_name": "Original".databaseValue,
            "pin_hash": "fakehash".databaseValue,
            "email": "old@test.com".databaseValue,
            "is_active": 1.databaseValue,
        ], track: false)

        _ = try repo.update(id, data: [
            "email": "new@test.com".databaseValue,
        ], track: true, deviceId: "test-device")

        let changes = try ChangeTracker.getPendingChanges(db: db)
        #expect(changes.count == 1)
        #expect(changes[0].operation == "UPDATE")
    }

    @Test("update with empty data returns false")
    func testUpdateEmpty() throws {
        let db = try freshDB()
        let repo = BaseRepository(db: db, tableName: "users")

        let id = try repo.insert([
            "display_name": "Test".databaseValue,
            "pin_hash": "fakehash".databaseValue,
            "is_active": 1.databaseValue,
        ], track: false)

        let changed = try repo.update(id, data: [:], track: false)
        #expect(!changed)
    }

    // MARK: - Delete

    @Test("delete removes record")
    func testDelete() throws {
        let db = try freshDB()
        let repo = BaseRepository(db: db, tableName: "users")

        let id = try repo.insert([
            "display_name": "ToDelete".databaseValue,
            "pin_hash": "fakehash".databaseValue,
            "is_active": 1.databaseValue,
        ], track: false)

        let deleted = try repo.delete(id, track: false)
        #expect(deleted)

        let row = try repo.getById(id)
        #expect(row == nil)
    }

    @Test("delete with tracking creates change log")
    func testDeleteWithTracking() throws {
        let db = try freshDB()
        let repo = BaseRepository(db: db, tableName: "users")

        let id = try repo.insert([
            "display_name": "WillBeDeleted".databaseValue,
            "pin_hash": "fakehash".databaseValue,
            "is_active": 1.databaseValue,
        ], track: false)

        _ = try repo.delete(id, track: true, deviceId: "test-device")

        let changes = try ChangeTracker.getPendingChanges(db: db)
        #expect(changes.count == 1)
        #expect(changes[0].operation == "DELETE")
        #expect(changes[0].recordId == id)
    }

    @Test("delete non-existent record returns false")
    func testDeleteMissing() throws {
        let db = try freshDB()
        let repo = BaseRepository(db: db, tableName: "users")

        let deleted = try repo.delete(9999, track: false)
        #expect(!deleted)
    }

    // MARK: - Raw Queries

    @Test("rawQuery executes custom SQL")
    func testRawQuery() throws {
        let db = try freshDB()
        let repo = BaseRepository(db: db, tableName: "users")

        try repo.insert(["display_name": "RawTest".databaseValue, "pin_hash": "hash".databaseValue, "is_active": 1.databaseValue], track: false)

        let rows = try repo.rawQuery("SELECT display_name FROM users WHERE is_active = 1")
        #expect(rows.count == 1)
        let name: String = rows[0]["display_name"]
        #expect(name == "RawTest")
    }

    @Test("rawRun executes custom write SQL")
    func testRawRun() throws {
        let db = try freshDB()
        let repo = BaseRepository(db: db, tableName: "users")

        try repo.insert(["display_name": "Before".databaseValue, "pin_hash": "hash".databaseValue, "is_active": 1.databaseValue], track: false)

        let changed = try repo.rawRun(
            "UPDATE users SET display_name = 'After' WHERE display_name = 'Before'"
        )
        #expect(changed == 1)
    }
}
