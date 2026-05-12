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

    @Test("All 81 migrations (000-080) apply successfully")
    func testAllMigrationsApply() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        // Check at least one representative table from each migration group
        let tables = [
            // Core foundation (000-008)
            "_change_log",       // 000
            "users",             // 001
            "parts",             // 002
            "jobs",              // 003
            "notebooks",         // 004
            "purchase_orders",   // 005
            "vehicles",          // 006
            "chat_channels",     // 007
            "_conflict_log",     // 008
            // People & scheduling (009-011)
            "certifications",    // 009
            "billing_periods",   // 010
            "pto_policies",      // 011
            // Fleet & tools (012-013)
            "job_trailers",      // 012
            "tool_depreciation_entries", // 013
            // Contacts & costs (014-017)
            "entity_contacts",   // 014
            "job_team_members",  // 015
            "companion_rules",   // 016
            "hat_permissions",   // 017
            // AI & profiles (018-019)
            "_text_history",     // 018
            "business_profiles", // 019
            // Warehouse & stock (020-021)
            "warehouse_locations", // 020
            // Notebooks & auth (022-024)
            // Pricing & suppliers (025-028)
            "pricing_tiers",     // 025
            // Forecasting (029-031)
            // JPO & staging (032-035)
            "staging_boxes",     // 035
            // Clock & chat (036-037)
            "message_attachments", // 037
            // Notebook hierarchy (038-039)
            "notebook_templates", // 039
            // Warehouse floor plans (040)
            "warehouse_floor_plans", // 040
            "warehouse_floor_features",
            "warehouse_storage_units",
            "warehouse_storage_levels",
            // Audit & compliance (041-042)
            "part_confidence",   // 041
            "break_records",     // 042
            // Payment & classification (043-045)
            "payment_records",   // 043
            // Scheduling & estimation (046-047)
            "estimation_questions", // 047
            // Tools detail (048-050)
            "tool_checkouts",    // 048
            // Vehicle & trailer (051-053)
            "inspection_templates", // 053
            // Reports & office (054-055)
            "saved_reports",     // 054
            // AI conversations (056)
            "ai_conversation_messages", // 056
            // Wishlist & background tasks (057-058)
            "wishlist_items",    // 057
            "background_task_log", // 058
            // Audit assignments & permissions (059-060)
            "vehicle_location_logs", // 079
        ]

        for table in tables {
            let exists = try db.writer.read { db in
                try db.tableExists(table)
            }
            #expect(exists, "Table \(table) should exist after migrations")
        }
    }

    @Test("Schema version is 81")
    func testSchemaVersion() throws {
        #expect(AppDatabase.schemaVersion == 81)
    }

    @Test("Migration 080 adds live inspection records vehicle performed-at index")
    func testMigration080InspectionRecordsVehiclePerformedAtIndex() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let indexes = try db.writer.read { db in
            try Row.fetchAll(db, sql: "PRAGMA index_list('inspection_records')")
        }

        let index = indexes.first { row in
            (row["name"] as String?) == "idx_ir_vehicle_performed_at_live"
        }
        #expect(index != nil, "inspection_records should have vehicle/performed_at index")
        #expect((index?["partial"] as Int?) == 1, "vehicle/performed_at index should exclude deleted rows")

        let indexedColumns = try db.writer.read { db in
            try Row.fetchAll(db, sql: "PRAGMA index_info('idx_ir_vehicle_performed_at_live')")
                .compactMap { $0["name"] as String? }
        }
        #expect(indexedColumns == ["vehicle_id", "performed_at"])

        let queryPlan = try db.writer.read { db in
            try Row.fetchAll(db, sql: """
                EXPLAIN QUERY PLAN
                SELECT result, performed_at FROM inspection_records
                WHERE vehicle_id = ? AND deleted_at IS NULL
                ORDER BY performed_at DESC LIMIT 1
                """, arguments: [1])
                .compactMap { $0["detail"] as String? }
                .joined(separator: "\n")
        }
        #expect(queryPlan.contains("idx_ir_vehicle_performed_at_live"))
    }

    @Test("Migration 079 adds live vehicle latest-location index")
    func testMigration079VehicleLocationLogsIndex() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let indexes = try db.writer.read { db in
            try Row.fetchAll(db, sql: "PRAGMA index_list('vehicle_location_logs')")
        }

        let index = indexes.first { row in
            (row["name"] as String?) == "idx_vll_vehicle_latest_live"
        }
        #expect(index != nil, "vehicle_location_logs should have latest-location index")
        #expect((index?["partial"] as Int?) == 1, "latest-location index should exclude deleted rows")

        let indexedColumns = try db.writer.read { db in
            try Row.fetchAll(db, sql: "PRAGMA index_info('idx_vll_vehicle_latest_live')")
                .compactMap { $0["name"] as String? }
        }
        #expect(indexedColumns == ["vehicle_id", "id"])

        let queryPlan = try db.writer.read { db in
            try Row.fetchAll(db, sql: """
                EXPLAIN QUERY PLAN
                SELECT MAX(id)
                FROM vehicle_location_logs
                WHERE deleted_at IS NULL
                GROUP BY vehicle_id
                """)
                .compactMap { $0["detail"] as String? }
                .joined(separator: "\n")
        }
        #expect(queryPlan.contains("idx_vll_vehicle_latest_live"))
    }

    @Test("Migration 073 adds grid_rows and grid_cols to warehouse_floor_plans")
    func testMigration073FloorPlanGridDimensions() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let columns = try db.writer.read { db in
            try db.columns(in: "warehouse_floor_plans").map(\.name)
        }
        #expect(columns.contains("grid_rows"), "warehouse_floor_plans should have grid_rows after migration 073")
        #expect(columns.contains("grid_cols"), "warehouse_floor_plans should have grid_cols after migration 073")
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
        #expect(count == 6, "Should have 6 default cost settings (3 from migration 014 + 3 from migration 019)")
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
