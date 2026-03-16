import Foundation
import GRDB

// MARK: - Migration Registration
//
// Ports all 18 TypeScript migrations (000–017) to GRDB DatabaseMigrator.
// Each migration keeps its original name for schema parity tracking.
// Tables are created with their final column sets (including deleted_at from 008).

extension AppDatabase {
    static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        // In development, allow schema alterations for ease of iteration.
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        registerMigration000ChangeLog(&migrator)
        registerMigration001Foundation(&migrator)
        registerMigration002PartsInventory(&migrator)
        registerMigration003JobsLabor(&migrator)
        registerMigration004Notebooks(&migrator)
        registerMigration005Orders(&migrator)
        registerMigration006FleetToolsScheduling(&migrator)
        registerMigration007Chat(&migrator)
        registerMigration008SoftDeleteAndSync(&migrator)
        registerMigration009PeopleFull(&migrator)
        registerMigration010CostsReceiving(&migrator)
        registerMigration011ReportsPTO(&migrator)
        registerMigration012WarehouseAttachments(&migrator)
        registerMigration013ToolsSupplierExtras(&migrator)
        registerMigration014ContactsCostsProfiles(&migrator)
        registerMigration015JobTeamSuppliers(&migrator)
        registerMigration016CompanionsAlternatives(&migrator)
        registerMigration017PermissionBackfill(&migrator)
        registerMigration018AICapabilities(&migrator)
    }
}

// MARK: - 000: Change Log

extension AppDatabase {
    private static func registerMigration000ChangeLog(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("000_change_log") { db in
            try db.create(table: "_change_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("device_id", .text).notNull()
                t.column("table_name", .text).notNull()
                t.column("record_id", .integer).notNull()
                t.column("operation", .text).notNull()
                    .check { $0 == "INSERT" || $0 == "UPDATE" || $0 == "DELETE" }
                t.column("changed_fields", .text)
                t.column("old_values", .text)
                t.column("timestamp", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("synced", .integer).notNull().defaults(to: 0)
                t.column("sync_batch_id", .text)
                t.column("sequence", .integer)
            }

            try db.create(
                index: "idx_change_log_unsynced",
                on: "_change_log",
                columns: ["synced", "timestamp"]
            )
            try db.create(
                index: "idx_change_log_table",
                on: "_change_log",
                columns: ["table_name", "record_id"]
            )
        }
    }
}

// MARK: - 001: Foundation

extension AppDatabase {
    private static func registerMigration001Foundation(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("001_foundation") { db in
            // Users
            try db.create(table: "users") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("display_name", .text).notNull()
                t.column("email", .text)
                t.column("phone", .text)
                t.column("pin_hash", .text).notNull()
                t.column("default_truck_id", .integer)
                t.column("emergency_contact_name", .text)
                t.column("emergency_contact_phone", .text)
                t.column("certification", .text)
                t.column("hire_date", .text)
                t.column("pay_rate", .double)
                t.column("is_active", .integer).defaults(to: 1)
                t.column("avatar_url", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }

            // Hats (Roles)
            try db.create(table: "hats") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("description", .text)
                t.column("level", .integer).defaults(to: 0)
                t.column("is_builtin", .integer).defaults(to: 0)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }

            // Hat Permissions
            try db.create(table: "hat_permissions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("hat_id", .integer).notNull()
                    .references("hats", onDelete: .cascade)
                t.column("permission_key", .text).notNull()
                t.uniqueKey(["hat_id", "permission_key"])
            }
            try db.create(index: "idx_hat_perms_hat", on: "hat_permissions", columns: ["hat_id"])
            try db.create(index: "idx_hat_perms_key", on: "hat_permissions", columns: ["permission_key"])

            // User Hats
            try db.create(table: "user_hats") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .integer).notNull()
                    .references("users", onDelete: .cascade)
                t.column("hat_id", .integer).notNull()
                    .references("hats", onDelete: .cascade)
                t.column("is_active", .integer).defaults(to: 1)
                t.column("deleted_at", .text)
                t.uniqueKey(["user_id", "hat_id"])
            }
            try db.create(index: "idx_user_hats_user", on: "user_hats", columns: ["user_id"])

            // Job Lead Elevations
            try db.create(table: "job_lead_elevations") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .integer).notNull()
                    .references("users", onDelete: .cascade)
                t.column("job_id", .integer).notNull()
                t.column("permission_key", .text).notNull()
                t.column("granted_by", .integer).references("users")
                t.column("granted_at", .text).defaults(sql: "(datetime('now'))")
                t.column("expires_at", .text)
                t.column("deleted_at", .text)
                t.uniqueKey(["user_id", "job_id", "permission_key"])
            }

            // Devices
            try db.create(table: "devices") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("device_name", .text).notNull()
                t.column("device_fingerprint", .text).notNull().unique()
                t.column("assigned_user_id", .integer).references("users")
                t.column("is_public", .integer).defaults(to: 0)
                t.column("last_seen", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_devices_fp", on: "devices", columns: ["device_fingerprint"])

            // Settings
            try db.create(table: "settings") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("key", .text).notNull().unique()
                t.column("value", .text)
                t.column("category", .text).defaults(to: "general")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_settings_cat", on: "settings", columns: ["category"])

            // Activity Log
            try db.create(table: "activity_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .integer).references("users")
                t.column("action", .text).notNull()
                t.column("entity_type", .text)
                t.column("entity_id", .integer)
                t.column("details", .text)
                t.column("ip_address", .text)
                t.column("timestamp", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_activity_ts", on: "activity_log", columns: ["timestamp"])
            try db.create(index: "idx_activity_entity", on: "activity_log", columns: ["entity_type", "entity_id"])

            // Notifications
            try db.create(table: "notifications") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .integer).references("users")
                t.column("title", .text).notNull()
                t.column("body", .text)
                t.column("severity", .text).defaults(to: "info")
                t.column("source", .text).defaults(to: "system")
                t.column("link", .text)
                t.column("is_read", .integer).defaults(to: 0)
                t.column("type", .text).defaults(to: "system")
                t.column("message", .text)
                t.column("entity_type", .text)
                t.column("entity_id", .integer)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_notif_user", on: "notifications", columns: ["user_id", "is_read"])
            try db.create(index: "idx_notifications_created", on: "notifications", columns: ["created_at"])
            try db.create(index: "idx_notifications_entity", on: "notifications", columns: ["entity_type", "entity_id"])

            // Notification Preferences
            try db.create(table: "notification_preferences") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .integer).notNull().references("users")
                t.column("notification_type", .text).notNull()
                t.column("is_enabled", .integer).notNull().defaults(to: 0)
                t.column("deleted_at", .text)
                t.uniqueKey(["user_id", "notification_type"])
            }
            try db.create(index: "idx_notif_prefs_user", on: "notification_preferences", columns: ["user_id"])
        }
    }
}

// MARK: - 002: Parts & Inventory

extension AppDatabase {
    private static func registerMigration002PartsInventory(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("002_parts_inventory") { db in
            // Part Categories
            try db.create(table: "part_categories") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("description", .text)
                t.column("sort_order", .integer).defaults(to: 0)
                t.column("is_active", .integer).defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }

            // Part Styles
            try db.create(table: "part_styles") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("category_id", .integer).notNull()
                    .references("part_categories", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("description", .text)
                t.column("image_url", .text)
                t.column("sort_order", .integer).defaults(to: 0)
                t.column("is_active", .integer).defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["category_id", "name"])
            }
            try db.create(index: "idx_styles_category", on: "part_styles", columns: ["category_id"])

