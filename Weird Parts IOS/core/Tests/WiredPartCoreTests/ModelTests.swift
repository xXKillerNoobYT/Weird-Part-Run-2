import Testing
import GRDB
@testable import WiredPartCore

@Suite("Model CRUD Tests")
struct ModelTests {

    private func freshDB() throws -> AppDatabase {
        try AppDatabase.openInMemoryDatabase()
    }

    /// Helper: current timestamp string for NOT NULL DEFAULT columns
    private var now: String { "2026-03-14 00:00:00" }

    // MARK: - User Model

    @Test("User insert and fetch round-trip")
    func testUserInsertFetch() throws {
        let db = try freshDB()
        var user = User(
            displayName: "Alice",
            pinHash: "fakehash",
            isActive: 1
        )
        user.email = "alice@test.com"
        user.phone = "555-1234"

        try db.writer.write { dbConn in
            try user.insert(dbConn)
        }
        #expect(user.id != nil)

        let fetched = try db.writer.read { dbConn in
            try User.fetchOne(dbConn, key: user.id!)
        }
        #expect(fetched != nil)
        #expect(fetched?.displayName == "Alice")
        #expect(fetched?.email == "alice@test.com")
        #expect(fetched?.isActive == 1)
    }

    @Test("User update persists changes")
    func testUserUpdate() throws {
        let db = try freshDB()
        var user = User(displayName: "Bob", pinHash: "fakehash", isActive: 1)
        try db.writer.write { dbConn in try user.insert(dbConn) }

        user.email = "bob@test.com"
        try db.writer.write { dbConn in try user.update(dbConn) }

        let fetched = try db.writer.read { dbConn in try User.fetchOne(dbConn, key: user.id!) }
        #expect(fetched?.email == "bob@test.com")
    }

    // MARK: - Setting Model

    @Test("Setting insert and fetch")
    func testSettingInsertFetch() throws {
        let db = try freshDB()
        var setting = Setting(key: "test_key", value: "test_value", category: "general")
        try db.writer.write { dbConn in try setting.insert(dbConn) }
        #expect(setting.id != nil)

        let fetched = try db.writer.read { dbConn in
            try Setting.fetchOne(dbConn, sql: "SELECT * FROM settings WHERE key = ?", arguments: ["test_key"])
        }
        #expect(fetched?.value == "test_value")
        #expect(fetched?.category == "general")
    }

    // MARK: - Hat Model

    @Test("Hat insert and fetch")
    func testHatInsertFetch() throws {
        let db = try freshDB()
        var hat = Hat(name: "TestHat", level: 50, isBuiltin: 0)
        try db.writer.write { dbConn in try hat.insert(dbConn) }
        #expect(hat.id != nil)

        let fetched = try db.writer.read { dbConn in try Hat.fetchOne(dbConn, key: hat.id!) }
        #expect(fetched?.name == "TestHat")
        #expect(fetched?.level == 50)
    }

    // MARK: - Part Model

    @Test("Part insert and fetch round-trip")
    func testPartInsertFetch() throws {
        let db = try freshDB()

        // First create a category (required FK)
        var category = PartCategory(name: "Electrical", sortOrder: 1)
        try db.writer.write { dbConn in try category.insert(dbConn) }

        var part = Part(
            categoryId: category.id!,
            partType: "general",
            name: "Test Part",
            companyCostPrice: 8.50,
            companyMarkupPercent: 20.0
        )
        part.code = "P-001"
        part.description = "Test part"

        try db.writer.write { dbConn in try part.insert(dbConn) }
        #expect(part.id != nil)

        let fetched = try db.writer.read { dbConn in try Part.fetchOne(dbConn, key: part.id!) }
        #expect(fetched?.code == "P-001")
        #expect(fetched?.companyCostPrice == 8.50)
        #expect(fetched?.name == "Test Part")
    }

    // MARK: - Job Model

    @Test("Job insert and fetch round-trip")
    func testJobInsertFetch() throws {
        let db = try freshDB()
        var job = Job(
            jobNumber: "J-001",
            jobName: "Smith Renovation",
            status: "active",
            priority: "normal",
            jobType: "renovation",
            createdAt: now,
            updatedAt: now
        )

        try db.writer.write { dbConn in try job.insert(dbConn) }
        #expect(job.id != nil)

        let fetched = try db.writer.read { dbConn in try Job.fetchOne(dbConn, key: job.id!) }
        #expect(fetched?.jobName == "Smith Renovation")
        #expect(fetched?.status == "active")
        #expect(fetched?.priority == "normal")
        #expect(fetched?.jobType == "renovation")
    }

    // MARK: - Supplier Model

    @Test("Supplier insert and fetch round-trip")
    func testSupplierInsertFetch() throws {
        let db = try freshDB()
        var supplier = Supplier(name: "Acme Parts")
        supplier.phone = "555-9999"
        supplier.email = "orders@acme.test"
        supplier.deliveryMethod = "local_pickup"

        try db.writer.write { dbConn in try supplier.insert(dbConn) }
        #expect(supplier.id != nil)

        let fetched = try db.writer.read { dbConn in try Supplier.fetchOne(dbConn, key: supplier.id!) }
        #expect(fetched?.name == "Acme Parts")
        #expect(fetched?.phone == "555-9999")
        #expect(fetched?.deliveryMethod == "local_pickup")
    }

    // MARK: - Vehicle Model

