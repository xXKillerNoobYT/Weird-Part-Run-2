import Testing
import GRDB
@testable import WiredPartCore

@Suite("Database Migration Tests")
struct DatabaseTests {

    @Test("In-memory database opens and migrations run")
    func testInMemoryDatabaseOpens() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        // Verify the database is functional by checking a known table exists
        let tableExists = try db.writer.read { db in
            try db.tableExists("users")
        }
        #expect(tableExists)
    }

    @Test("All 18 migrations apply successfully")
    func testAllMigrationsApply() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        // Check a table from each migration
        let tables = [
            "_change_log",       // 000
            "users",             // 001
            "parts",             // 002
            "jobs",              // 003
            "notebooks",         // 004
            "purchase_orders",   // 005
            "vehicles",          // 006
            "chat_channels",     // 007
            "_conflict_log",     // 008
            "certifications",    // 009
            "billing_periods",   // 010
            "pto_policies",      // 011
            "job_trailers",      // 012
            "tool_depreciation_entries", // 013
            "entity_contacts",   // 014
            "job_team_members",  // 015
            "companion_rules",   // 016
            "hat_permissions",   // 017
        ]

        for table in tables {
            let exists = try db.writer.read { db in
                try db.tableExists(table)
            }
            #expect(exists, "Table \(table) should exist after migrations")
        }
    }

    @Test("Users table has correct columns")
    func testUsersTableSchema() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let columns = try db.writer.read { db in
            try db.columns(in: "users").map(\.name)
        }

        let expectedColumns = [
            "id", "display_name", "email", "phone", "pin_hash",
            "default_truck_id", "emergency_contact_name", "emergency_contact_phone",
            "certification", "hire_date", "pay_rate", "is_active",
            "avatar_url", "deleted_at", "created_at", "updated_at",
        ]

        for col in expectedColumns {
            #expect(columns.contains(col), "users table should have column '\(col)'")
        }
    }

    @Test("Settings table has correct columns")
    func testSettingsTableSchema() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let columns = try db.writer.read { db in
            try db.columns(in: "settings").map(\.name)
        }

        #expect(columns.contains("key"))
        #expect(columns.contains("value"))
        #expect(columns.contains("category"))
    }

    @Test("Change log table supports sync tracking")
    func testChangeLogSchema() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let columns = try db.writer.read { db in
            try db.columns(in: "_change_log").map(\.name)
        }

        let expected = ["id", "device_id", "table_name", "record_id", "operation",
                        "changed_fields", "old_values", "timestamp", "synced",
                        "sync_batch_id", "sequence"]

        for col in expected {
            #expect(columns.contains(col), "_change_log should have column '\(col)'")
        }
    }

    @Test("Sync infrastructure tables exist")
    func testSyncInfrastructure() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let syncTables = ["_conflict_log", "_vector_clock", "_device_registry"]
        for table in syncTables {
            let exists = try db.writer.read { db in
                try db.tableExists(table)
            }
            #expect(exists, "Sync table \(table) should exist")
        }
    }

    @Test("Company cost settings are seeded")
    func testCostSettingsSeeded() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let count = try db.writer.read { db -> Int in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM company_cost_settings")!
        }
        #expect(count == 3, "Should have 3 default cost settings")
    }

    @Test("Parts table includes cost tracking columns from migration 014")
    func testPartsHasCostColumns() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let columns = try db.writer.read { db in
            try db.columns(in: "parts").map(\.name)
        }

        #expect(columns.contains("weighted_avg_cost"))
        #expect(columns.contains("custom_margin_percent"))
        #expect(columns.contains("cost_last_updated"))
    }

    @Test("Jobs table includes budget columns from migration 014")
    func testJobsHasBudgetColumns() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let columns = try db.writer.read { db in
            try db.columns(in: "jobs").map(\.name)
        }

        #expect(columns.contains("budget_limit"))
        #expect(columns.contains("budget_alert_percent"))
    }
}