            // Part Types
            try db.create(table: "part_types") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("style_id", .integer).notNull()
                    .references("part_styles", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("description", .text)
                t.column("color", .text)
                t.column("image_url", .text)
                t.column("sort_order", .integer).defaults(to: 0)
                t.column("is_active", .integer).defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["style_id", "name"])
            }
            try db.create(index: "idx_types_style", on: "part_types", columns: ["style_id"])

            // Part Colors
            try db.create(table: "part_colors") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("hex_code", .text)
                t.column("sort_order", .integer).defaults(to: 0)
                t.column("is_active", .integer).defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }

            // Brands
            try db.create(table: "brands") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("website", .text)
                t.column("notes", .text)
                t.column("is_active", .integer).defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }

            // Suppliers
            try db.create(table: "suppliers") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("contact_name", .text)
                t.column("email", .text)
                t.column("phone", .text)
                t.column("address", .text)
                t.column("website", .text)
                t.column("rep_name", .text)
                t.column("rep_email", .text)
                t.column("rep_phone", .text)
                t.column("notes", .text)
                t.column("delivery_method", .text).defaults(to: "standard_shipping")
                t.column("delivery_days", .text)
                t.column("special_order_lead_days", .integer)
                t.column("delivery_notes", .text)
                t.column("driver_name", .text)
                t.column("driver_phone", .text)
                t.column("driver_email", .text)
                t.column("on_time_rate", .double).defaults(to: 0.95)
                t.column("quality_score", .double).defaults(to: 0.90)
                t.column("avg_lead_days", .integer).defaults(to: 5)
                t.column("reliability_score", .double).defaults(to: 0.85)
                t.column("communication_score", .double).defaults(to: 0.85)
                t.column("is_active", .integer).defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }

            // Parts
            try db.create(table: "parts") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("category_id", .integer).notNull()
                    .references("part_categories")
                t.column("style_id", .integer).references("part_styles")
                t.column("type_id", .integer).references("part_types")
                t.column("color_id", .integer).references("part_colors")
                t.column("part_type", .text).notNull().defaults(to: "general")
                t.column("code", .text).unique()
                t.column("name", .text).notNull()
                t.column("description", .text)
                t.column("brand_id", .integer).references("brands", onDelete: .setNull)
                t.column("manufacturer_part_number", .text)
                t.column("unit_of_measure", .text).defaults(to: "each")
                t.column("weight_lbs", .double)
                t.column("company_cost_price", .double).notNull().defaults(to: 0.0)
                t.column("company_markup_percent", .double).notNull().defaults(to: 0.0)
                t.column("min_stock_level", .integer).defaults(to: 0)
                t.column("max_stock_level", .integer).defaults(to: 0)
                t.column("target_stock_level", .integer).defaults(to: 0)
                t.column("reorder_point", .integer).defaults(to: 0)
                t.column("forecast_last_run", .text)
                t.column("forecast_adu_30", .double).defaults(to: 0)
                t.column("forecast_adu_90", .double).defaults(to: 0)
                t.column("forecast_reorder_point", .integer).defaults(to: 0)
                t.column("forecast_target_qty", .integer).defaults(to: 0)
                t.column("forecast_suggested_order", .integer).defaults(to: 0)
                t.column("forecast_days_until_low", .integer).defaults(to: 999)
                t.column("is_deprecated", .integer).defaults(to: 0)
                t.column("deprecation_reason", .text)
                t.column("is_qr_tagged", .integer).defaults(to: 0)
                t.column("notes", .text)
                t.column("image_url", .text)
                t.column("pdf_url", .text)
                t.column("shelf_location", .text)
                t.column("bin_location", .text)
                t.column("is_active", .integer).defaults(to: 1)
                t.column("weighted_avg_cost", .double).defaults(to: 0)
                t.column("custom_margin_percent", .double)
                t.column("cost_last_updated", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }

            // Generated column for company_sell_price
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_parts_category ON parts(category_id)
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_parts_brand ON parts(brand_id)
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_parts_name ON parts(name)
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_parts_code ON parts(code)
                """)

            // Brand-Supplier Links
            try db.create(table: "brand_supplier_links") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("brand_id", .integer).notNull()
                    .references("brands", onDelete: .cascade)
                t.column("supplier_id", .integer).notNull()
                    .references("suppliers", onDelete: .cascade)
                t.column("account_number", .text)
                t.column("notes", .text)
                t.column("is_active", .integer).defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["brand_id", "supplier_id"])
            }

            // Part-Supplier Links
            try db.create(table: "part_supplier_links") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("part_id", .integer).notNull()
                    .references("parts", onDelete: .cascade)
                t.column("supplier_id", .integer).notNull()
                    .references("suppliers", onDelete: .cascade)
                t.column("supplier_part_number", .text)
                t.column("supplier_cost_price", .double)
                t.column("moq", .integer).defaults(to: 1)
                t.column("discount_brackets", .text)
                t.column("last_price_date", .text)
                t.column("is_preferred", .integer).defaults(to: 0)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["part_id", "supplier_id"])
            }

            // Stock
            try db.create(table: "stock") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("part_id", .integer).notNull()
                    .references("parts", onDelete: .cascade)
                t.column("location_type", .text).notNull()
                t.column("location_id", .integer).notNull().defaults(to: 1)
                t.column("qty", .integer).notNull().defaults(to: 0)
                t.column("supplier_id", .integer).references("suppliers")
                t.column("last_counted", .text)
                t.column("deleted_at", .text)
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_stock_part", on: "stock", columns: ["part_id"])
            try db.create(index: "idx_stock_location", on: "stock", columns: ["location_type", "location_id"])

            // Stock Movements
            try db.create(table: "stock_movements") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("part_id", .integer).notNull().references("parts")
                t.column("qty", .integer).notNull()
                t.column("from_location_type", .text)
                t.column("from_location_id", .integer)
                t.column("to_location_type", .text)
                t.column("to_location_id", .integer)
                t.column("supplier_id", .integer).references("suppliers")
                t.column("movement_type", .text).notNull().defaults(to: "transfer")
                t.column("reason", .text)
                t.column("reference_number", .text)
                t.column("notes", .text)
                t.column("job_id", .integer)
                t.column("performed_by", .integer).notNull().references("users")
                t.column("verified_by", .integer).references("users")
                t.column("photo_path", .text)
                t.column("scan_confirmed", .integer).defaults(to: 0)
                t.column("gps_lat", .double)
                t.column("gps_lng", .double)
                t.column("unit_cost_at_move", .double)
                t.column("unit_sell_at_move", .double)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_movements_part", on: "stock_movements", columns: ["part_id"])
            try db.create(index: "idx_movements_job", on: "stock_movements", columns: ["job_id"])
            try db.create(index: "idx_movements_date", on: "stock_movements", columns: ["created_at"])

            // Pulled Staging Tags
            try db.create(table: "pulled_staging_tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("stock_id", .integer).notNull()
                    .references("stock", onDelete: .cascade).unique()
                t.column("destination_type", .text)
                t.column("destination_id", .integer)
                t.column("destination_label", .text)
                t.column("tagged_by", .integer).references("users")
                t.column("deleted_at", .text)
                t.column("tagged_at", .text).defaults(sql: "(datetime('now'))")
            }
        }
    }
}

// MARK: - 003: Jobs & Labor

extension AppDatabase {
    private static func registerMigration003JobsLabor(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("003_jobs_labor") { db in
            // Bill Rate Types
            try db.create(table: "bill_rate_types") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("description", .text)
                t.column("sort_order", .integer).defaults(to: 0)
                t.column("is_active", .integer).defaults(to: 1)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }

            // Jobs
            try db.create(table: "jobs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("job_number", .text).notNull().unique()
                t.column("job_name", .text).notNull()
                t.column("customer_name", .text)
                t.column("address_line1", .text)
                t.column("address_line2", .text)
                t.column("city", .text)
                t.column("state", .text)
                t.column("zip", .text)
                t.column("gps_lat", .double)
                t.column("gps_lng", .double)
                t.column("status", .text).notNull().defaults(to: "active")
                t.column("priority", .text).notNull().defaults(to: "normal")
                t.column("job_type", .text).notNull().defaults(to: "service")
                t.column("bill_rate_type_id", .integer).references("bill_rate_types")
                t.column("billing_rate", .double)
                t.column("estimated_hours", .double)
                t.column("lead_user_id", .integer).references("users")
                t.column("on_call_type", .text)
                t.column("warranty_start_date", .text)
                t.column("warranty_end_date", .text)
                t.column("start_date", .text)
                t.column("due_date", .text)
                t.column("completed_date", .text)
                t.column("notes", .text)
                t.column("budget_limit", .double)
                t.column("budget_alert_percent", .double).defaults(to: 80)
                t.column("created_by", .integer).references("users")
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_jobs_status", on: "jobs", columns: ["status"])
            try db.create(index: "idx_jobs_number", on: "jobs", columns: ["job_number"])

            // Job Parts
            try db.create(table: "job_parts") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("job_id", .integer).notNull().references("jobs")
                t.column("part_id", .integer).notNull().references("parts")
                t.column("qty_consumed", .integer).notNull().defaults(to: 0)
                t.column("qty_returned", .integer).notNull().defaults(to: 0)
                t.column("unit_cost_at_consume", .double)
                t.column("unit_sell_at_consume", .double)
                t.column("consumed_by", .integer).references("users")
                t.column("consumed_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("notes", .text)
                t.column("deleted_at", .text)
            }
            try db.create(index: "idx_job_parts_job", on: "job_parts", columns: ["job_id"])

            // Labor Entries
            try db.create(table: "labor_entries") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .integer).notNull().references("users")
                t.column("job_id", .integer).notNull().references("jobs")
                t.column("clock_in", .text).notNull()
                t.column("clock_out", .text)
                t.column("regular_hours", .double).defaults(to: 0)
                t.column("overtime_hours", .double).defaults(to: 0)
                t.column("drive_time_minutes", .integer).defaults(to: 0)
                t.column("clock_in_gps_lat", .double)
                t.column("clock_in_gps_lng", .double)
                t.column("clock_out_gps_lat", .double)
                t.column("clock_out_gps_lng", .double)
                t.column("clock_in_photo_path", .text)
                t.column("clock_out_photo_path", .text)
                t.column("status", .text).notNull().defaults(to: "clocked_in")
                t.column("edited_by", .integer).references("users")
                t.column("approved_by", .integer).references("users")
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_labor_user", on: "labor_entries", columns: ["user_id"])
            try db.create(index: "idx_labor_job", on: "labor_entries", columns: ["job_id"])
            try db.create(index: "idx_labor_status", on: "labor_entries", columns: ["status"])

            // Clock-Out Questions
            try db.create(table: "clock_out_questions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("question_text", .text).notNull()
                t.column("answer_type", .text).notNull().defaults(to: "text")
                t.column("is_required", .integer).notNull().defaults(to: 1)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("created_by", .integer).references("users")
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            // Clock-Out Responses
            try db.create(table: "clock_out_responses") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("labor_entry_id", .integer).notNull().references("labor_entries")
                t.column("question_id", .integer).notNull().references("clock_out_questions")
                t.column("answer_text", .text)
                t.column("answer_bool", .integer)
                t.column("photo_path", .text)
                t.column("deleted_at", .text)
                t.column("answered_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_cor_labor", on: "clock_out_responses", columns: ["labor_entry_id"])

            // One-Time Questions
            try db.create(table: "one_time_questions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("job_id", .integer).notNull().references("jobs")
                t.column("target_user_id", .integer).references("users")
                t.column("question_text", .text).notNull()
                t.column("answer_type", .text).notNull().defaults(to: "text")
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("created_by", .integer).notNull().references("users")
                t.column("answered_by", .integer).references("users")
                t.column("answer_text", .text)
                t.column("answer_photo_path", .text)
                t.column("shown_at_clock_in", .integer).notNull().defaults(to: 0)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("answered_at", .text)
            }
            try db.create(index: "idx_otq_job", on: "one_time_questions", columns: ["job_id"])

            // Daily Reports
            try db.create(table: "daily_reports") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("job_id", .integer).notNull().references("jobs")
                t.column("report_date", .text).notNull()
                t.column("report_json", .text).notNull()
                t.column("status", .text).notNull().defaults(to: "generated")
                t.column("generated_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("reviewed_by", .integer).references("users")
                t.column("reviewed_at", .text)
                t.column("deleted_at", .text)
                t.uniqueKey(["job_id", "report_date"])
            }
            try db.create(index: "idx_dr_job_date", on: "daily_reports", columns: ["job_id", "report_date"])
        }
    }
}

// MARK: - 004: Notebooks

extension AppDatabase {
    private static func registerMigration004Notebooks(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("004_notebooks") { db in
            try db.create(table: "notebook_templates") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("description", .text)
                t.column("job_type", .text)
                t.column("is_default", .integer).notNull().defaults(to: 0)
                t.column("created_by", .integer).references("users")
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            try db.create(table: "template_sections") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("template_id", .integer).notNull()
                    .references("notebook_templates", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("section_type", .text).notNull().defaults(to: "notes")
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("is_locked", .integer).notNull().defaults(to: 0)
                t.column("deleted_at", .text)
            }

            try db.create(table: "template_entries") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("section_id", .integer).notNull()
                    .references("template_sections", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("default_content", .text)
                t.column("entry_type", .text).notNull().defaults(to: "note")
                t.column("field_type", .text)
                t.column("field_required", .integer).notNull().defaults(to: 0)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("deleted_at", .text)
            }

            try db.create(table: "notebooks") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("description", .text)
                t.column("job_id", .integer).references("jobs")
                t.column("template_id", .integer).references("notebook_templates")
                t.column("created_by", .integer).notNull().references("users")
                t.column("is_archived", .integer).notNull().defaults(to: 0)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_notebooks_job", on: "notebooks", columns: ["job_id"])

            try db.create(table: "notebook_sections") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("notebook_id", .integer).notNull()
                    .references("notebooks", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("section_type", .text).notNull().defaults(to: "notes")
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("is_locked", .integer).notNull().defaults(to: 0)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_nb_sections_notebook", on: "notebook_sections", columns: ["notebook_id"])

            try db.create(table: "notebook_entries") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("section_id", .integer).notNull()
                    .references("notebook_sections", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("content", .text)
                t.column("entry_type", .text).notNull().defaults(to: "note")
                t.column("field_type", .text)
                t.column("field_required", .integer).notNull().defaults(to: 0)
                t.column("field_filled_by", .integer).references("users")
                t.column("task_status", .text)
                t.column("task_due_date", .text)
                t.column("task_assigned_to", .integer).references("users")
                t.column("task_parts_note", .text)
                t.column("created_by", .integer).notNull().references("users")
                t.column("updated_by", .integer).references("users")
                t.column("is_deleted", .integer).notNull().defaults(to: 0)
                t.column("deleted_by", .integer).references("users")
                t.column("deleted_at", .text)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_nb_entries_section", on: "notebook_entries", columns: ["section_id"])

            try db.create(table: "notebook_entry_permissions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("entry_id", .integer).notNull()
                    .references("notebook_entries", onDelete: .cascade)
                t.column("user_id", .integer).notNull().references("users")
                t.column("granted_by", .integer).notNull().references("users")
                t.column("deleted_at", .text)
                t.column("granted_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.uniqueKey(["entry_id", "user_id"])
            }

            try db.create(table: "task_order_links") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("entry_id", .integer).notNull()
                    .references("notebook_entries", onDelete: .cascade)
                t.column("po_id", .integer)
                t.column("status", .text).defaults(to: "linked")
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
        }
    }
}

// MARK: - 005: Orders

extension AppDatabase {
    private static func registerMigration005Orders(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("005_orders") { db in
            // Job Parts Orders
            try db.create(table: "job_parts_orders") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("job_id", .integer).references("jobs")
                t.column("order_number", .text).notNull().unique()
                t.column("status", .text).notNull().defaults(to: "draft")
                t.column("priority", .text).defaults(to: "normal")
                t.column("order_type", .text).notNull().defaults(to: "job")
                t.column("has_special_items", .integer).notNull().defaults(to: 0)
                t.column("smart_suggestions_enabled", .integer).notNull().defaults(to: 1)
                t.column("requested_by", .integer).notNull().references("users")
                t.column("approved_by", .integer).references("users")
                t.column("approved_at", .text)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_jpo_job", on: "job_parts_orders", columns: ["job_id"])
            try db.create(index: "idx_jpo_status", on: "job_parts_orders", columns: ["status"])

            // JPO Line Items
            try db.create(table: "jpo_line_items") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("jpo_id", .integer).notNull()
                    .references("job_parts_orders", onDelete: .cascade)
                t.column("part_id", .integer).notNull().references("parts")
                t.column("qty_requested", .integer).notNull().defaults(to: 1)
                t.column("qty_ordered", .integer).notNull().defaults(to: 0)
                t.column("qty_received", .integer).notNull().defaults(to: 0)
                t.column("priority", .text).defaults(to: "normal")
                t.column("entry_id", .integer).references("notebook_entries")
                t.column("suggested_supplier_id", .integer).references("suppliers")
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_jpo_lines_jpo", on: "jpo_line_items", columns: ["jpo_id"])

            // Purchase Orders
            try db.create(table: "purchase_orders") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("po_number", .text).notNull().unique()
                t.column("supplier_id", .integer).notNull().references("suppliers")
                t.column("status", .text).notNull().defaults(to: "draft")
                t.column("order_date", .text)
                t.column("expected_delivery", .text)
                t.column("actual_delivery", .text)
                t.column("shipping_method", .text)
                t.column("tracking_number", .text)
                t.column("subtotal", .double).defaults(to: 0)
                t.column("tax_amount", .double).defaults(to: 0)
                t.column("shipping_cost", .double).defaults(to: 0)
                t.column("total_cost", .double).defaults(to: 0)
                t.column("notes", .text)
                t.column("internal_notes", .text)
                t.column("pdf_path", .text)
                t.column("pdf_generated_at", .text)
                t.column("confirmation_checklist", .text)
                t.column("supplier_notes", .text)
                t.column("submitted_by", .integer).references("users")
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_po_supplier", on: "purchase_orders", columns: ["supplier_id"])
            try db.create(index: "idx_po_status", on: "purchase_orders", columns: ["status"])

            // PO Line Items
            try db.create(table: "po_line_items") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("po_id", .integer).notNull()
                    .references("purchase_orders", onDelete: .cascade)
                t.column("jpo_line_id", .integer).references("jpo_line_items")
                t.column("part_id", .integer).notNull().references("parts")
                t.column("qty_ordered", .integer).notNull()
                t.column("qty_received", .integer).notNull().defaults(to: 0)
                t.column("unit_cost", .double)
                t.column("received_unit_cost", .double)
                t.column("status", .text).defaults(to: "pending")
                t.column("backorder_expected_date", .text)
                t.column("received_at", .text)
                t.column("received_by", .integer).references("users")
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_po_lines_po", on: "po_line_items", columns: ["po_id"])

            // Returns
            try db.create(table: "returns") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("return_number", .text).notNull().unique()
                t.column("return_type", .text).notNull()
                t.column("po_id", .integer).references("purchase_orders")
                t.column("supplier_id", .integer).references("suppliers")
                t.column("job_id", .integer).references("jobs")
                t.column("status", .text).notNull().defaults(to: "draft")
                t.column("rma_number", .text)
                t.column("reason", .text).notNull()
                t.column("shipping_carrier", .text)
                t.column("tracking_number", .text)
                t.column("credit_amount", .double).defaults(to: 0)
                t.column("notes", .text)
                t.column("initiated_by", .integer).notNull().references("users")
                t.column("approved_by", .integer).references("users")
                t.column("approved_at", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            // Return Line Items
            try db.create(table: "return_line_items") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("return_id", .integer).notNull()
                    .references("returns", onDelete: .cascade)
                t.column("part_id", .integer).notNull().references("parts")
                t.column("po_line_id", .integer).references("po_line_items")
                t.column("qty", .integer).notNull()
                t.column("condition", .text).defaults(to: "new")
                t.column("disposition", .text).notNull()
                t.column("unit_cost", .double)
                t.column("notes", .text)
                t.column("returnable_to_supplier", .integer).defaults(to: 1)
                t.column("non_return_reason", .text)
                t.column("below_target_flag", .integer).defaults(to: 0)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            // Order Status History
            try db.create(table: "order_status_history") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("entity_type", .text).notNull()
                t.column("entity_id", .integer).notNull()
                t.column("old_status", .text)
                t.column("new_status", .text).notNull()
                t.column("changed_by", .integer).notNull().references("users")
                t.column("notes", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_order_history_entity", on: "order_status_history", columns: ["entity_type", "entity_id"])

            // Special Items
            try db.create(table: "special_items") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("jpo_id", .integer).notNull()
                    .references("job_parts_orders", onDelete: .cascade)
                t.column("description", .text).notNull()
                t.column("part_number", .text)
                t.column("quantity", .integer).notNull().defaults(to: 1)
                t.column("unit", .text).notNull().defaults(to: "each")
                t.column("estimated_cost", .double)
                t.column("notes", .text)
                t.column("is_flagged", .integer).notNull().defaults(to: 1)
                t.column("flag_resolved_by", .integer).references("users")
                t.column("flag_resolved_at", .text)
                t.column("linked_part_id", .integer).references("parts")
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_special_items_jpo", on: "special_items", columns: ["jpo_id"])

            // Job Preferences
            try db.create(table: "job_preferences") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("job_id", .integer).notNull().references("jobs")
                t.column("preference_type", .text).notNull()
                t.column("entity_id", .integer)
                t.column("text_value", .text)
                t.column("category", .text)
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("auto_learned", .integer).notNull().defaults(to: 1)
                t.column("confidence_score", .double).notNull().defaults(to: 0.5)
                t.column("last_used_at", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
        }
    }
}

// MARK: - 006: Fleet, Tools & Scheduling

extension AppDatabase {
    private static func registerMigration006FleetToolsScheduling(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("006_fleet_tools_scheduling") { db in
            // Vehicles
            try db.create(table: "vehicles") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("vehicle_number", .text).notNull().unique()
                t.column("vehicle_name", .text).notNull()
                t.column("vehicle_type", .text).notNull().defaults(to: "company_truck")
                t.column("status", .text).notNull().defaults(to: "active")
                t.column("make", .text)
                t.column("model", .text)
                t.column("year", .integer)
                t.column("color", .text)
                t.column("vin", .text)
                t.column("license_plate", .text)
                t.column("insurance_policy", .text)
                t.column("insurance_expiry", .text)
                t.column("registration_expiry", .text)
                t.column("current_odometer", .integer).defaults(to: 0)
                t.column("owner_user_id", .integer).references("users")
                t.column("notes", .text)
                t.column("photo_path", .text)
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            // Vehicle Assignments
            try db.create(table: "vehicle_assignments") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("vehicle_id", .integer).notNull().references("vehicles")
                t.column("user_id", .integer).notNull().references("users")
                t.column("assignment_type", .text).notNull().defaults(to: "primary")
                t.column("is_take_home", .integer).notNull().defaults(to: 0)
                t.column("home_to_shop_miles", .double)
                t.column("start_date", .text).notNull().defaults(sql: "(date('now'))")
                t.column("end_date", .text)
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_va_vehicle", on: "vehicle_assignments", columns: ["vehicle_id"])
            try db.create(index: "idx_va_user", on: "vehicle_assignments", columns: ["user_id"])

            // Tools
            try db.create(table: "tools") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("tool_number", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("category", .text).notNull().defaults(to: "general")
                t.column("brand", .text)
                t.column("model_number", .text)
                t.column("serial_number", .text)
                t.column("purchase_date", .text)
                t.column("purchase_cost", .double)
                t.column("warranty_expiry", .text)
                t.column("location_type", .text).notNull().defaults(to: "warehouse")
                t.column("location_id", .integer)
                t.column("assigned_to", .integer).references("users")
                t.column("status", .text).notNull().defaults(to: "available")
                t.column("condition_rating", .integer).defaults(to: 5)
                t.column("has_kit", .integer).notNull().defaults(to: 0)
                t.column("notes", .text)
                t.column("photo_path", .text)
                t.column("barcode", .text)
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("depreciation_method", .text)
                t.column("salvage_value", .double).defaults(to: 0)
                t.column("useful_life_years", .integer)
                t.column("calibration_due_date", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_tools_number", on: "tools", columns: ["tool_number"])
            try db.create(index: "idx_tools_status", on: "tools", columns: ["status"])
            try db.create(index: "idx_tools_barcode", on: "tools", columns: ["barcode"])

            // Kit Templates
            try db.create(table: "kit_templates") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("tool_id", .integer).notNull()
                    .references("tools", onDelete: .cascade)
                t.column("component_name", .text).notNull()
                t.column("component_type", .text).notNull().defaults(to: "accessory")
                t.column("qty_required", .integer).notNull().defaults(to: 1)
                t.column("brand", .text)
                t.column("model_number", .text)
                t.column("is_critical", .integer).notNull().defaults(to: 0)
                t.column("sort_order", .integer).defaults(to: 0)
                t.column("notes", .text)
                t.column("deleted_at", .text)
            }

            // Tool Movements
            try db.create(table: "tool_movements") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("tool_id", .integer).notNull().references("tools")
                t.column("from_location_type", .text)
                t.column("from_location_id", .integer)
                t.column("to_location_type", .text)
                t.column("to_location_id", .integer)
                t.column("movement_type", .text).notNull()
                t.column("reason", .text)
                t.column("job_id", .integer).references("jobs")
                t.column("performed_by", .integer).notNull().references("users")
                t.column("verified_by", .integer).references("users")
                t.column("condition_at_move", .integer)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            // Kit Verification Sessions
            try db.create(table: "kit_verification_sessions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("tool_id", .integer).notNull().references("tools")
                t.column("movement_id", .integer).references("tool_movements")
                t.column("verified_by", .integer).notNull().references("users")
                t.column("trigger_type", .text).notNull()
                t.column("is_complete", .integer).notNull().defaults(to: 0)
                t.column("missing_count", .integer).notNull().defaults(to: 0)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            // Kit Verification Items
            try db.create(table: "kit_verification_items") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("session_id", .integer).notNull()
                    .references("kit_verification_sessions", onDelete: .cascade)
                t.column("template_item_id", .integer).notNull()
                    .references("kit_templates")
                t.column("is_present", .integer).notNull().defaults(to: 1)
                t.column("condition_rating", .integer)
                t.column("notes", .text)
                t.column("deleted_at", .text)
            }

            // Tool Maintenance Types
            try db.create(table: "tool_maintenance_types") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("description", .text)
                t.column("default_interval_days", .integer)
                t.column("sort_order", .integer).defaults(to: 0)
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            // Tool Maintenance Schedules
            try db.create(table: "tool_maintenance_schedules") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("tool_id", .integer).notNull()
                    .references("tools", onDelete: .cascade)
                t.column("maintenance_type_id", .integer).notNull()
                    .references("tool_maintenance_types")
                t.column("interval_days", .integer)
                t.column("last_performed_at", .text)
                t.column("next_due_date", .text)
                t.column("is_enabled", .integer).notNull().defaults(to: 1)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.uniqueKey(["tool_id", "maintenance_type_id"])
            }

            // Tool Maintenance Records
            try db.create(table: "tool_maintenance_records") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("tool_id", .integer).notNull().references("tools")
                t.column("maintenance_type_id", .integer).notNull()
                    .references("tool_maintenance_types")
                t.column("service_date", .text).notNull()
                t.column("cost", .double)
                t.column("vendor", .text)
                t.column("description", .text)
                t.column("performed_by", .integer).references("users")
                t.column("notes", .text)
                t.column("calibration_certificate", .text)
                t.column("calibration_provider", .text)
                t.column("calibration_standard", .text)
                t.column("calibration_result", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            // Customers
            try db.create(table: "customers") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("company_name", .text)
                t.column("email", .text)
                t.column("phone", .text)
                t.column("address", .text)
                t.column("city", .text)
                t.column("state", .text)
                t.column("zip", .text)
                t.column("notes", .text)
                t.column("is_active", .integer).defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }

            // General Contractors
            try db.create(table: "general_contractors") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("company_name", .text).notNull()
                t.column("contact_name", .text)
                t.column("email", .text)
                t.column("phone", .text)
                t.column("address", .text)
                t.column("city", .text)
                t.column("state", .text)
                t.column("zip", .text)
                t.column("relationship", .text).defaults(to: "we_work_for_them")
                t.column("notes", .text)
                t.column("is_active", .integer).defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }

            // Employee Default Schedules
            try db.create(table: "employee_default_schedules") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .integer).notNull()
                    .references("users", onDelete: .cascade)
                t.column("day_of_week", .integer).notNull()
                t.column("start_time", .text).defaults(to: "07:00")
                t.column("end_time", .text).defaults(to: "15:30")
                t.column("lunch_start", .text)
                t.column("lunch_end", .text)
                t.column("is_working_day", .integer).defaults(to: 1)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.uniqueKey(["user_id", "day_of_week"])
            }

            // Schedule Exceptions
            try db.create(table: "schedule_exceptions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .integer).notNull()
                    .references("users", onDelete: .cascade)
                t.column("exception_date", .text).notNull()
                t.column("exception_type", .text).notNull()
                t.column("start_time", .text)
                t.column("end_time", .text)
                t.column("lunch_start", .text)
                t.column("lunch_end", .text)
                t.column("is_approved", .integer).defaults(to: 0)
                t.column("approved_by", .integer).references("users")
                t.column("approved_at", .text)
                t.column("reason", .text)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["user_id", "exception_date"])
            }

            // Job Dispatch
            try db.create(table: "job_dispatch") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("job_id", .integer).notNull()
                    .references("jobs", onDelete: .cascade)
                t.column("user_id", .integer).notNull()
                    .references("users", onDelete: .cascade)
                t.column("dispatch_date", .text).notNull()
                t.column("shift_start", .text)
                t.column("shift_end", .text)
                t.column("lunch_start", .text)
                t.column("lunch_end", .text)
                t.column("role_on_job", .text).defaults(to: "worker")
                t.column("status", .text).defaults(to: "scheduled")
                t.column("dispatched_by", .integer).references("users")
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["user_id", "dispatch_date", "job_id"])
            }
            try db.create(index: "idx_dispatch_date", on: "job_dispatch", columns: ["dispatch_date"])

            // Subcontractor Schedules
            try db.create(table: "subcontractor_schedules") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("job_id", .integer).notNull()
                    .references("jobs", onDelete: .cascade)
                t.column("gc_id", .integer).notNull()
                    .references("general_contractors", onDelete: .cascade)
                t.column("scheduled_date", .text).notNull()
                t.column("arrival_time", .text)
                t.column("departure_time", .text)
                t.column("scope_of_work", .text)
                t.column("status", .text).defaults(to: "scheduled")
                t.column("notes", .text)
                t.column("created_by", .integer).references("users")
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["job_id", "gc_id", "scheduled_date"])
            }
        }
    }
}

// MARK: - 007: Chat

extension AppDatabase {
    private static func registerMigration007Chat(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("007_chat") { db in
            try db.create(table: "chat_channels") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("channel_type", .text).notNull().defaults(to: "job")
                t.column("job_id", .integer).references("jobs")
                t.column("name", .text)
                t.column("created_by", .integer).notNull().references("users")
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_chat_channels_job", on: "chat_channels", columns: ["job_id"])

            try db.create(table: "chat_channel_members") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("channel_id", .integer).notNull().references("chat_channels")
                t.column("user_id", .integer).notNull().references("users")
                t.column("role", .text).notNull().defaults(to: "member")
                t.column("muted_until", .text)
                t.column("joined_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("left_at", .text)
                t.column("deleted_at", .text)
                t.uniqueKey(["channel_id", "user_id"])
            }

            try db.create(table: "qa_threads") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("channel_id", .integer).references("chat_channels")
                t.column("job_id", .integer).notNull().references("jobs")
                t.column("asked_by", .integer).notNull().references("users")
                t.column("subject", .text).notNull()
                t.column("current_level", .text).notNull().defaults(to: "worker")
                t.column("assigned_to", .integer).references("users")
                t.column("status", .text).notNull().defaults(to: "open")
                t.column("priority", .text).notNull().defaults(to: "normal")
                t.column("answer_text", .text)
                t.column("answered_by", .integer).references("users")
                t.column("answered_at", .text)
                t.column("closed_at", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_qa_job", on: "qa_threads", columns: ["job_id"])
            try db.create(index: "idx_qa_status", on: "qa_threads", columns: ["status"])

            try db.create(table: "chat_messages") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("channel_id", .integer).notNull().references("chat_channels")
                t.column("sender_id", .integer).notNull().references("users")
                t.column("message_type", .text).notNull().defaults(to: "text")
                t.column("content", .text)
                t.column("media_path", .text)
                t.column("reply_to_id", .integer).references("chat_messages")
                t.column("pinned_at", .text)
                t.column("pinned_by", .integer).references("users")
                t.column("qa_thread_id", .integer).references("qa_threads")
                t.column("qa_level", .text)
                t.column("edited_at", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_cm_channel", on: "chat_messages", columns: ["channel_id", "created_at"])

            try db.create(table: "chat_read_receipts") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("channel_id", .integer).notNull().references("chat_channels")
                t.column("user_id", .integer).notNull().references("users")
                t.column("last_read_message_id", .integer).notNull()
                t.column("read_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
                t.uniqueKey(["channel_id", "user_id"])
            }

            try db.create(table: "chat_mentions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("message_id", .integer).notNull().references("chat_messages")
                t.column("mentioned_user_id", .integer).notNull().references("users")
                t.column("acknowledged_at", .text)
                t.column("deleted_at", .text)
            }
            try db.create(index: "idx_mentions_user", on: "chat_mentions", columns: ["mentioned_user_id", "acknowledged_at"])

            try db.create(table: "rfi_objects") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("qa_thread_id", .integer).notNull().references("qa_threads")
                t.column("job_id", .integer).notNull().references("jobs")
                t.column("gc_contact_id", .integer)
                t.column("subject", .text).notNull()
                t.column("body", .text).notNull()
                t.column("status", .text).notNull().defaults(to: "draft")
                t.column("response_text", .text)
                t.column("responded_at", .text)
                t.column("sent_via", .text)
                t.column("sent_at", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_rfi_qa", on: "rfi_objects", columns: ["qa_thread_id"])
        }
    }
}

// MARK: - 008: Soft Delete & Sync Infrastructure

extension AppDatabase {
    private static func registerMigration008SoftDeleteAndSync(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("008_soft_delete_and_sync") { db in
            // Conflict Log
            try db.create(table: "_conflict_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("table_name", .text).notNull()
                t.column("record_id", .text).notNull()
                t.column("field_name", .text).notNull()
                t.column("local_value", .text)
                t.column("remote_value", .text)
                t.column("winner", .text).notNull()
                t.column("local_device", .text).notNull()
                t.column("remote_device", .text).notNull()
                t.column("local_ts", .text).notNull()
                t.column("remote_ts", .text).notNull()
                t.column("resolved_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("reviewed", .integer).notNull().defaults(to: 0)
            }
            try db.create(index: "idx_conflict_log_table", on: "_conflict_log", columns: ["table_name", "record_id"])

            // Vector Clock
            try db.create(table: "_vector_clock") { t in
                t.column("device_id", .text).notNull()
                t.column("peer_id", .text).notNull()
                t.column("last_sequence", .integer).notNull().defaults(to: 0)
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.primaryKey(["device_id", "peer_id"])
            }

            // Device Registry
            try db.create(table: "_device_registry") { t in
                t.primaryKey("device_id", .text)
                t.column("device_name", .text)
                t.column("platform", .text)
                t.column("role", .text)
                t.column("certificate", .text)
                t.column("last_seen_at", .text)
                t.column("last_sync_at", .text)
                t.column("is_trusted", .integer).notNull().defaults(to: 0)
                t.column("is_deactivated", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            // Auto-increment sequence trigger for change log
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS trg_change_log_sequence
                    AFTER INSERT ON _change_log
                    WHEN NEW.sequence IS NULL
                BEGIN
                    UPDATE _change_log
                    SET sequence = (SELECT COALESCE(MAX(sequence), 0) + 1 FROM _change_log)
                    WHERE id = NEW.id;
                END
                """)
        }
    }
}