    @Test("Vehicle insert and fetch round-trip")
    func testVehicleInsertFetch() throws {
        let db = try freshDB()
        var vehicle = Vehicle(
            vehicleNumber: "T-001",
            vehicleName: "Shop Truck",
            vehicleType: "company_truck",
            status: "active",
            isActive: 1,
            createdAt: now,
            updatedAt: now
        )
        vehicle.licensePlate = "ABC-1234"
        vehicle.year = 2024
        vehicle.make = "Ford"
        vehicle.model = "F-250"

        try db.writer.write { dbConn in try vehicle.insert(dbConn) }
        #expect(vehicle.id != nil)

        let fetched = try db.writer.read { dbConn in try Vehicle.fetchOne(dbConn, key: vehicle.id!) }
        #expect(fetched?.vehicleNumber == "T-001")
        #expect(fetched?.licensePlate == "ABC-1234")
        #expect(fetched?.make == "Ford")
    }

    // MARK: - Tool Model

    @Test("Tool insert and fetch round-trip")
    func testToolInsertFetch() throws {
        let db = try freshDB()
        var tool = Tool(
            toolNumber: "T-042",
            name: "Hammer Drill",
            category: "power_tools",
            locationType: "warehouse",
            status: "available",
            hasKit: 0,
            isActive: 1,
            createdAt: now,
            updatedAt: now
        )
        tool.serialNumber = "SN-ABCD-1234"

        try db.writer.write { dbConn in try tool.insert(dbConn) }
        #expect(tool.id != nil)

        let fetched = try db.writer.read { dbConn in try Tool.fetchOne(dbConn, key: tool.id!) }
        #expect(fetched?.name == "Hammer Drill")
        #expect(fetched?.toolNumber == "T-042")
        #expect(fetched?.serialNumber == "SN-ABCD-1234")
    }

    // MARK: - Notebook Model

    @Test("Notebook insert and fetch round-trip")
    func testNotebookInsertFetch() throws {
        let db = try freshDB()

        // Need a user for created_by (NOT NULL FK)
        var user = User(displayName: "Admin", pinHash: "hash", isActive: 1)
        try db.writer.write { dbConn in try user.insert(dbConn) }

        var notebook = Notebook(
            title: "Daily Notes",
            createdBy: user.id!,
            isArchived: 0,
            createdAt: now,
            updatedAt: now
        )

        try db.writer.write { dbConn in try notebook.insert(dbConn) }
        #expect(notebook.id != nil)

        let fetched = try db.writer.read { dbConn in try Notebook.fetchOne(dbConn, key: notebook.id!) }
        #expect(fetched?.title == "Daily Notes")
    }

    // MARK: - PurchaseOrder Model

    @Test("PurchaseOrder insert and fetch round-trip")
    func testPurchaseOrderInsertFetch() throws {
        let db = try freshDB()

        // Need a supplier for supplier_id (NOT NULL FK)
        var supplier = Supplier(name: "Test Supplier")
        try db.writer.write { dbConn in try supplier.insert(dbConn) }

        var po = PurchaseOrder(
            poNumber: "PO-2026-001",
            supplierId: supplier.id!,
            status: "draft",
            createdAt: now,
            updatedAt: now
        )

        try db.writer.write { dbConn in try po.insert(dbConn) }
        #expect(po.id != nil)

        let fetched = try db.writer.read { dbConn in try PurchaseOrder.fetchOne(dbConn, key: po.id!) }
        #expect(fetched?.poNumber == "PO-2026-001")
        #expect(fetched?.status == "draft")
    }

    // MARK: - ChatChannel Model

    @Test("ChatChannel insert and fetch round-trip")
    func testChatChannelInsertFetch() throws {
        let db = try freshDB()

        // Need a user for created_by (NOT NULL FK)
        var user = User(displayName: "Admin", pinHash: "hash", isActive: 1)
        try db.writer.write { dbConn in try user.insert(dbConn) }

        var channel = ChatChannel(
            channelType: "group",
            createdBy: user.id!,
            isActive: 1,
            createdAt: now,
            updatedAt: now
        )
        channel.name = "General"

        try db.writer.write { dbConn in try channel.insert(dbConn) }
        #expect(channel.id != nil)

        let fetched = try db.writer.read { dbConn in try ChatChannel.fetchOne(dbConn, key: channel.id!) }
        #expect(fetched?.name == "General")
        #expect(fetched?.channelType == "group")
    }

    // MARK: - Soft Delete Pattern

    @Test("Soft delete sets deleted_at")
    func testSoftDelete() throws {
        let db = try freshDB()
        var user = User(displayName: "Deletable", pinHash: "hash", isActive: 1)
        try db.writer.write { dbConn in try user.insert(dbConn) }

        user.deletedAt = "2026-03-14 00:00:00"
        user.isActive = 0
        try db.writer.write { dbConn in try user.update(dbConn) }

        let fetched = try db.writer.read { dbConn in try User.fetchOne(dbConn, key: user.id!) }
        #expect(fetched?.deletedAt == "2026-03-14 00:00:00")
        #expect(fetched?.isActive == 0)
    }

    // MARK: - Multiple Records

    @Test("Fetch all users returns correct count")
    func testFetchAllUsers() throws {
        let db = try freshDB()

        for i in 1...5 {
            var user = User(displayName: "User \(i)", pinHash: "hash\(i)", isActive: 1)
            try db.writer.write { dbConn in try user.insert(dbConn) }
        }

        let all = try db.writer.read { dbConn in try User.fetchAll(dbConn) }
        #expect(all.count == 5)
    }
}
