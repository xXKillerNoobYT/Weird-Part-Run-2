import Foundation
import GRDB
@testable import WiredPartCore

/// Shared helpers for end-to-end integration tests.
///
/// These helpers set up a fully seeded in-memory database with an admin user,
/// providing all services ready for testing complete workflows.
struct E2ETestHelpers {

    /// A fully initialized test environment with all services.
    struct TestEnvironment {
        let db: AppDatabase
        let auth: AuthService
        let settings: SettingsService
        let parts: PartsService
        let warehouse: WarehouseService
        let jobs: JobsService
        let orders: OrdersService
        let fleet: FleetService
        let people: PeopleService
        let scheduling: SchedulingService
        let chat: ChatService
        let notebooks: NotebooksService
        let reports: ReportsService
        let tools: ToolsService

        /// The admin user created during bootstrap.
        let adminUser: User
        let adminUserId: Int64
        let adminToken: String
    }

    /// Create a fresh in-memory database, bootstrap it with an admin user,
    /// and return all services ready for use.
    static func setUp(adminName: String = "TestAdmin", adminPin: String = "1234") throws -> TestEnvironment {
        let db = try AppDatabase.openInMemoryDatabase()

        let auth = AuthService(db: db)
        let settings = SettingsService(db: db)
        let parts = PartsService(db: db)
        let warehouse = WarehouseService(db: db)
        let jobs = JobsService(db: db)
        let orders = OrdersService(db: db)
        let fleet = FleetService(db: db)
        let people = PeopleService(db: db)
        let scheduling = SchedulingService(db: db)
        let chat = ChatService(db: db)
        let notebooks = NotebooksService(db: db)
        let reports = ReportsService(db: db)
        let tools = ToolsService(db: db)

        // Bootstrap: create admin user, hats, permissions, default settings
        let result = try auth.seedFirstAdmin(displayName: adminName, pin: adminPin)
        let user = result.user!
        let userId = user.id!
        let token = result.token!

        return TestEnvironment(
            db: db,
            auth: auth,
            settings: settings,
            parts: parts,
            warehouse: warehouse,
            jobs: jobs,
            orders: orders,
            fleet: fleet,
            people: people,
            scheduling: scheduling,
            chat: chat,
            notebooks: notebooks,
            reports: reports,
            tools: tools,
            adminUser: user,
            adminUserId: userId,
            adminToken: token
        )
    }

    // MARK: - Seed Helpers

    /// Create a part category and return its ID.
    static func seedCategory(_ env: TestEnvironment, name: String = "Electrical") throws -> Int64 {
        try env.parts.createCategory(name: name, description: "Test category")
    }

    /// Create a part category + style + type chain and return (categoryId, styleId, typeId).
    static func seedPartHierarchy(_ env: TestEnvironment, category: String = "Wire", style: String = "THHN", type: String = "12 AWG") throws -> (Int64, Int64, Int64) {
        let catId = try env.parts.createCategory(name: category)
        let styleId = try env.parts.createStyle(categoryId: catId, name: style)
        let typeId = try env.parts.createType(styleId: styleId, name: type)
        return (catId, styleId, typeId)
    }

    /// Create a basic part and return its ID.
    static func seedPart(_ env: TestEnvironment, name: String = "Test Wire", categoryId: Int64) throws -> Int64 {
        try env.parts.createPart(
            categoryId: categoryId,
            name: name,
            code: "TW-\(Int.random(in: 1000...9999))"
        )
    }

    /// Create a job and return its ID.
    static func seedJob(_ env: TestEnvironment, jobNumber: String = "J-001", name: String = "Test Job") throws -> Int64 {
        try env.jobs.createJob(
            jobNumber: jobNumber,
            jobName: name,
            customerName: "Test Customer",
            status: "active",
            createdBy: env.adminUserId
        )
    }

    /// Create a brand and return its ID.
    static func seedBrand(_ env: TestEnvironment, name: String = "TestBrand") throws -> Int64 {
        try env.parts.createBrand(name: name)
    }

    /// Create a supplier and return its ID.
    static func seedSupplier(_ env: TestEnvironment, name: String = "TestSupplier") throws -> Int64 {
        try env.parts.createSupplier(name: name, email: "test@supplier.com")
    }

    /// Seed warehouse stock for a part at a location. Returns the stock row ID.
    static func seedStock(_ env: TestEnvironment, partId: Int64, qty: Int, locationType: String = "warehouse", locationId: Int64 = 1) throws -> Int64 {
        try env.warehouse.createMovement(
            partId: partId,
            qty: qty,
            fromLocationType: nil,
            fromLocationId: nil,
            toLocationType: locationType,
            toLocationId: locationId,
            movementType: "receive",
            reason: "Initial stock",
            performedBy: env.adminUserId
        )
    }
}