// MARK: - 009: People Full

extension AppDatabase {
    private static func registerMigration009PeopleFull(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("009_people_full") { db in
            try db.create(table: "certifications") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .integer).notNull()
                    .references("users", onDelete: .cascade)
                t.column("cert_type", .text).notNull()
                t.column("cert_name", .text).notNull()
                t.column("issuing_authority", .text)
                t.column("cert_number", .text)
                t.column("issued_date", .text)
                t.column("expiry_date", .text)
                t.column("is_active", .integer).defaults(to: 1)
                t.column("notes", .text)
                t.column("document_path", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_certifications_user", on: "certifications", columns: ["user_id", "is_active"])
            try db.create(index: "idx_certifications_expiry", on: "certifications", columns: ["expiry_date"])

            try db.create(table: "wage_history") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .integer).notNull()
                    .references("users", onDelete: .cascade)
                t.column("pay_rate", .double).notNull()
                t.column("effective_date", .text).notNull()
                t.column("reason", .text)
                t.column("changed_by", .integer).references("users")
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }

            try db.create(table: "employee_notes") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .integer).notNull()
                    .references("users", onDelete: .cascade)
                t.column("note_type", .text).defaults(to: "general")
                t.column("title", .text).notNull()
                t.column("body", .text).notNull()
                t.column("is_private", .integer).defaults(to: 0)
                t.column("created_by", .integer).references("users")
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }

            try db.create(table: "user_skills") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .integer).notNull()
                    .references("users", onDelete: .cascade)
                t.column("skill_name", .text).notNull()
                t.column("proficiency", .text).defaults(to: "intermediate")
                t.column("years_experience", .double)
                t.column("verified_by", .integer).references("users")
                t.column("verified_at", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["user_id", "skill_name"])
            }

            try db.create(table: "employee_teams") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("description", .text)
                t.column("lead_user_id", .integer).references("users")
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            try db.create(table: "employee_team_members") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("team_id", .integer).notNull()
                    .references("employee_teams", onDelete: .cascade)
                t.column("user_id", .integer).notNull()
                    .references("users", onDelete: .cascade)
                t.column("role", .text).notNull().defaults(to: "member")
                t.column("joined_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
                t.uniqueKey(["team_id", "user_id"])
            }
        }
    }
}

// MARK: - 010: Costs & Receiving

extension AppDatabase {
    private static func registerMigration010CostsReceiving(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("010_costs_receiving") { db in
            try db.create(table: "billing_periods") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("job_id", .integer).references("jobs")
                t.column("period_start", .text).notNull()
                t.column("period_end", .text).notNull()
                t.column("locked_at", .text)
                t.column("locked_by", .integer).references("users")
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }

            try db.create(table: "receiving_sessions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("po_id", .integer).notNull().references("purchase_orders")
                t.column("started_by", .integer).notNull().references("users")
                t.column("mode", .text).notNull().defaults(to: "packing_slip")
                t.column("status", .text).notNull().defaults(to: "in_progress")
                t.column("completed_at", .text)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            try db.create(table: "receiving_session_items") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("session_id", .integer).notNull()
                    .references("receiving_sessions", onDelete: .cascade)
                t.column("po_line_id", .integer).notNull()
                    .references("po_line_items")
                t.column("expected_qty", .integer).notNull().defaults(to: 0)
                t.column("received_qty", .integer).notNull().defaults(to: 0)
                t.column("actual_cost", .double)
                t.column("scanned_at", .text)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
        }
    }
}

// MARK: - 011: Reports & PTO

extension AppDatabase {
    private static func registerMigration011ReportsPTO(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("011_reports_pto") { db in
            try db.create(table: "report_annotations") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("report_type", .text).notNull()
                t.column("context_key", .text).notNull()
                t.column("content", .text).notNull()
                t.column("author_id", .integer).notNull().references("users")
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            try db.create(table: "report_share_tokens") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("token", .text).notNull().unique()
                t.column("report_type", .text).notNull()
                t.column("context_params", .text).notNull().defaults(to: "{}")
                t.column("label", .text)
                t.column("created_by", .integer).notNull().references("users")
                t.column("expires_at", .text)
                t.column("last_accessed_at", .text)
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            try db.create(table: "report_templates") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("report_type", .text).notNull()
                t.column("config_json", .text).notNull().defaults(to: "{}")
                t.column("created_by", .integer).notNull().references("users")
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            try db.create(table: "pto_policies") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .integer).notNull().references("users")
                t.column("policy_name", .text).notNull().defaults(to: "Standard PTO")
                t.column("accrual_rate", .double).notNull().defaults(to: 3.33)
                t.column("accrual_period", .text).notNull().defaults(to: "biweekly")
                t.column("max_balance", .double)
                t.column("carryover_limit", .double)
                t.column("start_date", .text).notNull()
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            try db.create(table: "pto_transactions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .integer).notNull().references("users")
                t.column("transaction_type", .text).notNull()
                t.column("hours", .double).notNull()
                t.column("balance_after", .double).notNull()
                t.column("reference_id", .integer)
                t.column("reference_type", .text)
                t.column("note", .text)
                t.column("effective_date", .text).notNull()
                t.column("created_by", .integer).references("users")
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
        }
    }
}

// MARK: - 012: Warehouse & Attachments

extension AppDatabase {
    private static func registerMigration012WarehouseAttachments(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("012_warehouse_attachments") { db in
            try db.create(table: "job_trailers") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("trailer_code", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("status", .text).notNull().defaults(to: "active")
                t.column("current_job_id", .integer).references("jobs")
                t.column("assigned_driver_user_id", .integer).references("users")
                t.column("notes", .text)
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }

            try db.create(table: "trailer_location_events") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("trailer_id", .integer).notNull()
                    .references("job_trailers", onDelete: .cascade)
                t.column("event_type", .text).notNull().defaults(to: "manual_update")
                t.column("location_kind", .text).notNull().defaults(to: "other")
                t.column("job_id", .integer).references("jobs")
                t.column("lat", .double)
                t.column("lng", .double)
                t.column("recorded_by", .integer).notNull().references("users")
                t.column("recorded_at", .text).defaults(sql: "(datetime('now'))")
                t.column("notes", .text)
            }

            try db.create(table: "order_attachments") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("entity_type", .text).notNull()
                t.column("entity_id", .integer).notNull()
                t.column("file_path", .text).notNull()
                t.column("file_name", .text).notNull()
                t.column("file_type", .text)
                t.column("file_size", .integer)
                t.column("description", .text)
                t.column("uploaded_by", .integer).references("users")
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_order_attachments_entity", on: "order_attachments", columns: ["entity_type", "entity_id"])
        }
    }
}

// MARK: - 013: Tools & Supplier Extras

extension AppDatabase {
    private static func registerMigration013ToolsSupplierExtras(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("013_tools_supplier_extras") { db in
            try db.create(table: "tool_depreciation_entries") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("tool_id", .integer).notNull()
                    .references("tools", onDelete: .cascade)
                t.column("year_number", .integer).notNull()
                t.column("fiscal_year", .text).notNull()
                t.column("beginning_value", .double).notNull()
                t.column("depreciation_amount", .double).notNull()
                t.column("accumulated", .double).notNull()
                t.column("ending_value", .double).notNull()
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.uniqueKey(["tool_id", "year_number"])
            }

            try db.create(table: "notebook_entry_tools") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("entry_id", .integer).notNull()
                    .references("notebook_entries", onDelete: .cascade)
                t.column("tool_id", .integer).notNull()
                    .references("tools", onDelete: .cascade)
                t.column("notes", .text)
                t.column("created_by", .integer).notNull().references("users")
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.uniqueKey(["entry_id", "tool_id"])
            }

            try db.create(table: "supplier_portal_tokens") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("supplier_id", .integer).notNull().references("suppliers")
                t.column("token", .text).notNull().unique()
                t.column("note", .text)
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("expires_at", .text)
                t.column("last_used_at", .text)
                t.column("created_by", .integer).references("users")
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            try db.create(table: "supplier_po_acknowledgments") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("po_id", .integer).notNull()
                    .references("purchase_orders").unique()
                t.column("supplier_id", .integer).notNull().references("suppliers")
                t.column("token_id", .integer).references("supplier_portal_tokens")
                t.column("estimated_delivery", .text)
                t.column("supplier_notes", .text)
                t.column("acknowledged_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }
        }
    }
}

// MARK: - 014: Contacts, Costs & Profiles

extension AppDatabase {
    private static func registerMigration014ContactsCostsProfiles(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("014_contacts_costs_profiles") { db in
            try db.create(table: "entity_contacts") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("entity_type", .text).notNull()
                t.column("entity_id", .integer).notNull()
                t.column("first_name", .text).notNull()
                t.column("last_name", .text).notNull().defaults(to: "")
                t.column("role", .text).notNull()
                t.column("phone", .text).notNull()
                t.column("email", .text)
                t.column("is_primary", .integer).defaults(to: 0)
                t.column("notes", .text)
                t.column("is_active", .integer).defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_entity_contacts_entity", on: "entity_contacts", columns: ["entity_type", "entity_id"])

            try db.create(table: "job_customers") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("job_id", .integer).notNull()
                    .references("jobs", onDelete: .cascade)
                t.column("customer_id", .integer).notNull()
                    .references("customers", onDelete: .cascade)
                t.column("contact_role", .text).defaults(to: "owner")
                t.column("is_primary", .integer).defaults(to: 0)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["job_id", "customer_id", "contact_role"])
            }

            try db.create(table: "job_general_contractors") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("job_id", .integer).notNull()
                    .references("jobs", onDelete: .cascade)
                t.column("gc_id", .integer).notNull()
                    .references("general_contractors", onDelete: .cascade)
                t.column("relationship", .text).notNull()
                t.column("contract_amount", .double)
                t.column("contract_number", .text)
                t.column("is_primary", .integer).defaults(to: 0)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["job_id", "gc_id"])
            }

            try db.create(table: "cost_layers") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("part_id", .integer).notNull().references("parts")
                t.column("purchase_date", .text).notNull()
                t.column("po_line_id", .integer).references("po_line_items")
                t.column("original_qty", .integer).notNull()
                t.column("remaining_qty", .integer).notNull()
                t.column("unit_cost", .double).notNull()
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_cost_layers_part", on: "cost_layers", columns: ["part_id", "remaining_qty"])

            try db.create(table: "company_cost_settings") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("setting_key", .text).notNull().unique()
                t.column("setting_value", .text).notNull()
                t.column("updated_by", .integer).references("users")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }
            // Seed default cost settings
            try db.execute(sql: """
                INSERT OR IGNORE INTO company_cost_settings (setting_key, setting_value)
                VALUES
                    ('default_margin_percent', '25'),
                    ('cost_method', 'weighted_average'),
                    ('auto_update_pricing', 'true')
                """)

            try db.create(table: "company_profiles") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("address_street", .text)
                t.column("address_city", .text)
                t.column("address_state", .text)
                t.column("address_zip", .text)
                t.column("phone", .text)
                t.column("email", .text)
                t.column("website", .text)
                t.column("logo_path", .text)
                t.column("contractor_license", .text)
                t.column("insurance_info", .text)
                t.column("tax_id", .text)
                t.column("is_primary", .integer).notNull().defaults(to: 0)
                t.column("branch_name", .text)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
        }
    }
}

// MARK: - 015: Job Team & Suppliers

extension AppDatabase {
    private static func registerMigration015JobTeamSuppliers(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("015_job_team_suppliers") { db in
            try db.create(table: "job_team_members") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("job_id", .integer).notNull()
                    .references("jobs", onDelete: .cascade)
                t.column("user_id", .integer).notNull().references("users")
                t.column("role", .text).notNull().defaults(to: "member")
                t.column("assigned_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("assigned_by", .integer).references("users")
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.uniqueKey(["job_id", "user_id"])
            }

            try db.create(table: "job_preferred_suppliers") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("job_id", .integer).notNull()
                    .references("jobs", onDelete: .cascade)
                t.column("supplier_id", .integer).notNull().references("suppliers")
                t.column("rank", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
                t.uniqueKey(["job_id", "supplier_id"])
            }
        }
    }
}

// MARK: - 016: Companions & Alternatives

extension AppDatabase {
    private static func registerMigration016CompanionsAlternatives(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("016_companions_alternatives") { db in
            try db.create(table: "type_color_links") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("type_id", .integer).notNull()
                    .references("part_types", onDelete: .cascade)
                t.column("color_id", .integer).notNull()
                    .references("part_colors", onDelete: .cascade)
                t.column("image_url", .text)
                t.column("sort_order", .integer).defaults(to: 0)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["type_id", "color_id"])
            }

            try db.create(table: "type_brand_links") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("type_id", .integer).notNull()
                    .references("part_types", onDelete: .cascade)
                t.column("brand_id", .integer)
                    .references("brands", onDelete: .cascade)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }

            try db.create(table: "companion_rules") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("description", .text)
                t.column("style_match", .text).notNull().defaults(to: "auto")
                t.column("qty_mode", .text).notNull().defaults(to: "sum")
                t.column("qty_ratio", .double).defaults(to: 1.0)
                t.column("is_active", .integer).defaults(to: 1)
                t.column("created_by", .integer).references("users")
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }

            try db.create(table: "companion_rule_sources") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("rule_id", .integer).notNull()
                    .references("companion_rules", onDelete: .cascade)
                t.column("category_id", .integer).notNull()
                    .references("part_categories")
                t.column("style_id", .integer).references("part_styles")
            }

            try db.create(table: "companion_rule_targets") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("rule_id", .integer).notNull()
                    .references("companion_rules", onDelete: .cascade)
                t.column("category_id", .integer).notNull()
                    .references("part_categories")
                t.column("style_id", .integer).references("part_styles")
            }

            try db.create(table: "companion_suggestions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("rule_id", .integer)
                    .references("companion_rules", onDelete: .setNull)
                t.column("target_category_id", .integer).notNull()
                    .references("part_categories")
                t.column("target_style_id", .integer).references("part_styles")
                t.column("target_description", .text).notNull()
                t.column("suggested_qty", .integer).notNull()
                t.column("approved_qty", .integer)
                t.column("reason_type", .text).notNull().defaults(to: "rule")
                t.column("reason_text", .text).notNull()
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("triggered_by", .integer).references("users")
                t.column("decided_by", .integer).references("users")
                t.column("decided_at", .text)
                t.column("order_id", .integer)
                t.column("notes", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }

            try db.create(table: "companion_suggestion_sources") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("suggestion_id", .integer).notNull()
                    .references("companion_suggestions", onDelete: .cascade)
                t.column("category_id", .integer).notNull()
                    .references("part_categories")
                t.column("category_name", .text)
                t.column("style_id", .integer).references("part_styles")
                t.column("style_name", .text)
                t.column("qty", .integer).notNull()
            }

            try db.create(table: "co_occurrence_pairs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("category_a_id", .integer).notNull()
                    .references("part_categories")
                t.column("category_b_id", .integer).notNull()
                    .references("part_categories")
                t.column("co_occurrence_count", .integer).notNull().defaults(to: 0)
                t.column("total_jobs_a", .integer).notNull().defaults(to: 0)
                t.column("total_jobs_b", .integer).notNull().defaults(to: 0)
                t.column("avg_ratio_a_to_b", .double).defaults(to: 1.0)
                t.column("confidence", .double).defaults(to: 0.0)
                t.column("last_computed", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["category_a_id", "category_b_id"])
            }

            try db.create(table: "companion_feedback") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("suggestion_id", .integer).notNull()
                    .references("companion_suggestions")
                t.column("rule_id", .integer).references("companion_rules")
                t.column("action", .text).notNull()
                t.column("suggested_qty", .integer).notNull()
                t.column("final_qty", .integer)
                t.column("source_categories", .text)
                t.column("target_category_id", .integer)
                t.column("target_style_id", .integer)
                t.column("user_id", .integer).references("users")
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }

            try db.create(table: "part_alternatives") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("part_id", .integer).notNull()
                    .references("parts", onDelete: .cascade)
                t.column("alternative_part_id", .integer).notNull()
                    .references("parts", onDelete: .cascade)
                t.column("relationship", .text).notNull().defaults(to: "substitute")
                t.column("preference", .integer).notNull().defaults(to: 0)
                t.column("notes", .text)
                t.column("created_by", .integer).references("users")
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["part_id", "alternative_part_id"])
            }
        }
    }
}

// MARK: - 017: Permission Backfill

extension AppDatabase {
    private static func registerMigration017PermissionBackfill(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("017_permission_backfill") { db in
            // Admin hat: all 6 missing permissions
            let adminPerms = ["use_chat", "ask_qa", "send_rfi", "view_customers", "view_contractors", "manage_remote_sync"]
            for perm in adminPerms {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
                    SELECT id, ? FROM hats WHERE name = 'Admin'
                    """, arguments: [perm])
            }

            // Manager hat
            let managerPerms = ["use_chat", "view_chat", "manage_chat", "ask_qa", "send_rfi", "view_customers", "view_contractors"]
            for perm in managerPerms {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
                    SELECT id, ? FROM hats WHERE name = 'Manager'
                    """, arguments: [perm])
            }

            // Office hat
            let officePerms = ["use_chat", "view_chat", "ask_qa", "view_customers", "view_contractors"]
            for perm in officePerms {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
                    SELECT id, ? FROM hats WHERE name = 'Office'
                    """, arguments: [perm])
            }

            // Lead hat
            let leadPerms = ["use_chat", "view_chat", "ask_qa", "view_customers"]
            for perm in leadPerms {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
                    SELECT id, ? FROM hats WHERE name = 'Lead'
                    """, arguments: [perm])
            }

            // Worker hat
            let workerPerms = ["use_chat", "view_chat"]
            for perm in workerPerms {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
                    SELECT id, ? FROM hats WHERE name = 'Worker'
                    """, arguments: [perm])
            }
        }
    }
}

// MARK: - 018: AI Capabilities (Phase 12+)

extension AppDatabase {
    private static func registerMigration018AICapabilities(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("018_ai_capabilities") { db in

            // Text prediction history — local-only, per-user, not synced
            try db.create(table: "_text_history") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .integer).notNull()
                t.column("field_type", .text).notNull()
                t.column("text", .text).notNull()
                t.column("frequency", .integer).notNull().defaults(to: 1)
                t.column("last_used_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.uniqueKey(["user_id", "field_type", "text"])
            }
            try db.create(
                index: "idx_text_history_lookup",
                on: "_text_history",
                columns: ["user_id", "field_type", "last_used_at"]
            )

            // Part image feature vectors for camera matching
            try db.create(table: "part_image_features") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("part_id", .integer).notNull()
                    .references("parts", onDelete: .cascade)
                t.column("feature_vector", .blob).notNull()
                t.column("adapter_type", .text).notNull()
                t.column("image_hash", .text).notNull()
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.uniqueKey(["part_id", "adapter_type", "image_hash"])
            }
            try db.create(
                index: "idx_part_image_features_adapter",
                on: "part_image_features",
                columns: ["adapter_type"]
            )

            // Image match history — local-only diagnostics
            try db.create(table: "image_match_history") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("query_image_hash", .text).notNull()
                t.column("top_match_part_id", .integer)
                t.column("top_similarity", .double)
                t.column("user_confirmed_part_id", .integer)
                t.column("result_count", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            // Binary attachments for sync
            try db.create(table: "_binary_attachments") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("table_name", .text).notNull()
                t.column("record_id", .integer).notNull()
                t.column("attachment_type", .text).notNull()
                t.column("data_hash", .text).notNull().unique()
                t.column("data_size", .integer).notNull()
                t.column("sync_status", .text).notNull().defaults(to: "pending")
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(
                index: "idx_binary_attachments_sync",
                on: "_binary_attachments",
                columns: ["sync_status"]
            )
            try db.create(
                index: "idx_binary_attachments_record",
                on: "_binary_attachments",
                columns: ["table_name", "record_id"]
            )

            // Sync transfer log — tracks binary transfer sessions
            try db.create(table: "_sync_transfer_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("transfer_id", .text).notNull()
                t.column("table_name", .text).notNull()
                t.column("record_id", .integer).notNull()
                t.column("data_size", .integer).notNull()
                t.column("status", .text).notNull()
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
        }
    }
}
