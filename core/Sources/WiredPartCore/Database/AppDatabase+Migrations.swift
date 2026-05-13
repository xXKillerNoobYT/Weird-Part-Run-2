import Foundation
import GRDB

// MARK: - Safe Column Addition Helper (fixes #201)

/// Adds a column only if it doesn't already exist, avoiding both try? (which swallows real errors)
/// and duplicate-column crashes on re-run.
private func addColumnIfMissing(
    _ db: Database,
    table: String,
    column: String,
    type: Database.ColumnType,
    defaultValue: (any DatabaseValueConvertible)? = nil
) throws {
    let columns = try db.columns(in: table).map(\.name)
    guard !columns.contains(column) else { return }
    try db.alter(table: table) { t in
        if let def = defaultValue {
            t.add(column: column, type).defaults(to: def)
        } else {
            t.add(column: column, type)
        }
    }
}

// MARK: - Migration Registration
//
// Ports all 18 TypeScript migrations (000–017) to GRDB DatabaseMigrator.
// Each migration keeps its original name for schema parity tracking.
// Tables are created with their final column sets (including deleted_at from 008).

extension AppDatabase {
    static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        // NOTE: eraseDatabaseOnSchemaChange was removed (GitHub #101).
        // The app has 71+ proper incremental migrations — that flag wiped
        // the entire database whenever the schema fingerprint changed,
        // destroying all user data on every rebuild.

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
        registerMigration019BusinessProfiles(&migrator)
        registerMigration020WarehouseLocationsStockEntries(&migrator)
        registerMigration021MissingTables(&migrator)
        registerMigration022NotebookColumns(&migrator)
        registerMigration023PinSalt(&migrator)
        registerMigration024ScheduledDeletions(&migrator)
        registerMigration025PricingSystem(&migrator)
        registerMigration026SupplierEnhancements(&migrator)
        registerMigration027CompanionPolls(&migrator)
        registerMigration028SupplierBridge(&migrator)
        registerMigration029LocationStockTargets(&migrator)
        registerMigration030ForecastSettings(&migrator)
        registerMigration031TargetRecommendations(&migrator)
        registerMigration032JPOPerPartStatus(&migrator)
        registerMigration033PartChangeLog(&migrator)
        registerMigration034JobStages(&migrator)
        registerMigration035StagingBoxes(&migrator)
        registerMigration036ClockTodoIntegration(&migrator)
        registerMigration037ChatAttachments(&migrator)
        registerMigration038NotebookHierarchy(&migrator)
        registerMigration039NotebookTemplates(&migrator)
        registerMigration040WarehouseFloorPlans(&migrator)
        registerMigration041AuditConfidence(&migrator)
        registerMigration042BreakCompliance(&migrator)
        registerMigration043PaymentTracking(&migrator)
        registerMigration044JobClassifications(&migrator)
        registerMigration045TodoClassification(&migrator)
        registerMigration046HalfDayScheduling(&migrator)
        registerMigration047JobEstimation(&migrator)
        registerMigration048ToolDetailTables(&migrator)
        registerMigration049ToolTrades(&migrator)
        registerMigration050ToolMaintenanceConfigs(&migrator)
        registerMigration051VehicleStockAndTrailers(&migrator)
        registerMigration052TrailerMiniWarehouse(&migrator)
        registerMigration053PreTripInspection(&migrator)
        registerMigration054SavedReports(&migrator)
        registerMigration055OfficeChannel(&migrator)
        registerMigration056AIConversations(&migrator)
        registerMigration057WishlistItems(&migrator)
        registerMigration058BackgroundTaskLog(&migrator)
        registerMigration059MultiUserAuditAssignments(&migrator)
        registerMigration060PermissionKeysExpansion(&migrator)
        registerMigration061AuditSessionMetadata(&migrator)
        registerMigration062AuditCountedQty(&migrator)
        registerMigration063FixContractorNotesFKs(&migrator)
        registerMigration064TimeOffRequestGroups(&migrator)
        registerMigration065ColorPartNumbers(&migrator)
        registerMigration066BrandSupplierCarryStatus(&migrator)
        registerMigration067CascadePricingCosts(&migrator)
        registerMigration068WarehouseZonesProgressV2(&migrator)
        registerMigration069ScheduleConfigTables(&migrator)
        registerMigration070WishlistItemsV2(&migrator)
        registerMigration071FlexPool(&migrator)
        registerMigration072CompanySetupDraft(&migrator)
        registerMigration073FloorPlanGridDimensions(&migrator)
        registerMigration074ColorBrandSKUs(&migrator)
        registerMigration075CompanionFeedbackNullableSuggestionId(&migrator)
        registerMigration076StockMovementsCompositeIndex(&migrator)
        registerMigration077VehicleIssueReports(&migrator)
        registerMigration078PartsRecommendationPermissions(&migrator)
        registerMigration079VehicleLocationLogsIndex(&migrator)
        registerMigration080InspectionRecordsVehiclePerformedAtIndex(&migrator)
        registerMigration081POLineResolvedBrand(&migrator)
        registerMigration082PartsFieldTimestamps(&migrator)
        registerMigration083StructuredEstimationReviews(&migrator)
        registerMigration084SyncedTableFieldTimestamps(&migrator)
        registerMigration085CoOccurrenceHierarchyUniqueness(&migrator)
        registerMigration086PartsAutoAddWishlistToggle(&migrator)
        registerMigration087WishlistLocationRouting(&migrator)
        registerMigration088WarehouseOnboardingNineStepProgress(&migrator)
        registerMigration089BreakPolicyPresets(&migrator)
    }

    // MARK: - Migration 039: Notebook Templates

    private static func registerMigration039NotebookTemplates(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("039_notebook_templates") { db in
            // Drop the old notebook_templates from migration 004 and recreate with new schema
            try? db.drop(table: "template_entries")
            try? db.drop(table: "template_sections")
            try? db.drop(table: "notebook_templates")
            try db.create(table: "notebook_templates") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("description", .text)
                t.column("template_type", .text).notNull().defaults(to: "job")
                t.column("category", .text)
                t.column("template_data", .text).notNull()
                t.column("is_default", .integer).notNull().defaults(to: 0)
                t.column("created_by", .integer).references("users")
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }
        }
    }

    // MARK: - Migration 040: Warehouse Floor Plans

    private static func registerMigration040WarehouseFloorPlans(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("040_warehouse_floor_plans") { db in
            // Floor plans
            try db.create(table: "warehouse_floor_plans") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("width_inches", .integer).notNull()
                t.column("length_inches", .integer).notNull()
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }

            // Non-storage features on the floor plan (doors, walkways, etc.)
            try db.create(table: "warehouse_floor_features") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("floor_plan_id", .integer).notNull()
                    .references("warehouse_floor_plans", onDelete: .cascade)
                t.column("feature_type", .text).notNull()
                t.column("label", .text)
                t.column("grid_x", .integer).notNull()
                t.column("grid_y", .integer).notNull()
                t.column("grid_width", .integer).notNull().defaults(to: 1)
                t.column("grid_height", .integer).notNull().defaults(to: 1)
                t.column("rotation", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }

            // Physical storage units placed on the floor plan
            try db.create(table: "warehouse_storage_units") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("floor_plan_id", .integer).notNull()
                    .references("warehouse_floor_plans", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("unit_type", .text).notNull()
                t.column("row_number", .text)
                t.column("unit_number", .text)
                t.column("width_inches", .integer)
                t.column("depth_inches", .integer)
                t.column("height_inches", .integer)
                t.column("grid_x", .integer)
                t.column("grid_y", .integer)
                t.column("grid_width", .integer).defaults(to: 1)
                t.column("grid_height", .integer).defaults(to: 1)
                t.column("rotation", .integer).notNull().defaults(to: 0)
                t.column("front_face", .text).defaults(to: "south")
                t.column("is_movable", .integer).notNull().defaults(to: 0)
                t.column("is_job_ready", .integer).notNull().defaults(to: 0)
                t.column("home_area_id", .integer)
                t.column("current_location_type", .text)
                t.column("current_location_id", .integer)
                t.column("assigned_to", .integer).references("users")
                t.column("is_configured", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }

            // Levels within a storage unit (shelves, trays, drawers)
            try db.create(table: "warehouse_storage_levels") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("unit_id", .integer).notNull()
                    .references("warehouse_storage_units", onDelete: .cascade)
                t.column("level_code", .text).notNull()
                t.column("level_name", .text)
                t.column("level_order", .integer).notNull().defaults(to: 0)
                t.column("height_inches", .integer)
                t.column("area_count", .integer).notNull().defaults(to: 1)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }

            // Individual areas within a level — where parts live
            try db.create(table: "warehouse_storage_areas") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("level_id", .integer).notNull()
                    .references("warehouse_storage_levels", onDelete: .cascade)
                t.column("area_code", .text).notNull()
                t.column("area_number", .integer).notNull()
                t.column("width_inches", .integer)
                t.column("has_qr_code", .integer).notNull().defaults(to: 0)
                t.column("has_sticker", .integer).notNull().defaults(to: 0)
                t.column("full_location_code", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }

            // Optional bins within areas — one part type per bin
            try db.create(table: "warehouse_bins") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("area_id", .integer).notNull()
                    .references("warehouse_storage_areas", onDelete: .cascade)
                t.column("bin_code", .text).notNull()
                t.column("bin_number", .integer).notNull()
                t.column("is_fixed", .integer).notNull().defaults(to: 0)
                t.column("assigned_part_id", .integer).references("parts")
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }

            // Links parts to their home storage area
            try db.create(table: "warehouse_part_assignments") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("part_id", .integer).notNull()
                    .references("parts", onDelete: .cascade)
                t.column("area_id", .integer).notNull()
                    .references("warehouse_storage_areas", onDelete: .cascade)
                t.column("is_home", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
                t.uniqueKey(["part_id", "area_id"])
            }

            // User position tracking for warehouse navigation
            try db.create(table: "warehouse_user_positions") { t in
                t.column("user_id", .integer).notNull().primaryKey()
                    .references("users", onDelete: .cascade)
                t.column("area_id", .integer).notNull()
                    .references("warehouse_storage_areas", onDelete: .cascade)
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }

            // Onboarding wizard progress tracking
            try db.create(table: "warehouse_onboarding_progress") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("floor_plan_id", .integer)
                    .references("warehouse_floor_plans")
                t.column("current_step", .integer).notNull().defaults(to: 1)
                t.column("step1_complete", .integer).notNull().defaults(to: 0)
                t.column("step2_complete", .integer).notNull().defaults(to: 0)
                t.column("step3_complete", .integer).notNull().defaults(to: 0)
                t.column("step4_progress", .text)
                t.column("step5_progress", .text)
                t.column("step6_progress", .text)
                t.column("started_at", .text).defaults(sql: "(datetime('now'))")
                t.column("completed_at", .text)
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }
        }
    }

    // MARK: - Migration 041: Audit Confidence System

    private static func registerMigration041AuditConfidence(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("041_audit_confidence") { db in
            // Part confidence tracking — per part+area confidence scores
            try db.create(table: "part_confidence") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("part_id", .integer).notNull()
                    .references("parts", onDelete: .cascade)
                t.column("area_id", .integer).notNull()
                    .references("warehouse_storage_areas", onDelete: .cascade)
                t.column("confidence_percent", .double).notNull().defaults(to: 0.0)
                t.column("reliability_level", .integer).notNull().defaults(to: 0)
                t.column("last_audit_date", .text)
                t.column("last_audit_by", .integer).references("users")
                t.column("last_audit_count", .integer)
                t.column("system_count", .integer).notNull().defaults(to: 0)
                t.column("decay_rate", .double).notNull().defaults(to: 0.066)
                t.column("movement_decay_factor", .double).notNull().defaults(to: 1.0)
                t.column("clean_audit_streak", .integer).notNull().defaults(to: 0)
                t.column("misplacement_count", .integer).notNull().defaults(to: 0)
                t.column("last_misplacement_date", .text)
                t.column("total_audit_count", .integer).notNull().defaults(to: 0)
                t.column("total_variance_dollars", .double).notNull().defaults(to: 0.0)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["part_id", "area_id"])
            }

            // Audit sessions v2 — supports multiple session types
            try db.create(table: "audit_sessions_v2") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("session_type", .text).notNull().defaults(to: "count")
                t.column("started_by", .integer).notNull().references("users")
                t.column("floor_plan_id", .integer).references("warehouse_floor_plans")
                t.column("target_area_id", .integer).references("warehouse_storage_areas")
                t.column("target_unit_id", .integer).references("warehouse_storage_units")
                t.column("status", .text).notNull().defaults(to: "active")
                t.column("parts_counted", .integer).notNull().defaults(to: 0)
                t.column("discrepancies_found", .integer).notNull().defaults(to: 0)
                t.column("misplaced_found", .integer).notNull().defaults(to: 0)
                t.column("started_at", .text).defaults(sql: "(datetime('now'))")
                t.column("completed_at", .text)
                t.column("deleted_at", .text)
            }

            // Individual audit counts within a session
            try db.create(table: "audit_counts") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("session_id", .integer).notNull()
                    .references("audit_sessions_v2", onDelete: .cascade)
                t.column("part_id", .integer).notNull().references("parts")
                t.column("area_id", .integer).notNull()
                    .references("warehouse_storage_areas")
                t.column("system_count", .integer).notNull()
                t.column("user_count", .integer).notNull()
                t.column("variance", .integer).notNull()
                t.column("variance_dollars", .double).notNull().defaults(to: 0.0)
                t.column("variance_percent", .double).notNull().defaults(to: 0.0)
                t.column("result", .text).notNull()
                t.column("counted_by", .integer).notNull().references("users")
                t.column("counted_at", .text).defaults(sql: "(datetime('now'))")
            }

            // Log of parts found in wrong locations
            try db.create(table: "misplaced_parts_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("part_id", .integer).notNull().references("parts")
                t.column("found_at_area_id", .integer).notNull()
                    .references("warehouse_storage_areas")
                t.column("home_area_id", .integer)
                    .references("warehouse_storage_areas")
                t.column("qty_found", .integer).notNull()
                t.column("resolution", .text).notNull().defaults(to: "pending")
                t.column("resolved_by", .integer).references("users")
                t.column("resolved_at", .text)
                t.column("found_by", .integer).notNull().references("users")
                t.column("found_at", .text).defaults(sql: "(datetime('now'))")
            }

            // Per-user warehouse reliability ratings
            try db.create(table: "user_warehouse_ratings") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .integer).notNull()
                    .references("users", onDelete: .cascade)
                t.column("overall_rating", .double).notNull().defaults(to: 5.0)
                t.column("accuracy_rating", .double).notNull().defaults(to: 5.0)
                t.column("effort_rating", .double).notNull().defaults(to: 5.0)
                t.column("placement_rating", .double).notNull().defaults(to: 5.0)
                t.column("wizard_compliance", .double).notNull().defaults(to: 5.0)
                t.column("speed_rating", .double).notNull().defaults(to: 5.0)
                t.column("proactive_rating", .double).notNull().defaults(to: 5.0)
                t.column("total_audits", .integer).notNull().defaults(to: 0)
                t.column("total_accurate", .integer).notNull().defaults(to: 0)
                t.column("total_misplacements_found", .integer).notNull().defaults(to: 0)
                t.column("total_proactive_fixes", .integer).notNull().defaults(to: 0)
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["user_id"])
            }

            // Per-area organization quality ratings
            try db.create(table: "organization_ratings") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("area_id", .integer).notNull()
                    .references("warehouse_storage_areas", onDelete: .cascade)
                t.column("overall_rating", .double).notNull().defaults(to: 5.0)
                t.column("labels_accurate", .integer).notNull().defaults(to: 0)
                t.column("parts_in_home", .integer).notNull().defaults(to: 0)
                t.column("no_duplicates", .integer).notNull().defaults(to: 0)
                t.column("not_overcrowded", .integer).notNull().defaults(to: 0)
                t.column("bins_assigned", .integer).notNull().defaults(to: 0)
                t.column("similar_parts_nearby", .integer).notNull().defaults(to: 0)
                t.column("clean_audit_count", .integer).notNull().defaults(to: 0)
                t.column("last_org_check", .text)
                t.column("last_org_check_by", .integer).references("users")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["area_id"])
            }

            // Consolidation suggestions when parts are spread across multiple areas
            try db.create(table: "consolidation_votes") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("part_id", .integer).notNull().references("parts")
                t.column("current_areas", .text).notNull()
                t.column("chosen_area_id", .integer)
                    .references("warehouse_storage_areas")
                t.column("status", .text).notNull().defaults(to: "voting")
                t.column("manager_override", .integer).notNull().defaults(to: 0)
                t.column("dismiss_reason", .text)
                t.column("ignore_count", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("decided_at", .text)
                t.column("deleted_at", .text)
            }

            // Individual votes on consolidation suggestions
            try db.create(table: "consolidation_vote_entries") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("vote_id", .integer).notNull()
                    .references("consolidation_votes", onDelete: .cascade)
                t.column("user_id", .integer).notNull().references("users")
                t.column("chosen_area_id", .integer).notNull()
                    .references("warehouse_storage_areas")
                t.column("voted_at", .text).defaults(sql: "(datetime('now'))")
            }
        }
    }

    // MARK: - Migration 042: Break/Lunch Compliance

    private static func registerMigration042BreakCompliance(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("042_break_compliance") { db in
            // Break/lunch policies — state and company rules
            try db.create(table: "break_policies") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("state_code", .text)
                t.column("policy_type", .text).notNull()
                t.column("work_day_hours", .integer).notNull().defaults(to: 8)
                t.column("lunch_minutes", .integer).notNull().defaults(to: 30)
                t.column("break_count", .integer).notNull().defaults(to: 2)
                t.column("break_minutes", .integer).notNull().defaults(to: 15)
                t.column("data_source", .text)
                t.column("data_date", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }

            // Break bonuses for sticking to state minimums
            try db.create(table: "break_bonuses") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("policy_id", .integer).notNull()
                    .references("break_policies")
                t.column("bonus_type", .text).notNull()
                t.column("bonus_amount", .double).notNull().defaults(to: 0.0)
                t.column("description", .text)
                t.column("is_enabled", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }

            // Individual break records per user per day
            try db.create(table: "break_records") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .integer).notNull().references("users")
                t.column("labor_entry_id", .integer).references("labor_entries")
                t.column("break_type", .text).notNull()
                t.column("started_at", .text).notNull()
                t.column("ended_at", .text)
                t.column("duration_minutes", .integer)
                t.column("is_paid", .integer).notNull().defaults(to: 1)
                t.column("auto_filled", .integer).notNull().defaults(to: 0)
                t.column("timer_duration_minutes", .integer)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }

            // Company-level break settings
            try db.create(table: "company_break_settings") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("state_code", .text).notNull().defaults(to: "WY")
                t.column("rounding_minutes", .integer).notNull().defaults(to: 15)
                t.column("rounding_enabled", .integer).notNull().defaults(to: 0)
                t.column("auto_fill_breaks", .integer).notNull().defaults(to: 1)
                t.column("default_morning_break", .text).defaults(to: "10:00")
                t.column("default_lunch", .text).defaults(to: "12:00")
                t.column("default_afternoon_break", .text).defaults(to: "14:30")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }

            try seedBreakPolicyPresets(db)

            // Seed default company settings
            try db.execute(sql: """
                INSERT INTO company_break_settings (state_code, rounding_minutes, rounding_enabled, auto_fill_breaks)
                VALUES ('WY', 15, 0, 1)
                """)
        }
    }

    private static func registerMigration070WishlistItemsV2(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("070_wishlist_items_v2") { db in
            // Approval flow fields: dismiss reason, auto-approve timestamp, certainty score
            try db.execute(sql: "ALTER TABLE wishlist_items ADD COLUMN dismiss_reason TEXT")
            try db.execute(sql: "ALTER TABLE wishlist_items ADD COLUMN auto_approve_at TEXT")
            try db.execute(sql: "ALTER TABLE wishlist_items ADD COLUMN certainty_score REAL")
        }
    }

    private static func registerMigration071FlexPool(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("071_flex_pool") { db in
            // Flex pool: jobs managers mark as claimable by qualified workers
            // is_flex_pool: 1 = job is in the flex pool and available to claim
            // flex_pool_team_filter: JSON array of team IDs allowed to claim, NULL = all teams
            // flex_pool_user_filter: JSON array of user IDs allowed to claim, NULL = all users
            try db.execute(sql: "ALTER TABLE jobs ADD COLUMN is_flex_pool INTEGER NOT NULL DEFAULT 0")
            try db.execute(sql: "ALTER TABLE jobs ADD COLUMN flex_pool_team_filter TEXT")
            try db.execute(sql: "ALTER TABLE jobs ADD COLUMN flex_pool_user_filter TEXT")
        }
    }

    private static func registerMigration073FloorPlanGridDimensions(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("073_floor_plan_grid_dimensions") { db in
            // Add user-defined grid dimensions to floor plans (PE-040).
            // Before this migration, grid size was derived from width_inches / 60,
            // which meant users could never set it explicitly. Now grid_rows and
            // grid_cols are persisted directly so the wizard can offer a
            // dimensions-first flow.
            try db.alter(table: "warehouse_floor_plans") { t in
                t.add(column: "grid_rows", .integer)
                t.add(column: "grid_cols", .integer)
            }
        }
    }

    private static func registerMigration074ColorBrandSKUs(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("074_color_brand_skus") { db in
            // PE-COLORS Phase 1 — distinct SKU per (color, brand, type) combination.
            // Fills the gap described in colors-parts-redesign.md: the same physical color
            // can appear under multiple brands (each with its own part number / cost), and the
            // same (color, brand) pair can legitimately appear under multiple types.
            try db.create(table: "color_brand_skus") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("color_id", .integer).notNull().references("part_colors", onDelete: .cascade)
                t.column("brand_id", .integer).notNull().references("brands", onDelete: .cascade)
                t.column("type_id", .integer).notNull().references("part_types", onDelete: .cascade)
                t.column("part_number", .text)
                t.column("unit_cost", .double)
                t.column("stock_qty", .integer).notNull().defaults(to: 0)
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.uniqueKey(["color_id", "brand_id", "type_id"])
            }
            try db.create(
                index: "idx_color_brand_skus_lookup",
                on: "color_brand_skus",
                columns: ["type_id", "brand_id", "color_id"]
            )
            try db.create(
                index: "idx_color_brand_skus_color",
                on: "color_brand_skus",
                columns: ["color_id"]
            )

            // "General mode" on order line items — brand deferred to supplier selection time.
            // CHECK constraint prevents stale values without a separate enum table.
            try db.alter(table: "jpo_line_items") { t in
                t.add(column: "brand_selection_mode", .text).defaults(to: "specific")
            }
            try db.alter(table: "po_line_items") { t in
                t.add(column: "brand_selection_mode", .text).defaults(to: "specific")
            }
        }
    }

    private static func registerMigration072CompanySetupDraft(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("072_company_setup_draft") { db in
            // Wizard draft state — moves PII out of unencrypted UserDefaults into
            // SQLite (encrypted at rest via iOS Data Protection).
            // At most one row exists; deleted when the wizard completes.
            try db.create(table: "company_setup_draft", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("current_step", .integer).notNull().defaults(to: 0)
                t.column("completed_steps", .text)   // JSON-encoded Set<Int>
                t.column("skipped_steps", .text)      // JSON-encoded Set<Int>
                t.column("name", .text)
                t.column("address", .text)
                t.column("phone", .text)
                t.column("email", .text)
                t.column("selected_state", .text)
                t.column("updated_at", .datetime).notNull().defaults(sql: "(datetime('now'))")
            }
        }
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
                t.column("auto_add_to_wishlist", .integer).notNull().defaults(to: 0)
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

// MARK: - 019: Business Profiles

extension AppDatabase {
    private static func registerMigration019BusinessProfiles(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("019_business_profiles") { db in

            // Business / company profile — one row per company on this device
            try db.create(table: "business_profiles") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("company_name", .text).notNull()
                t.column("industry", .text)
                t.column("address", .text)
                t.column("city", .text)
                t.column("state", .text)
                t.column("zip", .text)
                t.column("phone", .text)
                t.column("email", .text)
                t.column("website", .text)
                t.column("logo_data", .blob)
                t.column("timezone", .text).defaults(to: "America/Chicago")
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
        }
    }
}

// MARK: - 020: Warehouse Locations & Stock Entries

extension AppDatabase {
    private static func registerMigration020WarehouseLocationsStockEntries(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("020_warehouse_locations_stock_entries") { db in

            // Warehouse locations — physical warehouses, shops, storage yards
            try db.create(table: "warehouse_locations") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("address", .text)
                t.column("location_type", .text).notNull().defaults(to: "warehouse")
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }

            // Stock entries — per-part, per-warehouse quantity tracking
            try db.create(table: "stock_entries") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("part_id", .integer).notNull()
                    .references("parts", onDelete: .cascade)
                t.column("warehouse_id", .integer).notNull()
                    .references("warehouse_locations", onDelete: .cascade)
                t.column("quantity", .integer).notNull().defaults(to: 0)
                t.column("bin_location", .text)
                t.column("last_counted_at", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_stock_entries_part", on: "stock_entries", columns: ["part_id"])
            try db.create(index: "idx_stock_entries_warehouse", on: "stock_entries", columns: ["warehouse_id"])
            try db.create(index: "idx_stock_entries_part_wh", on: "stock_entries", columns: ["part_id", "warehouse_id"])
        }
    }
}

// MARK: - 021: Missing Tables (Fleet, Scheduling, Orders, Costs, Chat)

extension AppDatabase {
    private static func registerMigration021MissingTables(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("021_missing_tables") { db in

            // ── Fleet: Vehicle Delivery Items ──
            try db.create(table: "vehicle_delivery_items") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("vehicle_id", .integer).notNull().references("vehicles", onDelete: .cascade)
                t.column("job_id", .integer).references("jobs")
                t.column("po_id", .integer).references("purchase_orders")
                t.column("description", .text)
                t.column("quantity", .integer).notNull().defaults(to: 1)
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("loaded_by", .integer).references("users")
                t.column("delivered_by", .integer).references("users")
                t.column("loaded_at", .text)
                t.column("delivered_at", .text)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_vdi_vehicle", on: "vehicle_delivery_items", columns: ["vehicle_id"])

            // ── Fleet: Vehicle Maintenance Types ──
            try db.create(table: "maintenance_types") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("description", .text)
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }

            // ── Fleet: Vehicle Maintenance Schedules ──
            try db.create(table: "maintenance_schedules") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("vehicle_id", .integer).notNull().references("vehicles", onDelete: .cascade)
                t.column("maintenance_type_id", .integer).notNull().references("maintenance_types")
                t.column("interval_miles", .integer)
                t.column("interval_days", .integer)
                t.column("last_performed_at", .text)
                t.column("last_performed_miles", .integer)
                t.column("next_due_date", .text)
                t.column("next_due_miles", .integer)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_maint_sched_vehicle", on: "maintenance_schedules", columns: ["vehicle_id"])

            // ── Fleet: Vehicle Maintenance Records ──
            try db.create(table: "maintenance_records") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("vehicle_id", .integer).notNull().references("vehicles", onDelete: .cascade)
                t.column("maintenance_type_id", .integer).references("maintenance_types")
                t.column("performed_at", .text).notNull()
                t.column("performed_by", .integer).references("users")
                t.column("odometer_reading", .integer)
                t.column("cost", .double)
                t.column("vendor", .text)
                t.column("description", .text)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_maint_rec_vehicle", on: "maintenance_records", columns: ["vehicle_id"])

            // ── Fleet: Mileage Logs ──
            try db.create(table: "mileage_logs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("vehicle_id", .integer).notNull().references("vehicles", onDelete: .cascade)
                t.column("user_id", .integer).notNull().references("users")
                t.column("log_date", .text).notNull()
                t.column("start_odometer", .integer)
                t.column("end_odometer", .integer)
                t.column("total_miles", .double)
                t.column("purpose", .text)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_mileage_vehicle", on: "mileage_logs", columns: ["vehicle_id"])
            try db.create(index: "idx_mileage_user", on: "mileage_logs", columns: ["user_id"])

            // ── Fleet: Trip Legs ──
            try db.create(table: "trip_legs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("mileage_log_id", .integer).notNull().references("mileage_logs", onDelete: .cascade)
                t.column("leg_type", .text).notNull().defaults(to: "job")
                t.column("from_location", .text)
                t.column("to_location", .text)
                t.column("miles", .double)
                t.column("job_id", .integer).references("jobs")
                t.column("notes", .text)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_trip_legs_log", on: "trip_legs", columns: ["mileage_log_id"])

            // ── Fleet: Mileage Reimbursements ──
            try db.create(table: "mileage_reimbursements") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .integer).notNull().references("users")
                t.column("mileage_log_id", .integer).references("mileage_logs")
                t.column("miles", .double).notNull()
                t.column("rate_per_mile", .double).notNull()
                t.column("amount", .double).notNull()
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("approved_by", .integer).references("users")
                t.column("approved_at", .text)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_reimburse_user", on: "mileage_reimbursements", columns: ["user_id"])

            // ── Fleet: Fuel Logs ──
            try db.create(table: "fuel_logs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("vehicle_id", .integer).notNull().references("vehicles", onDelete: .cascade)
                t.column("user_id", .integer).notNull().references("users")
                t.column("log_date", .text).notNull()
                t.column("gallons", .double)
                t.column("cost_per_gallon", .double)
                t.column("total_cost", .double)
                t.column("odometer_reading", .integer)
                t.column("station", .text)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_fuel_vehicle", on: "fuel_logs", columns: ["vehicle_id"])

            // ── Fleet: Trailer Stock Templates ──
            try db.create(table: "trailer_stock_templates") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("trailer_id", .integer).notNull().references("job_trailers", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_tst_trailer", on: "trailer_stock_templates", columns: ["trailer_id"])

            // ── Fleet: Trailer Stock Template Lines ──
            try db.create(table: "trailer_stock_template_lines") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("template_id", .integer).notNull().references("trailer_stock_templates", onDelete: .cascade)
                t.column("part_id", .integer).notNull().references("parts")
                t.column("target_qty", .integer).notNull().defaults(to: 1)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("deleted_at", .text)
            }
            try db.create(index: "idx_tstl_template", on: "trailer_stock_template_lines", columns: ["template_id"])

            // ── Scheduling: Dispatch Templates ──
            try db.create(table: "dispatch_templates") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("description", .text)
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }

            // ── Scheduling: Dispatch Template Members ──
            try db.create(table: "dispatch_template_members") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("template_id", .integer).notNull().references("dispatch_templates", onDelete: .cascade)
                t.column("user_id", .integer).notNull().references("users")
                t.column("role", .text).notNull().defaults(to: "worker")
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("deleted_at", .text)
            }
            try db.create(index: "idx_dtm_template", on: "dispatch_template_members", columns: ["template_id"])

            // ── Scheduling: Shift Patterns ──
            try db.create(table: "shift_patterns") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("description", .text)
                t.column("rotation_days", .integer).notNull().defaults(to: 7)
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }

            // ── Scheduling: Shift Pattern Days ──
            try db.create(table: "shift_pattern_days") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("pattern_id", .integer).notNull().references("shift_patterns", onDelete: .cascade)
                t.column("day_offset", .integer).notNull()
                t.column("start_time", .text)
                t.column("end_time", .text)
                t.column("is_off", .integer).notNull().defaults(to: 0)
                t.column("deleted_at", .text)
            }
            try db.create(index: "idx_spd_pattern", on: "shift_pattern_days", columns: ["pattern_id"])

            // ── Orders: PO-JPO Links ──
            try db.create(table: "po_jpo_links") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("po_id", .integer).notNull().references("purchase_orders", onDelete: .cascade)
                t.column("jpo_id", .integer).notNull().references("job_parts_orders", onDelete: .cascade)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["po_id", "jpo_id"])
            }

            // ── Orders: Staging Zones ──
            try db.create(table: "staging_zones") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("zone_type", .text).notNull().defaults(to: "receiving")
                t.column("warehouse_id", .integer).references("warehouse_locations")
                t.column("description", .text)
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }

            // ── Orders: Staging Items ──
            try db.create(table: "staging_items") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("staging_zone_id", .integer).notNull().references("staging_zones", onDelete: .cascade)
                t.column("part_id", .integer).references("parts")
                t.column("po_line_id", .integer).references("po_line_items")
                t.column("job_id", .integer).references("jobs")
                t.column("quantity", .integer).notNull().defaults(to: 1)
                t.column("status", .text).notNull().defaults(to: "staged")
                t.column("notes", .text)
                t.column("staged_by", .integer).references("users")
                t.column("staged_at", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_staging_zone", on: "staging_items", columns: ["staging_zone_id"])

            // ── Costs: PTO Balances ──
            try db.create(table: "pto_balances") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .integer).notNull().references("users")
                t.column("policy_id", .integer).notNull().references("pto_policies")
                t.column("balance", .double).notNull().defaults(to: 0)
                t.column("used", .double).notNull().defaults(to: 0)
                t.column("year", .integer).notNull()
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["user_id", "policy_id", "year"])
            }

            // ── Costs: Supplier Contact Ratings ──
            try db.create(table: "supplier_contact_ratings") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("supplier_id", .integer).notNull().references("suppliers", onDelete: .cascade)
                t.column("contact_type", .text).notNull()
                t.column("rater_id", .integer).notNull().references("users")
                t.column("category", .text).notNull()
                t.column("rating", .integer).notNull()
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_scr_supplier", on: "supplier_contact_ratings", columns: ["supplier_id"])

            // ── Costs: PO Conversations ──
            try db.create(table: "po_conversations") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("po_id", .integer).notNull().references("purchase_orders", onDelete: .cascade)
                t.column("entry_type", .text).notNull().defaults(to: "note")
                t.column("author_id", .integer).notNull().references("users")
                t.column("content", .text).notNull()
                t.column("is_internal", .integer).notNull().defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_po_conv_po", on: "po_conversations", columns: ["po_id"])

            // ── Costs: PO Groups ──
            try db.create(table: "po_groups") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("description", .text)
                t.column("created_by", .integer).notNull().references("users")
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }

            // ── Costs: PO Group Members ──
            try db.create(table: "po_group_members") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("group_id", .integer).notNull().references("po_groups", onDelete: .cascade)
                t.column("po_id", .integer).notNull().references("purchase_orders", onDelete: .cascade)
                t.column("added_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["group_id", "po_id"])
            }

            // ── Costs: Category Supplier Preferences ──
            try db.create(table: "category_supplier_preferences") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("category_id", .integer).notNull().references("part_categories", onDelete: .cascade)
                t.column("supplier_id", .integer).notNull().references("suppliers", onDelete: .cascade)
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["category_id", "supplier_id"])
            }

            // ── Costs: Job Supplier Preferences ──
            try db.create(table: "job_supplier_preferences") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("job_id", .integer).notNull().references("jobs", onDelete: .cascade)
                t.column("supplier_id", .integer).notNull().references("suppliers", onDelete: .cascade)
                t.column("is_excluded", .integer).notNull().defaults(to: 0)
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["job_id", "supplier_id"])
            }

            // ── Foundation: Add missing columns to notification_preferences ──
            try db.alter(table: "notification_preferences") { t in
                t.add(column: "sound", .text)
                t.add(column: "created_at", .text).defaults(sql: "(datetime('now'))")
            }

            // ── Chat: QA Escalations ──
            try db.create(table: "qa_escalations") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("thread_id", .integer).notNull().references("qa_threads", onDelete: .cascade)
                t.column("from_level", .text).notNull()
                t.column("to_level", .text).notNull()
                t.column("escalated_by", .integer).notNull().references("users")
                t.column("reason", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_qa_esc_thread", on: "qa_escalations", columns: ["thread_id"])
        }
    }
}

// MARK: - 022: Notebook Missing Columns

extension AppDatabase {
    private static func registerMigration022NotebookColumns(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("022_notebook_columns") { db in
            // The notebooks table was missing notebook_type, status, and content columns
            // that the NotebooksService queries and UI expect.
            try db.alter(table: "notebooks") { t in
                t.add(column: "notebook_type", .text).notNull().defaults(to: "general")
                t.add(column: "status", .text).notNull().defaults(to: "active")
                t.add(column: "content", .text)
            }

            // Backfill: notebooks linked to a job should have type "job"
            try db.execute(sql: """
                UPDATE notebooks SET notebook_type = 'job' WHERE job_id IS NOT NULL
                """)
        }
    }
}

// MARK: - 023: PIN Salt for Per-User Hashing

extension AppDatabase {
    private static func registerMigration023PinSalt(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("023_pin_salt") { db in
            // Add per-user salt column for secure PIN hashing.
            // Existing users get a NULL salt; on next login the system
            // will detect the legacy hash format, re-hash with a salt,
            // and store both the new hash and the salt.
            try db.alter(table: "users") { t in
                t.add(column: "pin_salt", .text)
            }
        }
    }
}

// MARK: - 025: Pricing System

extension AppDatabase {
    private static func registerMigration025PricingSystem(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("025_pricing_system") { db in
            // Hierarchical price tiers — set price/markup at any hierarchy level
            // Prices cascade: category → style → type → brand → part (most specific wins)
            try db.create(table: "pricing_tiers") { t in
                t.autoIncrementedPrimaryKey("id")
                // Exactly ONE of these should be set to define the tier level
                t.column("category_id", .integer).references("part_categories")
                t.column("style_id", .integer).references("part_styles")
                t.column("type_id", .integer).references("part_types")
                t.column("brand_id", .integer).references("brands")
                t.column("part_id", .integer).references("parts")
                // The actual pricing values
                t.column("markup_percent", .double)        // e.g. 50.0 = 50% markup
                t.column("margin_percent", .double)         // alternative: margin mode
                t.column("fixed_sell_price", .double)       // optional: override with fixed price
                t.column("set_by", .integer).references("users")
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            // Ensure only one active tier per hierarchy point
            try db.create(index: "idx_pricing_tiers_category", on: "pricing_tiers", columns: ["category_id"], condition: Column("deleted_at") == nil)
            try db.create(index: "idx_pricing_tiers_style", on: "pricing_tiers", columns: ["style_id"], condition: Column("deleted_at") == nil)
            try db.create(index: "idx_pricing_tiers_type", on: "pricing_tiers", columns: ["type_id"], condition: Column("deleted_at") == nil)
            try db.create(index: "idx_pricing_tiers_brand", on: "pricing_tiers", columns: ["brand_id"], condition: Column("deleted_at") == nil)
            try db.create(index: "idx_pricing_tiers_part", on: "pricing_tiers", columns: ["part_id"], condition: Column("deleted_at") == nil)

            // Price change history — every time a price/markup changes, log it
            try db.create(table: "price_history") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("part_id", .integer).references("parts")
                t.column("pricing_tier_id", .integer).references("pricing_tiers")
                t.column("change_type", .text).notNull()     // "cost_update", "markup_change", "margin_change", "tier_set", "tier_removed", "reset"
                t.column("old_value", .double)
                t.column("new_value", .double)
                t.column("old_sell_price", .double)
                t.column("new_sell_price", .double)
                t.column("source", .text)                     // "manual", "receiving", "po_update", "bulk_edit", "tier_cascade"
                t.column("source_id", .integer)               // PO id, receiving session id, etc.
                t.column("changed_by", .integer).references("users")
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_price_history_part", on: "price_history", columns: ["part_id", "created_at"])

            // Sale consumption records — track which FIFO batches were used for each sale
            // This enables LIFO returns: restore the most recently consumed batch
            try db.create(table: "cost_layer_consumptions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("cost_layer_id", .integer).notNull().references("cost_layers")
                t.column("part_id", .integer).notNull().references("parts")
                t.column("job_id", .integer).references("jobs")
                t.column("qty_consumed", .integer).notNull()
                t.column("unit_cost_at_sale", .double).notNull()  // locked cost from the batch
                t.column("sell_price_charged", .double)           // what the customer was charged
                t.column("supplier_id", .integer).references("suppliers") // which supplier this batch came from
                t.column("is_returned", .integer).notNull().defaults(to: 0) // 1 if this consumption was reversed by a return
                t.column("returned_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_consumptions_part_job", on: "cost_layer_consumptions", columns: ["part_id", "job_id"])
            try db.create(index: "idx_consumptions_layer", on: "cost_layer_consumptions", columns: ["cost_layer_id"])

            // Add new company cost settings
            try db.execute(sql: """
                INSERT OR IGNORE INTO company_cost_settings (setting_key, setting_value)
                VALUES
                    ('pricing_mode', 'markup'),
                    ('stale_price_threshold_days', '90'),
                    ('default_markup_percent', '50')
                """)
        }
    }
}

// MARK: - 024: Scheduled Deletions (Smart Delete)

extension AppDatabase {
    private static func registerMigration024ScheduledDeletions(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("024_scheduled_deletions") { db in
            try db.create(table: "scheduled_deletions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("entity_type", .text).notNull()       // "category", "style", "type", "brand", "color", "part"
                t.column("entity_id", .integer).notNull()
                t.column("entity_name", .text).notNull()        // human-readable name for display
                t.column("reason", .text)                        // why it's being deleted
                t.column("status", .text).notNull().defaults(to: "draining")  // "draining", "pending_approval", "approved", "cancelled"
                t.column("stock_at_schedule", .integer).defaults(to: 0)       // stock level when scheduled
                t.column("stock_reached_zero_at", .text)         // ISO8601 timestamp when stock first hit 0
                t.column("delete_after", .text)                  // ISO8601 timestamp = stock_reached_zero_at + 30 days
                t.column("alternative_part_id", .integer)        // recommended replacement part
                t.column("alternative_part_name", .text)         // cached name for display
                t.column("scheduled_by", .integer)               // user who initiated
                t.column("approved_by", .integer)                // user who approved final delete
                t.column("approved_at", .text)
                t.column("deleted_at", .text)                    // soft delete
                t.column("created_at", .text).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.column("updated_at", .text).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
        }
    }

    // MARK: - 026: Supplier Enhancements

    private static func registerMigration026SupplierEnhancements(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("026_supplier_enhancements") { db in
            // Add account number to suppliers (customer account # with this supplier)
            try db.alter(table: "suppliers") { t in
                t.add(column: "account_number", .text)
            }
        }
    }

    // MARK: - 027: Companion Polls & Auto-Discovery

    private static func registerMigration027CompanionPolls(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("027_companion_polls") { db in

            // -- ALTER existing tables --

            // Add type_id to sources and targets (rules can now match at type level)
            try db.alter(table: "companion_rule_sources") { t in
                t.add(column: "type_id", .integer).references("part_types")
            }
            try db.alter(table: "companion_rule_targets") { t in
                t.add(column: "type_id", .integer).references("part_types")
            }

            // Add brand matching + color auto-match flags to rules
            try db.alter(table: "companion_rules") { t in
                t.add(column: "try_match_brand", .integer).notNull().defaults(to: 0)
                t.add(column: "auto_color_match", .integer).notNull().defaults(to: 1)
                t.add(column: "parent_rule_id", .integer).references("companion_rules")
                t.add(column: "auto_delete_at", .text)
                t.add(column: "deleted_at", .text)
            }

            // Add points system + drill-down level to co_occurrence_pairs
            try db.alter(table: "co_occurrence_pairs") { t in
                t.add(column: "points", .integer).notNull().defaults(to: 0)
                t.add(column: "style_a_id", .integer).references("part_styles")
                t.add(column: "style_b_id", .integer).references("part_styles")
                t.add(column: "type_a_id", .integer).references("part_types")
                t.add(column: "type_b_id", .integer).references("part_types")
                t.add(column: "brand_a_id", .integer).references("brands")
                t.add(column: "brand_b_id", .integer).references("brands")
                t.add(column: "match_level", .text).notNull().defaults(to: "category")
                t.add(column: "rejection_count", .integer).notNull().defaults(to: 0)
                t.add(column: "is_blocked", .integer).notNull().defaults(to: 0)
                t.add(column: "tied_cooldown_until", .text)
            }

            // New indexes for co_occurrence drill-down
            try db.create(index: "idx_co_occurrence_level", on: "co_occurrence_pairs", columns: ["match_level", "points"])
            try db.create(index: "idx_co_occurrence_blocked", on: "co_occurrence_pairs", columns: ["is_blocked", "match_level"])

            // -- CREATE new tables --

            // companion_polls — one poll per auto-suggested companion rule
            try db.create(table: "companion_polls") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("co_occurrence_id", .integer).notNull()
                    .references("co_occurrence_pairs", onDelete: .cascade)
                t.column("proposed_rule_name", .text).notNull()
                t.column("proposed_rule_description", .text)
                t.column("source_category_id", .integer).references("part_categories")
                t.column("source_style_id", .integer).references("part_styles")
                t.column("source_type_id", .integer).references("part_types")
                t.column("target_category_id", .integer).references("part_categories")
                t.column("target_style_id", .integer).references("part_styles")
                t.column("target_type_id", .integer).references("part_types")
                t.column("match_level", .text).notNull().defaults(to: "category")
                t.column("try_match_brand", .integer).notNull().defaults(to: 0)
                t.column("auto_color_match", .integer).notNull().defaults(to: 1)
                t.column("status", .text).notNull().defaults(to: "active")
                t.column("admin_locked_result", .text)
                t.column("admin_locked_by", .integer).references("users")
                t.column("admin_locked_at", .text)
                t.column("result", .text)
                t.column("created_rule_id", .integer).references("companion_rules")
                t.column("start_date", .text).notNull().defaults(sql: "(date('now'))")
                t.column("end_date", .text).notNull().defaults(sql: "(date('now', '+30 days'))")
                t.column("completed_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }

            // companion_votes — one vote per user per poll
            try db.create(table: "companion_votes") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("poll_id", .integer).notNull()
                    .references("companion_polls", onDelete: .cascade)
                t.column("user_id", .integer).notNull()
                    .references("users", onDelete: .cascade)
                t.column("vote", .text).notNull()
                t.column("has_power", .integer).notNull().defaults(to: 0)
                t.column("voted_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["poll_id", "user_id"])
            }

            // companion_poll_results — finalized results for closed polls
            try db.create(table: "companion_poll_results") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("poll_id", .integer).notNull().unique()
                    .references("companion_polls", onDelete: .cascade)
                t.column("passed", .integer).notNull()
                t.column("total_votes", .integer).notNull().defaults(to: 0)
                t.column("powered_accept", .integer).notNull().defaults(to: 0)
                t.column("powered_reject", .integer).notNull().defaults(to: 0)
                t.column("all_accept", .integer).notNull().defaults(to: 0)
                t.column("all_reject", .integer).notNull().defaults(to: 0)
                t.column("was_admin_locked", .integer).notNull().defaults(to: 0)
                t.column("finalized_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            // companion_auto_discovery_log — tracks analysis runs
            try db.create(table: "companion_auto_discovery_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("analysis_date", .text).notNull()
                t.column("match_level", .text).notNull()
                t.column("data_window_months", .integer).notNull()
                t.column("pairs_analyzed", .integer).notNull().defaults(to: 0)
                t.column("new_pairs_found", .integer).notNull().defaults(to: 0)
                t.column("poll_created_id", .integer).references("companion_polls")
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }

            // -- Indexes --

            try db.create(index: "idx_polls_status", on: "companion_polls", columns: ["status"])
            try db.create(index: "idx_polls_dates", on: "companion_polls", columns: ["start_date", "end_date"])
            try db.create(index: "idx_votes_poll", on: "companion_votes", columns: ["poll_id"])
            try db.create(index: "idx_votes_user", on: "companion_votes", columns: ["user_id"])
            try db.create(index: "idx_rules_parent", on: "companion_rules", columns: ["parent_rule_id"])

            // -- Seed new permissions --

            // companion_vote_power — votes that actually count toward poll results
            let voteHats = try Row.fetchAll(db, sql: "SELECT id FROM hats WHERE name IN ('Admin', 'Manager', 'Lead')")
            for hat in voteHats {
                let hatId: Int64 = hat["id"]
                try db.execute(sql: "INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key) VALUES (?, 'companion_vote_power')", arguments: [hatId])
            }

            // vote_veto — admin controls: lock result, skip poll, preview next week
            if let adminHat = try Row.fetchOne(db, sql: "SELECT id FROM hats WHERE name = 'Admin'") {
                let adminId: Int64 = adminHat["id"]
                try db.execute(sql: "INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key) VALUES (?, 'vote_veto')", arguments: [adminId])
            }
        }

    }
}

// MARK: - 028: Supplier Communication Bridge

extension AppDatabase {
    private static func registerMigration028SupplierBridge(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("028_supplier_bridge") { db in
            try db.create(table: "supplier_channel_bridges") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("channel_id", .integer).notNull()
                    .references("chat_channels", onDelete: .cascade)
                t.column("supplier_id", .integer).notNull()
                    .references("suppliers", onDelete: .cascade)
                t.column("contact_id", .integer)
                    .references("entity_contacts", onDelete: .setNull)
                t.column("display_name", .text).notNull()
                t.column("role", .text)
                t.column("invite_token", .text).notNull()
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("last_seen_at", .text)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)

                t.uniqueKey(["channel_id", "supplier_id"])
            }
            try db.create(index: "idx_supplier_channel_bridges_supplier",
                          on: "supplier_channel_bridges", columns: ["supplier_id"])
            try db.create(index: "idx_supplier_channel_bridges_token",
                          on: "supplier_channel_bridges", columns: ["invite_token"],
                          unique: true)

            try db.create(table: "supplier_messages") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("message_id", .integer).notNull()
                    .references("chat_messages", onDelete: .cascade)
                t.column("bridge_id", .integer).notNull()
                    .references("supplier_channel_bridges", onDelete: .cascade)
                t.column("direction", .text).notNull()
                t.column("attachment_type", .text)
                t.column("attachment_ref", .text)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }
            try db.create(index: "idx_supplier_messages_bridge",
                          on: "supplier_messages", columns: ["bridge_id"])
        }
    }
}

// MARK: - 029: Location Stock Targets

extension AppDatabase {
    private static func registerMigration029LocationStockTargets(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("029_location_stock_targets") { db in
            try db.create(table: "location_stock_targets") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("part_id", .integer).notNull()
                    .references("parts", onDelete: .cascade)
                t.column("location_type", .text).notNull()
                t.column("location_id", .integer).notNull()
                t.column("min_stock", .integer).notNull().defaults(to: 0)
                t.column("target_stock", .integer).notNull().defaults(to: 0)
                t.column("max_stock", .integer).notNull().defaults(to: 0)
                t.column("forecast_adu_30", .double).defaults(to: 0)
                t.column("forecast_adu_90", .double).defaults(to: 0)
                t.column("forecast_days_until_low", .integer).defaults(to: 999)
                t.column("forecast_suggested_order", .integer).defaults(to: 0)
                t.column("forecast_last_run", .text)
                t.column("certainty_rating", .double).defaults(to: 0)
                t.column("deleted_at", .text)
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_lst_part_location", on: "location_stock_targets",
                          columns: ["part_id", "location_type", "location_id"], unique: true)
            try db.create(index: "idx_lst_location", on: "location_stock_targets",
                          columns: ["location_type", "location_id"])
        }
    }
}

// MARK: - 030: Forecast Settings + Free Space

extension AppDatabase {
    private static func registerMigration030ForecastSettings(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("030_forecast_settings") { db in
            try db.create(table: "forecast_settings") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("location_type", .text).notNull()
                t.column("location_id", .integer)
                t.column("usage_unit", .text).notNull().defaults(to: "daily")
                t.column("adu_lookback_days", .integer).defaults(to: 365)
                t.column("window_weeks", .integer).defaults(to: 3)
                t.column("min_data_days", .integer).defaults(to: 90)
                t.column("common_min_multiplier", .double).defaults(to: 3.5)
                t.column("common_target_multiplier", .double).defaults(to: 14.0)
                t.column("common_max_multiplier", .double).defaults(to: 21.0)
                t.column("critical_min_multiplier", .double).defaults(to: 7.0)
                t.column("critical_target_multiplier", .double).defaults(to: 14.0)
                t.column("critical_max_multiplier", .double).defaults(to: 30.0)
                t.column("free_space_suppress_threshold", .integer).defaults(to: 3)
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_fs_location", on: "forecast_settings",
                          columns: ["location_type", "location_id"], unique: true)

            // Seed: Shop (ADU, parts/day, 365-day lookback)
            try db.execute(sql: """
                INSERT INTO forecast_settings (location_type, usage_unit, adu_lookback_days, min_data_days,
                    common_min_multiplier, common_target_multiplier, common_max_multiplier,
                    critical_min_multiplier, critical_target_multiplier, critical_max_multiplier)
                VALUES ('warehouse', 'daily', 365, 90, 3.5, 14.0, 21.0, 7.0, 21.0, 30.0)
                """)

            // Seed: Truck (APW, parts/X-weeks, 3-week window)
            try db.execute(sql: """
                INSERT INTO forecast_settings (location_type, usage_unit, window_weeks, min_data_days,
                    common_min_multiplier, common_target_multiplier, common_max_multiplier,
                    critical_min_multiplier, critical_target_multiplier, critical_max_multiplier)
                VALUES ('truck', 'weekly', 3, 60, 1.0, 2.0, 3.0, 7.0, 14.0, 21.0)
                """)

            // Seed: Trailer (same as truck defaults)
            try db.execute(sql: """
                INSERT INTO forecast_settings (location_type, usage_unit, window_weeks, min_data_days,
                    common_min_multiplier, common_target_multiplier, common_max_multiplier,
                    critical_min_multiplier, critical_target_multiplier, critical_max_multiplier)
                VALUES ('trailer', 'weekly', 3, 60, 1.0, 2.0, 3.0, 7.0, 14.0, 21.0)
                """)

            // Free space ratings per location (1-10 scale)
            try db.create(table: "location_free_space") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("location_type", .text).notNull()
                t.column("location_id", .integer).notNull()
                t.column("free_space_rating", .integer).notNull().defaults(to: 5)
                t.column("updated_by", .integer).references("users")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_lfs_location", on: "location_free_space",
                          columns: ["location_type", "location_id"], unique: true)

            // Add part_category and do_not_restock to location_stock_targets
            try addColumnIfMissing(db, table: "location_stock_targets", column: "part_category", type: .text, defaultValue: "common")
            try addColumnIfMissing(db, table: "location_stock_targets", column: "do_not_restock", type: .integer, defaultValue: 0)
        }
    }
}

// MARK: - 031: Target Recommendations

extension AppDatabase {
    private static func registerMigration031TargetRecommendations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("031_target_recommendations") { db in
            try db.create(table: "target_recommendations") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("part_id", .integer).notNull().references("parts", onDelete: .cascade)
                t.column("location_type", .text).notNull()
                t.column("location_id", .integer).notNull()
                t.column("recommendation_type", .text).notNull().defaults(to: "adjust")
                t.column("current_min", .integer)
                t.column("current_target", .integer)
                t.column("current_max", .integer)
                t.column("recommended_min", .integer)
                t.column("recommended_target", .integer)
                t.column("recommended_max", .integer)
                t.column("current_category", .text)
                t.column("recommended_category", .text)
                t.column("usage_value", .double).notNull()
                t.column("usage_unit", .text).notNull()
                t.column("data_days", .integer).notNull()
                t.column("impact_score", .double).notNull()
                t.column("reason", .text)
                t.column("status", .text).defaults(to: "pending")
                t.column("approved_by", .integer).references("users")
                t.column("approved_at", .text)
                t.column("dismissed_by", .integer).references("users")
                t.column("dismissed_reason", .text)
                t.column("cooldown_until", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }
            try db.create(index: "idx_tr_part_loc", on: "target_recommendations",
                          columns: ["part_id", "location_type", "location_id"])
            try db.create(index: "idx_tr_status", on: "target_recommendations", columns: ["status"])
        }
    }
}

// MARK: - 032: JPO Per-Part Status

extension AppDatabase {
    private static func registerMigration032JPOPerPartStatus(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("032_jpo_per_part_status") { db in
            // Add per-line status fields to jpo_line_items
            try addColumnIfMissing(db, table: "jpo_line_items", column: "line_status", type: .text, defaultValue: "pending")
            try addColumnIfMissing(db, table: "jpo_line_items", column: "hold_reason", type: .text)
            try addColumnIfMissing(db, table: "jpo_line_items", column: "reject_reason", type: .text)
            try addColumnIfMissing(db, table: "jpo_line_items", column: "chat_thread_id", type: .integer)
            try addColumnIfMissing(db, table: "jpo_line_items", column: "po_line_id", type: .integer)
            try addColumnIfMissing(db, table: "jpo_line_items", column: "transfer_id", type: .integer)
            try addColumnIfMissing(db, table: "jpo_line_items", column: "status_updated_at", type: .text)
            try addColumnIfMissing(db, table: "jpo_line_items", column: "status_updated_by", type: .integer)

            // Add delivery option to job_purchase_orders
            try addColumnIfMissing(db, table: "job_parts_orders", column: "delivery_option", type: .text, defaultValue: "partial")
            try addColumnIfMissing(db, table: "job_parts_orders", column: "delivery_locked", type: .integer, defaultValue: 0)

            // Backfill existing lines to "pending"
            try db.execute(sql: """
                UPDATE jpo_line_items SET line_status = 'pending'
                WHERE line_status IS NULL
                """)
        }
    }

    private static func registerMigration033PartChangeLog(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("033_part_change_log") { db in
            try db.create(table: "part_change_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("part_id", .integer).notNull()
                    .references("parts", onDelete: .cascade)
                t.column("user_id", .integer)
                    .references("users", onDelete: .setNull)
                t.column("user_name", .text)
                t.column("action", .text).notNull()
                t.column("field_name", .text)
                t.column("old_value", .text)
                t.column("new_value", .text)
                t.column("context", .text)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_pcl_part", on: "part_change_log", columns: ["part_id"])
            try db.create(index: "idx_pcl_user", on: "part_change_log", columns: ["user_id"])
            try db.create(index: "idx_pcl_date", on: "part_change_log", columns: ["created_at"])
            try db.create(index: "idx_pcl_action", on: "part_change_log", columns: ["part_id", "action"])
        }
    }

    // MARK: - 034: Job Stages

    private static func registerMigration034JobStages(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("034_job_stages") { db in
            // Job stages table
            try db.create(table: "job_stages") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
            }

            // Category → Stage mapping
            try db.create(table: "job_stage_category_map") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("stage_id", .integer).notNull()
                    .references("job_stages", onDelete: .cascade)
                t.column("category_id", .integer).notNull()
                    .references("part_categories", onDelete: .cascade)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
                t.uniqueKey(["stage_id", "category_id"])
            }

            // Add stage_id to jpo_line_items (auto-assigned from category mapping)
            if !(try db.columns(in: "jpo_line_items").map(\.name)).contains("stage_id") {
                try db.alter(table: "jpo_line_items") { t in
                    t.add(column: "stage_id", .integer).references("job_stages")
                }
            }

            // Add current_stage_id to jobs
            if !(try db.columns(in: "jobs").map(\.name)).contains("current_stage_id") {
                try db.alter(table: "jobs") { t in
                    t.add(column: "current_stage_id", .integer).references("job_stages")
                }
            }

            // Indexes
            try db.create(index: "idx_jscm_stage", on: "job_stage_category_map", columns: ["stage_id"])
            try db.create(index: "idx_jscm_category", on: "job_stage_category_map", columns: ["category_id"])
            try db.create(index: "idx_jpo_lines_stage", on: "jpo_line_items", columns: ["stage_id"])

            // Seed 3 default stages
            try db.execute(sql: """
                INSERT INTO job_stages (name, sort_order) VALUES
                ('Rough-in', 1),
                ('Prep/Makeup', 2),
                ('Trim-out', 3)
                """)
        }
    }
}

// MARK: - 035: Staging Boxes

extension AppDatabase {
    private static func registerMigration035StagingBoxes(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("035_staging_boxes") { db in
            // Physical staging boxes for organizing pulled parts by job
            try db.create(table: "staging_boxes") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("job_id", .integer).notNull()
                    .references("jobs", onDelete: .cascade)
                t.column("box_number", .text).notNull()       // e.g. "0412-01"
                t.column("box_size", .text).notNull()
                    .defaults(to: "normal")                    // small / normal / large
                t.column("label_text", .text).notNull()        // e.g. "SMITH RES 0412-01"
                t.column("is_full", .integer).notNull()
                    .defaults(to: 0)
                t.column("area_id", .integer)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
            }

            try db.create(index: "idx_staging_boxes_job", on: "staging_boxes", columns: ["job_id"])
            try db.create(index: "idx_staging_boxes_full", on: "staging_boxes", columns: ["is_full"])
        }
    }

    // MARK: - 036: Clock + To-Do Integration

    private static func registerMigration036ClockTodoIntegration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("036_clock_todo_integration") { db in
            // Add linked_todo_id and work_type to labor_entries
            // so workers can track what they're doing + classify work type
            let leCols = try db.columns(in: "labor_entries").map(\.name)
            if !leCols.contains("linked_todo_id") {
                try db.alter(table: "labor_entries") { t in
                    t.add(column: "linked_todo_id", .integer)
                        .references("notebook_entries", onDelete: .setNull)
                    t.add(column: "work_type", .text)
                        .defaults(to: "new_work")
                }
            }
        }
    }
}

// MARK: - 037: Chat Message Attachments

extension AppDatabase {
    private static func registerMigration037ChatAttachments(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("037_chat_attachments") { db in
            try db.create(table: "message_attachments") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("message_id", .integer).notNull()
                    .references("chat_messages", onDelete: .cascade)
                t.column("attachment_type", .text).notNull()  // "photo", "file", "part_ref", "po_ref", "job_ref", "jpo_ref"
                t.column("file_path", .text)       // local file path for photos/files
                t.column("file_name", .text)       // display name
                t.column("file_size", .integer)    // bytes
                t.column("mime_type", .text)       // "image/jpeg", "application/pdf", etc.
                t.column("reference_id", .integer) // ID of the referenced entity (part, PO, job, JPO)
                t.column("reference_label", .text) // Display label for the reference
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_msg_attach_message", on: "message_attachments", columns: ["message_id"])
        }
    }
}

// MARK: - 038: Notebook Hierarchy (Section Groups + Block Content)

extension AppDatabase {
    private static func registerMigration038NotebookHierarchy(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("038_notebook_hierarchy") { db in
            // Section groups — optional grouping above sections
            try db.create(table: "notebook_section_groups") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("notebook_id", .integer).notNull()
                    .references("notebooks", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("is_collapsed", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }
            try db.create(index: "idx_nsg_notebook", on: "notebook_section_groups", columns: ["notebook_id"])

            // Add group_id and additional columns to notebook_sections
            let nsCols = try db.columns(in: "notebook_sections").map(\.name)
            if !nsCols.contains("group_id") {
                try db.alter(table: "notebook_sections") { t in
                    t.add(column: "group_id", .integer)
                        .references("notebook_section_groups", onDelete: .setNull)
                    t.add(column: "is_collapsed", .integer).notNull().defaults(to: 0)
                    t.add(column: "updated_at", .text).defaults(sql: "(datetime('now'))")
                }
            }

            // Add block content columns to notebook_entries
            let neCols = try db.columns(in: "notebook_entries").map(\.name)
            if !neCols.contains("block_type") {
                try db.alter(table: "notebook_entries") { t in
                    t.add(column: "block_type", .text).notNull().defaults(to: "text")
                    t.add(column: "block_data", .text)
                    t.add(column: "heading_level", .integer)
                    t.add(column: "checklist_items", .text)
                    t.add(column: "photo_path", .text)
                    t.add(column: "reference_type", .text)
                    t.add(column: "reference_id", .integer)
                    t.add(column: "is_completed", .integer).notNull().defaults(to: 0)
                    t.add(column: "notebook_id", .integer)
                }
            }
        }
    }
}

// MARK: - Migration 043: Payment Tracking

extension AppDatabase {
    private static func registerMigration043PaymentTracking(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("043_payment_tracking") { db in
            // Payment records for customer invoicing / AR tracking
            try db.create(table: "payment_records") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("customer_id", .integer).notNull()
                    .references("customers", onDelete: .cascade)
                t.column("job_id", .integer)
                    .references("jobs")
                t.column("invoice_number", .text)
                t.column("amount", .double).notNull()
                t.column("due_date", .text).notNull()
                t.column("paid_date", .text)
                t.column("paid_amount", .double)
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("notes", .text)
                t.column("created_by", .integer).references("users")
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }

            // Communication log for customers (notes, calls, emails, meetings)
            try db.create(table: "customer_communications") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("customer_id", .integer).notNull()
                    .references("customers", onDelete: .cascade)
                t.column("comm_type", .text).notNull().defaults(to: "note")
                t.column("content", .text).notNull()
                t.column("created_by", .integer).references("users")
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }

            // Contractor notes
            try db.create(table: "contractor_notes") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("contractor_id", .integer).notNull()
                    .references("entity_contacts", onDelete: .cascade)
                t.column("content", .text).notNull()
                t.column("created_by", .integer).references("users")
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }

            // Contractor ratings (subcontractors only)
            try db.create(table: "contractor_ratings") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("contractor_id", .integer).notNull()
                    .references("entity_contacts", onDelete: .cascade)
                t.column("quality_score", .double).notNull().defaults(to: 0)
                t.column("on_time_score", .double).notNull().defaults(to: 0)
                t.column("reliability_score", .double).notNull().defaults(to: 0)
                t.column("rated_by", .integer).references("users")
                t.column("job_id", .integer).references("jobs")
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }

            // Payment tracking settings in settings table
            try db.execute(sql: """
                INSERT OR IGNORE INTO settings (key, value) VALUES
                ('payment_tracking_enabled', '0'),
                ('default_payment_terms_days', '30'),
                ('overdue_warning_days', '7'),
                ('auto_payment_hold', '0')
            """)
        }
    }

    // MARK: - Migration 044: Job Classifications

    private static func registerMigration044JobClassifications(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("044_job_classifications") { db in
            // Warranty, classification, payment hold, and continuous columns on jobs
            let jobCols044 = try db.columns(in: "jobs").map(\.name)
            if !jobCols044.contains("warranty_start") {
                try db.alter(table: "jobs") { t in
                    t.add(column: "warranty_start", .text)
                    t.add(column: "warranty_end", .text)
                    t.add(column: "warranty_duration_days", .integer)
                    t.add(column: "job_classification", .text).defaults(to: "standard")
                    t.add(column: "payment_hold_amount", .double)
                    t.add(column: "payment_hold_date", .text)
                    t.add(column: "payment_hold_reason", .text)
                    t.add(column: "is_continuous", .integer).notNull().defaults(to: 0)
                    t.add(column: "continuous_schedule", .text)
                }
            }
        }
    }

    // MARK: - Migration 045: Todo Work Classification

    private static func registerMigration045TodoClassification(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("045_todo_classification") { db in
            // Work classification columns on notebook_entries
            let neCols045 = try db.columns(in: "notebook_entries").map(\.name)
            if !neCols045.contains("work_classification") {
                try db.alter(table: "notebook_entries") { t in
                    t.add(column: "work_classification", .text)
                    t.add(column: "classification_reviewed", .integer).notNull().defaults(to: 0)
                t.add(column: "classification_reviewed_by", .integer)
                t.add(column: "classification_reviewed_at", .text)
                t.add(column: "warranty_timer_start", .text)
                t.add(column: "warranty_timer_end", .text)
                t.add(column: "is_question", .integer).notNull().defaults(to: 0)
                }
            }

            // Classification audit history
            try db.create(table: "classification_history") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("entry_id", .integer).notNull()
                    .references("notebook_entries", onDelete: .cascade)
                t.column("old_classification", .text)
                t.column("new_classification", .text).notNull()
                t.column("changed_by", .integer).notNull()
                    .references("users")
                t.column("reason", .text)
                t.column("changed_at", .text).defaults(sql: "(datetime('now'))")
            }
        }
    }

    // MARK: - Migration 046: Half-Day Scheduling

    private static func registerMigration046HalfDayScheduling(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("046_half_day_scheduling") { db in
            // Add time_slot column to job_dispatch for AM/PM/Full day scheduling
            try addColumnIfMissing(db, table: "job_dispatch", column: "time_slot", type: .text, defaultValue: "full")
        }
    }

    // MARK: - Migration 047: Job Estimation

    private static func registerMigration047JobEstimation(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("047_job_estimation") { db in
            // Configurable questions asked at each stage of a job
            try db.create(table: "estimation_questions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("question_text", .text).notNull()
                t.column("question_group", .text).notNull()      // scope, complexity, access, materials, labor
                t.column("stage", .text).notNull()                // bid, pre_start, during, before_trim, punch_list
                t.column("answer_type", .text).notNull().defaults(to: "number") // number, choice, boolean, text
                t.column("choices", .text)                        // JSON array for choice type
                t.column("weight", .double).notNull().defaults(to: 1.0)
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }

            // Responses to estimation questions for a specific job+stage
            try db.create(table: "estimation_responses") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("job_id", .integer).notNull()
                    .references("jobs", onDelete: .cascade)
                t.column("question_id", .integer).notNull()
                    .references("estimation_questions")
                t.column("stage", .text).notNull()
                t.column("response_value", .text)                 // the answer
                t.column("is_unknown", .integer).notNull().defaults(to: 0) // "?" response
                t.column("answered_by", .integer).references("users")
                t.column("answered_at", .text).defaults(sql: "(datetime('now'))")
            }

            // Calculated estimation results per job+stage
            try db.create(table: "estimation_results") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("job_id", .integer).notNull()
                    .references("jobs", onDelete: .cascade)
                t.column("stage", .text).notNull()
                t.column("estimated_days", .double)
                t.column("estimated_hours", .double)
                t.column("confidence_percent", .double)           // 0-100
                t.column("ai_suggested", .integer).notNull().defaults(to: 0)
                t.column("notes", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }

            // Weekly and end-of-job reviews to improve future estimates
            try db.create(table: "estimation_reviews") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("job_id", .integer).notNull()
                    .references("jobs", onDelete: .cascade)
                t.column("review_type", .text).notNull()          // weekly, end_of_job
                t.column("actual_days", .double)
                t.column("actual_hours", .double)
                t.column("estimate_at_start", .double)
                t.column("variance_percent", .double)
                t.column("lessons_learned", .text)
                t.column("reviewed_by", .integer).references("users")
                t.column("reviewed_at", .text).defaults(sql: "(datetime('now'))")
            }

            // Log of rejected questions for AI reconsideration
            try db.create(table: "estimation_question_rejections") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("question_id", .integer).notNull()
                    .references("estimation_questions")
                t.column("rejected_by", .integer).references("users")
                t.column("reason", .text)
                t.column("rejected_at", .text).defaults(sql: "(datetime('now'))")
            }

            // Seed default estimation questions
            let seedQuestions: [(String, String, String, String, String?, Double, Int)] = [
                // Scope questions — bid stage
                ("Total square footage", "scope", "bid", "number", nil, 2.0, 1),
                ("Number of rooms/areas", "scope", "bid", "number", nil, 1.5, 2),
                ("Number of floors", "scope", "bid", "number", nil, 1.0, 3),
                ("New construction or remodel?", "scope", "bid", "choice", "[\"New Construction\",\"Remodel\",\"Addition\"]", 1.5, 4),

                // Complexity questions — bid stage
                ("Custom trim or millwork?", "complexity", "bid", "boolean", nil, 2.0, 1),
                ("High ceilings (over 10ft)?", "complexity", "bid", "boolean", nil, 1.5, 2),
                ("Difficulty level", "complexity", "bid", "choice", "[\"Standard\",\"Moderate\",\"Complex\",\"Very Complex\"]", 2.5, 3),

                // Access questions — pre_start stage
                ("Clear site access for deliveries?", "access", "pre_start", "boolean", nil, 1.0, 1),
                ("Elevator or stair access only?", "access", "pre_start", "choice", "[\"Ground Level\",\"Elevator\",\"Stairs Only\"]", 1.5, 2),
                ("Parking available for crew?", "access", "pre_start", "boolean", nil, 0.5, 3),

                // Materials questions — pre_start stage
                ("Materials on-site?", "materials", "pre_start", "boolean", nil, 1.5, 1),
                ("Special order items pending?", "materials", "pre_start", "boolean", nil, 2.0, 2),
                ("Material complexity", "materials", "pre_start", "choice", "[\"Standard\",\"Mixed\",\"All Custom\"]", 1.5, 3),

                // Labor questions — during stage
                ("Crew size needed", "labor", "during", "number", nil, 2.0, 1),
                ("Subcontractor coordination needed?", "labor", "during", "boolean", nil, 1.5, 2),
                ("Overtime likely?", "labor", "during", "boolean", nil, 1.0, 3),

                // Punch list questions
                ("Estimated punch list items", "scope", "punch_list", "number", nil, 1.0, 1),
                ("Touch-up paint needed?", "materials", "punch_list", "boolean", nil, 0.5, 2),
            ]

            for (text, group, stage, answerType, choices, weight, sortOrder) in seedQuestions {
                try db.execute(sql: """
                    INSERT INTO estimation_questions (question_text, question_group, stage, answer_type, choices, weight, sort_order)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [text, group, stage, answerType, choices, weight, sortOrder])
            }
        }
    }

    // MARK: - Migration 048: Tool Detail Tables (checkouts, change log)

    private static func registerMigration048ToolDetailTables(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("048_tool_detail_tables") { db in

            // Tool checkouts — dedicated checkout/return tracking with condition
            try db.create(table: "tool_checkouts") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("tool_id", .integer).notNull()
                    .references("tools", onDelete: .cascade)
                t.column("checked_out_by", .integer).notNull()
                    .references("users")
                t.column("checked_out_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
                t.column("checkout_condition", .text).notNull()
                    .defaults(to: "Good")
                t.column("checkout_notes", .text)
                t.column("checked_in_at", .text)
                t.column("checked_in_by", .integer)
                    .references("users")
                t.column("return_condition", .text)
                t.column("return_notes", .text)
                t.column("expected_return", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_tool_checkouts_tool", on: "tool_checkouts", columns: ["tool_id"])
            try db.create(index: "idx_tool_checkouts_active", on: "tool_checkouts",
                          columns: ["tool_id", "checked_in_at"])

            // Tool change log — version history for edits, with verification
            try db.create(table: "tool_change_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("tool_id", .integer).notNull()
                    .references("tools", onDelete: .cascade)
                t.column("changed_by", .integer).notNull()
                    .references("users")
                t.column("change_type", .text).notNull()
                    .defaults(to: "edit")
                t.column("field_name", .text)
                t.column("old_value", .text)
                t.column("new_value", .text)
                t.column("verification_status", .text).notNull()
                    .defaults(to: "approved")
                t.column("verified_by", .integer)
                    .references("users")
                t.column("verified_at", .text)
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("changed_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_tcl_tool", on: "tool_change_log", columns: ["tool_id"])
            try db.create(index: "idx_tcl_status", on: "tool_change_log",
                          columns: ["tool_id", "verification_status"])
            try db.create(index: "idx_tcl_date", on: "tool_change_log", columns: ["changed_at"])
        }
    }

    // MARK: - Migration 049: Tool Trades

    private static func registerMigration049ToolTrades(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("049_tool_trades") { db in
            try db.create(table: "tool_trades") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("tool_id", .integer).notNull()
                    .references("tools", onDelete: .cascade)
                t.column("from_user_id", .integer).notNull()
                    .references("users")
                t.column("to_user_id", .integer).notNull()
                    .references("users")
                t.column("condition_at_send", .text).notNull()
                t.column("condition_at_receive", .text)
                t.column("send_notes", .text)
                t.column("receive_notes", .text)
                t.column("status", .text).notNull()
                    .defaults(to: "pending")
                t.column("expires_at", .text).notNull()
                t.column("responded_at", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_tool_trades_tool", on: "tool_trades", columns: ["tool_id"])
            try db.create(index: "idx_tool_trades_status", on: "tool_trades", columns: ["status"])
            try db.create(index: "idx_tool_trades_to_user", on: "tool_trades",
                          columns: ["to_user_id", "status"])
        }
    }

    // MARK: - Migration 050: Tool Maintenance Configs

    private static func registerMigration050ToolMaintenanceConfigs(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("050_tool_maintenance_configs") { db in

            // Maintenance configs — 5 maintenance strategy types per tool
            try db.create(table: "tool_maintenance_configs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("tool_id", .integer).notNull()
                    .references("tools", onDelete: .cascade)
                t.column("maintenance_type", .text).notNull()
                t.column("interval_days", .integer)
                t.column("usage_threshold", .double)
                t.column("schedule_cron", .text)
                t.column("decay_rate", .double)
                t.column("decay_floor", .double)
                t.column("condition_triggers", .text)
                t.column("description", .text)
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_tmc_tool", on: "tool_maintenance_configs", columns: ["tool_id"])

            // Add usage tracking and confidence columns to tools
            try addColumnIfMissing(db, table: "tools", column: "total_usage_hours", type: .double, defaultValue: 0)
            try addColumnIfMissing(db, table: "tools", column: "confidence_score", type: .double, defaultValue: 1.0)
            try addColumnIfMissing(db, table: "tools", column: "last_maintenance_date", type: .text)
        }
    }
}

// MARK: - 051: Vehicle Stock & Trailer Attachments

extension AppDatabase {
    private static func registerMigration051VehicleStockAndTrailers(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("051_vehicle_stock_and_trailers") { db in

            // Vehicle stock — permanent truck inventory + in-transit transfer items
            try db.create(table: "vehicle_stock") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("vehicle_id", .integer).notNull()
                    .references("vehicles", onDelete: .cascade)
                t.column("part_id", .integer).references("parts")
                t.column("part_name", .text).notNull()
                t.column("quantity", .integer).notNull().defaults(to: 0)
                t.column("stock_type", .text).notNull().defaults(to: "truck_stock")
                    // "truck_stock" = permanent (MIN/TARGET/MAX)
                    // "transfer" = in-transit (source/destination)
                t.column("min_qty", .integer)
                t.column("target_qty", .integer)
                t.column("max_qty", .integer)
                t.column("source_location", .text)       // transfer: where it came from
                t.column("destination_location", .text)   // transfer: where it's going
                t.column("transfer_reason", .text)        // "job_delivery", "return", "restock"
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_vs_vehicle", on: "vehicle_stock", columns: ["vehicle_id"])
            try db.create(index: "idx_vs_type", on: "vehicle_stock", columns: ["stock_type"])

            // Add fuel_level column to vehicles (0.0–1.0, nullable)
            try addColumnIfMissing(db, table: "vehicles", column: "fuel_level", type: .double)
            try addColumnIfMissing(db, table: "vehicles", column: "next_maintenance_date", type: .text)

            // Trailer attachments — which trailer is attached to which vehicle
            try db.create(table: "trailer_attachments") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("vehicle_id", .integer).notNull()
                    .references("vehicles", onDelete: .cascade)
                t.column("trailer_id", .integer).notNull()
                    .references("job_trailers", onDelete: .cascade)
                t.column("attached_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
                t.column("detached_at", .text)
                t.column("attached_by", .integer).references("users")
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_ta_vehicle", on: "trailer_attachments", columns: ["vehicle_id"])
            try db.create(index: "idx_ta_trailer", on: "trailer_attachments", columns: ["trailer_id"])
        }
    }
}

// MARK: - 052: Trailer Mini-Warehouse

extension AppDatabase {
    private static func registerMigration052TrailerMiniWarehouse(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("052_trailer_mini_warehouse") { db in

            // Trailer storage units — physical containers (shelves, drawers, bins)
            try db.create(table: "trailer_storage_units") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("trailer_id", .integer).notNull()
                    .references("job_trailers", onDelete: .cascade)
                t.column("name", .text).notNull()         // "Shelf A", "Drawer 1"
                t.column("unit_type", .text).notNull()     // "shelf", "drawer", "compartment", "bin"
                t.column("capacity_slots", .integer)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_tsu_trailer", on: "trailer_storage_units", columns: ["trailer_id"])

            // Trailer stock — per-part inventory with MIN/TARGET/MAX and optional storage location
            try db.create(table: "trailer_stock") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("trailer_id", .integer).notNull()
                    .references("job_trailers", onDelete: .cascade)
                t.column("storage_unit_id", .integer)
                    .references("trailer_storage_units")
                t.column("part_id", .integer).references("parts")
                t.column("part_name", .text).notNull()
                t.column("quantity", .integer).notNull().defaults(to: 0)
                t.column("min_qty", .integer)
                t.column("target_qty", .integer)
                t.column("max_qty", .integer)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_ts_trailer", on: "trailer_stock", columns: ["trailer_id"])

            // Location tracking columns on job_trailers
            try addColumnIfMissing(db, table: "job_trailers", column: "is_at_shop", type: .integer, defaultValue: 1)
            try addColumnIfMissing(db, table: "job_trailers", column: "linked_warehouse_id", type: .integer)

            // Trailer location history — tracks shop/job_site/in_transit transitions
            try db.create(table: "trailer_location_history") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("trailer_id", .integer).notNull()
                    .references("job_trailers", onDelete: .cascade)
                t.column("location_type", .text).notNull()  // "shop", "job_site", "in_transit"
                t.column("location_label", .text)
                t.column("job_id", .integer).references("jobs")
                t.column("latitude", .double)
                t.column("longitude", .double)
                t.column("arrived_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
                t.column("departed_at", .text)
                t.column("recorded_by", .integer).references("users")
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_tlh_trailer", on: "trailer_location_history", columns: ["trailer_id"])
        }
    }

    // MARK: - Migration 053: Pre-Trip Inspection

    private static func registerMigration053PreTripInspection(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("053_pre_trip_inspection") { db in
            // Checklist templates — one row per checklist item per vehicle type
            try db.create(table: "inspection_templates") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("vehicle_type", .text).notNull()  // "van", "truck", "trailer"
                t.column("section", .text).notNull()        // "exterior", "interior", "equipment"
                t.column("item_name", .text).notNull()
                t.column("item_description", .text)
                t.column("is_critical", .boolean).notNull().defaults(to: false)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("is_active", .boolean).notNull().defaults(to: true)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
            }

            // Inspection records — one per inspection session
            try db.create(table: "inspection_records") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("vehicle_id", .integer).notNull()
                    .references("vehicles", onDelete: .cascade)
                t.column("trailer_id", .integer)
                    .references("job_trailers", onDelete: .setNull)
                t.column("inspector_id", .integer).notNull()
                    .references("users", onDelete: .cascade)
                t.column("result", .text).notNull()  // "pass", "fail", "conditional"
                t.column("notes", .text)
                t.column("performed_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
                t.column("odometer_reading", .integer)
                t.column("fuel_level", .double)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_ir_vehicle", on: "inspection_records", columns: ["vehicle_id"])
            try db.create(index: "idx_ir_inspector", on: "inspection_records", columns: ["inspector_id"])

            // Inspection results — one per checklist item per inspection
            try db.create(table: "inspection_results") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("inspection_id", .integer).notNull()
                    .references("inspection_records", onDelete: .cascade)
                t.column("template_item_id", .integer).notNull()
                    .references("inspection_templates", onDelete: .cascade)
                t.column("status", .text).notNull()  // "ok", "issue", "na"
                t.column("notes", .text)
                t.column("photo_path", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_ires_inspection", on: "inspection_results", columns: ["inspection_id"])

            // ── Seed default inspection items ──────────────────────────────

            // Helper to insert a template row
            func seed(_ vehicleType: String, _ section: String, _ name: String,
                      _ isCritical: Bool, _ order: Int, _ desc: String? = nil) throws {
                try db.execute(sql: """
                    INSERT INTO inspection_templates
                    (vehicle_type, section, item_name, item_description, is_critical, sort_order)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [vehicleType, section, name, desc, isCritical, order])
            }

            // Vehicle exterior items (apply to both "van" and "truck")
            let exteriorItems: [(String, Bool, String?)] = [
                ("Tires — Tread Depth", true, "Check all tires for adequate tread"),
                ("Tires — Pressure", true, "Check all tires for proper inflation"),
                ("Headlights", true, nil),
                ("Taillights", true, nil),
                ("Turn Signals", true, nil),
                ("Brake Lights", true, nil),
                ("Mirrors", false, "Side and rearview mirrors intact"),
                ("Windshield", false, "No cracks or chips that obstruct view"),
                ("Body Damage", false, "Note any new dents, scratches, or damage"),
                ("Fluid Leaks", true, "Check under vehicle for oil/coolant leaks"),
            ]

            // Vehicle interior items
            let interiorItems: [(String, Bool, String?)] = [
                ("Seatbelt", true, "Seatbelt latches and retracts properly"),
                ("Horn", true, nil),
                ("Gauges Working", false, "All dashboard gauges operational"),
                ("Wipers", false, "Blades in good condition"),
                ("Heater/AC", false, nil),
                ("Dashboard Lights", false, "No unexpected warning lights"),
            ]

            // Vehicle equipment items
            let equipmentItems: [(String, Bool, String?)] = [
                ("Fire Extinguisher", true, "Present and charged"),
                ("First Aid Kit", false, nil),
                ("Safety Cones/Triangles", false, nil),
                ("Spare Tire", false, "Present and inflated"),
            ]

            // Seed for "van" and "truck"
            for vehicleType in ["van", "truck"] {
                for (i, item) in exteriorItems.enumerated() {
                    try seed(vehicleType, "exterior", item.0, item.1, i, item.2)
                }
                for (i, item) in interiorItems.enumerated() {
                    try seed(vehicleType, "interior", item.0, item.1, i, item.2)
                }
                for (i, item) in equipmentItems.enumerated() {
                    try seed(vehicleType, "equipment", item.0, item.1, i, item.2)
                }
            }

            // Trailer-specific exterior items
            let trailerExteriorItems: [(String, Bool, String?)] = [
                ("Hitch Connection", true, "Properly secured and locked"),
                ("Safety Chains", true, "Connected and not dragging"),
                ("Trailer Lights", true, "All trailer lights functional"),
                ("Tires — Tread Depth", true, nil),
                ("Tires — Pressure", true, nil),
                ("Trailer Body", false, "No damage or loose panels"),
                ("Doors/Latches", false, "All doors secure and operational"),
                ("Load Secured", true, "All cargo properly secured"),
            ]

            // Trailer equipment
            let trailerEquipmentItems: [(String, Bool, String?)] = [
                ("Wheel Chocks", false, nil),
                ("Tie-Down Straps", false, "Present and in good condition"),
                ("Reflectors/Markings", false, "Visible and clean"),
            ]

            for (i, item) in trailerExteriorItems.enumerated() {
                try seed("trailer", "exterior", item.0, item.1, i, item.2)
            }
            for (i, item) in trailerEquipmentItems.enumerated() {
                try seed("trailer", "equipment", item.0, item.1, i, item.2)
            }
        }
    }

    // MARK: - Migration 054: Saved Reports

    private static func registerMigration054SavedReports(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("054_saved_reports") { db in
            try db.create(table: "saved_reports") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("report_type", .text).notNull()
                t.column("columns_json", .text).notNull()
                t.column("filters_json", .text).notNull()
                t.column("created_by", .integer).notNull().references("users")
                t.column("is_shared", .boolean).notNull().defaults(to: false)
                t.column("deleted_at", .datetime)
                t.column("created_at", .datetime).notNull().defaults(sql: "(datetime('now'))")
                t.column("last_run_at", .datetime)
            }

            try db.create(index: "idx_sr_created_by", on: "saved_reports", columns: ["created_by"])
        }
    }

    // MARK: - Migration 055: Office Channel (is_system)

    private static func registerMigration055OfficeChannel(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("055_office_channel") { db in
            // Add is_system column to chat_channels
            try addColumnIfMissing(db, table: "chat_channels", column: "is_system", type: .boolean, defaultValue: false)
        }
    }

    // MARK: - Migration 056: AI Conversation Messages

    private static func registerMigration056AIConversations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("056_ai_conversations") { db in
            // Stores individual chat messages so the AI assistant remembers past conversations.
            // Each row is a single user or assistant turn.
            try db.create(table: "ai_conversation_messages") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("conversation_id", .text).notNull()
                t.column("role", .text).notNull()            // "user" or "assistant"
                t.column("content", .text).notNull()
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            // Fast lookup by conversation
            try db.create(
                index: "idx_ai_conv_msgs_conv",
                on: "ai_conversation_messages",
                columns: ["conversation_id", "created_at"]
            )
        }
    }

    // MARK: - Migration 057: Wishlist Items

    private static func registerMigration057WishlistItems(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("057_wishlist_items") { db in
            try db.create(table: "wishlist_items", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("part_id", .integer).references("parts", onDelete: .cascade)
                t.column("part_name", .text).notNull()
                t.column("qty_suggested", .integer).notNull().defaults(to: 1)
                t.column("reason", .text)
                t.column("priority", .text).notNull().defaults(to: "normal")
                t.column("source_type", .text).notNull().defaults(to: "manual")
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("requested_by", .text)
                t.column("approved_by", .text)
                t.column("approved_at", .datetime)
                t.column("dismissed_by", .text)
                t.column("dismissed_at", .datetime)
                t.column("notes", .text)
                t.column("created_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.column("updated_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }

            // Fast lookup by status for filtered list views
            try db.create(
                index: "idx_wishlist_status",
                on: "wishlist_items",
                columns: ["status"]
            )

            // Fast lookup by part for dedup checks
            try db.create(
                index: "idx_wishlist_part",
                on: "wishlist_items",
                columns: ["part_id"]
            )
        }
    }

    // MARK: - Migration 058: Background Task Log

    private static func registerMigration058BackgroundTaskLog(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("058_background_task_log") { db in
            try db.create(table: "background_task_log", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("task_name", .text).notNull()
                t.column("task_type", .text).notNull()
                t.column("status", .text).notNull().defaults(to: "running")
                t.column("started_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.column("completed_at", .datetime)
                t.column("result_summary", .text)
                t.column("error_message", .text)
                t.column("items_processed", .integer).notNull().defaults(to: 0)
                t.column("device_id", .text)
            }

            // Fast lookup by status for "currently running" queries
            try db.create(
                index: "idx_bg_task_status",
                on: "background_task_log",
                columns: ["status"]
            )

            // Fast lookup by start time for "recent tasks" queries
            try db.create(
                index: "idx_bg_task_started",
                on: "background_task_log",
                columns: ["started_at"]
            )
        }
    }

    // MARK: - Migration 059: Multi-User Audit Assignments

    private static func registerMigration059MultiUserAuditAssignments(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("059_multi_user_audit_assignments") { db in
            // Multi-user audit verification assignments for low-confidence parts.
            // When a part's confidence is below threshold, 2-3 independent users
            // are assigned to count it. Their counts are compared for consensus.
            try db.create(table: "multi_user_audit_assignments") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("part_id", .integer).notNull()
                    .references("parts", onDelete: .cascade)
                t.column("part_name", .text).notNull()
                t.column("bin_location", .text)
                t.column("assigned_user_id", .integer).notNull()
                    .references("users", onDelete: .cascade)
                t.column("assigned_user_name", .text)
                t.column("counted_quantity", .integer)
                t.column("counted_at", .text)
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("audit_session_id", .integer)
                    .references("audit_sessions_v2", onDelete: .cascade)
                t.column("expected_quantity", .integer)
                t.column("notes", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
            }

            // Fast lookup by session for listing all assignments in a session
            try db.create(
                index: "idx_mua_session",
                on: "multi_user_audit_assignments",
                columns: ["audit_session_id"]
            )

            // Fast lookup by user for "my pending assignments" queries
            try db.create(
                index: "idx_mua_user_status",
                on: "multi_user_audit_assignments",
                columns: ["assigned_user_id", "status"]
            )

            // Fast lookup by part for resolving multi-user counts
            try db.create(
                index: "idx_mua_part_session",
                on: "multi_user_audit_assignments",
                columns: ["part_id", "audit_session_id"]
            )
        }
    }
}

// MARK: - Migration 060: Permission Keys Expansion (39A)

extension AppDatabase {
    private static func registerMigration061AuditSessionMetadata(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("061_audit_session_metadata") { db in
            // Add zone/scope metadata columns to audit_sessions_v2.
            // These were silently dropped when createAuditSession() migrated from
            // audit_sessions (v1) to audit_sessions_v2 — the v2 schema only had
            // session_type + started_by. IOSAuditSetupView collects zone, spot-check
            // count, include_zero_stock, and notes; this migration ensures they persist.
            try db.alter(table: "audit_sessions_v2") { t in
                t.add(column: "zone", .text)
                t.add(column: "sample_size", .integer)
                t.add(column: "include_zero_stock", .integer).notNull().defaults(to: 1)
                t.add(column: "notes", .text)
            }
        }
    }
}

extension AppDatabase {
    private static func registerMigration062AuditCountedQty(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("062_audit_counted_qty") { db in
            // Add counted_qty column to stock table so physical audit counts
            // can be persisted and compared against the system quantity (qty).
            try db.alter(table: "stock") { t in
                t.add(column: "counted_qty", .integer)
            }
        }
    }
}

extension AppDatabase {
    /// Migration 063: Fix FK references in contractor_notes and contractor_ratings.
    ///
    /// The original migration (part of a people-system refactor) created these tables
    /// with `contractor_id` referencing `entity_contacts`, but all service code
    /// passes `general_contractors.id` as the contractor identifier. Recreate
    /// both tables with the correct FK to `general_contractors`.
    private static func registerMigration063FixContractorNotesFKs(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("063_fix_contractor_notes_fks") { db in
            // Drop and recreate contractor_notes with correct FK
            try db.drop(table: "contractor_notes")
            try db.create(table: "contractor_notes") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("contractor_id", .integer).notNull()
                    .references("general_contractors", onDelete: .cascade)
                t.column("content", .text).notNull()
                t.column("created_by", .integer).references("users")
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }

            // Drop and recreate contractor_ratings with correct FK
            try db.drop(table: "contractor_ratings")
            try db.create(table: "contractor_ratings") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("contractor_id", .integer).notNull()
                    .references("general_contractors", onDelete: .cascade)
                t.column("quality_score", .double).notNull().defaults(to: 0)
                t.column("on_time_score", .double).notNull().defaults(to: 0)
                t.column("reliability_score", .double).notNull().defaults(to: 0)
                t.column("rated_by", .integer).references("users")
                t.column("job_id", .integer).references("jobs")
                t.column("notes", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }
        }
    }
}

extension AppDatabase {
    /// Migration 064: Add `request_group` to `schedule_exceptions`.
    ///
    /// Multi-day time-off requests are stored as one row per day (due to the
    /// `UNIQUE(user_id, exception_date)` constraint). Without a shared key,
    /// `listTimeOffRequests` returns one row per day, making a 3-day request
    /// appear as 3 separate requests in the UI.
    ///
    /// This migration adds a `request_group TEXT` column. `createTimeOffRequest`
    /// now assigns the same UUID to every day it inserts for a single request,
    /// and `listTimeOffRequests` groups by that UUID to surface one row per request.
    private static func registerMigration064TimeOffRequestGroups(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("064_time_off_request_groups") { db in
            try db.alter(table: "schedule_exceptions") { t in
                t.add(column: "request_group", .text)
            }
        }
    }

    // MARK: - Migration 065: Color-Level Part Numbers

    private static func registerMigration065ColorPartNumbers(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("065_color_part_numbers") { db in
            // Part numbers belong at the color level — each color variant has its own
            // manufacturer/internal part number (e.g., "Romex 12/2 White" ≠ "Romex 12/2 Gray")
            try db.alter(table: "part_colors") { t in
                t.add(column: "part_number", .text)
            }
            // part_supplier_links.supplier_part_number already exists from migration 002
        }
    }

    // MARK: - Migration 066: Brand-Supplier Carry Status

    private static func registerMigration066BrandSupplierCarryStatus(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("066_brand_supplier_carry_status") { db in
            // Each brand-supplier link tracks whether the supplier carries this brand
            // on the shelf or whether it needs to be ordered.
            try db.alter(table: "brand_supplier_links") { t in
                t.add(column: "carry_status", .text).defaults(to: "carry_on_shelf")
            }
        }
    }

    // MARK: - Migration 067: Cascade Pricing Costs

    private static func registerMigration067CascadePricingCosts(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("067_cascade_pricing_costs") { db in
            // Type-level default cost: all colors of this type inherit unless overridden.
            try db.alter(table: "part_types") { t in
                t.add(column: "default_unit_cost", .double)
            }

            // Color-level cost override: takes precedence over the type default.
            try db.alter(table: "part_colors") { t in
                t.add(column: "unit_cost", .double)
            }

            // Color × Supplier costs: per-supplier cost for a specific color.
            // Cascade: Supplier cost → Color cost → Type default cost.
            try db.create(table: "color_supplier_costs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("color_id", .integer).notNull()
                    .references("part_colors", onDelete: .cascade)
                t.column("supplier_id", .integer).notNull()
                    .references("suppliers", onDelete: .cascade)
                t.column("cost", .double).notNull()
                t.column("notes", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
                t.uniqueKey(["color_id", "supplier_id"])
            }
        }
    }

    // MARK: - Migration 068: Warehouse Zones + Progress V2

    private static func registerMigration068WarehouseZonesProgressV2(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("068_warehouse_zones_progress_v2") { db in
            // Warehouse zones: logical areas on the floor plan (staging, storage, receiving, etc.)
            try db.create(table: "warehouse_zones") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("floor_plan_id", .integer).notNull()
                    .references("warehouse_floor_plans", onDelete: .cascade)
                t.column("zone_type", .text).notNull()
                t.column("label", .text)
                t.column("color_hex", .text)
                t.column("grid_x", .integer).notNull().defaults(to: 0)
                t.column("grid_y", .integer).notNull().defaults(to: 0)
                t.column("grid_width", .integer).notNull().defaults(to: 4)
                t.column("grid_height", .integer).notNull().defaults(to: 4)
                t.column("rotation", .integer).notNull().defaults(to: 0)
                t.column("zone_order", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }

            // Expand onboarding progress with flexible JSON-based step tracking.
            // flow_type: "floor_plan" (9-step) or "parts" (3-step)
            try db.alter(table: "warehouse_onboarding_progress") { t in
                t.add(column: "flow_type", .text).notNull().defaults(to: "floor_plan")
                t.add(column: "total_steps", .integer).notNull().defaults(to: 6)
                t.add(column: "steps_progress", .text)
            }

            // Link storage units to zones (optional — unzoned units are fine)
            try db.alter(table: "warehouse_storage_units") { t in
                t.add(column: "zone_id", .integer).references("warehouse_zones")
            }
        }
    }

    private static func registerMigration069ScheduleConfigTables(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("069_schedule_config_tables") { db in
            // Shift templates: role-aware shift definitions
            try db.create(table: "shift_templates") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("hat_id", .integer).references("hats", onDelete: .setNull)
                t.column("work_days", .text).notNull()   // JSON array: ["mon","tue",...]
                t.column("start_time", .text).notNull()   // "HH:MM"
                t.column("end_time", .text).notNull()     // "HH:MM"
                t.column("break_minutes", .integer).defaults(to: 30)
                t.column("break_paid", .integer).defaults(to: 0) // 0=unpaid, 1=paid
                t.column("overtime_rule", .text).defaults(to: "company_default")
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }

            // Company holidays
            try db.create(table: "company_holidays") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("date", .text).notNull()          // "YYYY-MM-DD"
                t.column("is_paid", .integer).defaults(to: 1) // 1=paid, 0=unpaid
                t.column("is_recurring", .integer).defaults(to: 0) // 1=annually
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }
        }
    }
}

extension AppDatabase {
    private static func registerMigration060PermissionKeysExpansion(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("060_permission_keys_expansion") { db in
            // New fine-grained permission keys for jobs, scheduling, approvals, and admin.
            // These complement existing keys (manage_jobs, manage_fleet, etc.) with
            // more granular controls for viewing financials, creating jobs, self-assigning, etc.

            let newPermissions: [(key: String, hatNames: [String])] = [
                // Jobs
                ("view_job_financials", ["Admin", "Manager", "Office"]),
                ("create_jobs", ["Admin", "Manager", "Lead", "Office"]),
                ("self_assign_ready_jobs", ["Admin", "Manager", "Lead", "Worker"]),
                ("self_assign_contact_jobs", ["Admin", "Manager", "Worker"]),
                ("view_all_jobs", ["Admin", "Manager", "Lead", "Office"]),
                ("view_job_reports", ["Admin", "Manager", "Lead", "Office"]),
                // Scheduling
                ("approve_time_off", ["Admin", "Manager", "Office"]),
                // Orders
                ("approve_orders", ["Admin", "Manager", "Office"]),
                // Reports
                ("view_spending", ["Admin", "Manager", "Office"]),
                // Settings / Audit
                ("view_audit_log", ["Admin"]),
            ]

            for perm in newPermissions {
                for hatName in perm.hatNames {
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
                        SELECT id, ? FROM hats WHERE name = ?
                        """, arguments: [perm.key, hatName])
                }
            }
        }
    }

    // MARK: - Migration 075: companion_feedback — make suggestion_id nullable

    private static func registerMigration076StockMovementsCompositeIndex(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("076_stock_movements_composite_index") { db in
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_movements_part_date_type
                ON stock_movements (part_id, created_at, movement_type)
                WHERE deleted_at IS NULL
                """)
        }
    }

    private static func registerMigration077VehicleIssueReports(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("077_vehicle_issue_reports") { db in
            try db.create(table: "vehicle_issue_reports") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("vehicle_id", .integer).notNull().references("vehicles", onDelete: .cascade)
                t.column("reported_by", .integer).notNull().references("users")
                t.column("severity", .text).notNull()
                t.column("description", .text).notNull()
                t.column("status", .text).notNull().defaults(to: "open")
                t.column("deleted_at", .text)
                t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_vehicle_issue_reports_vehicle", on: "vehicle_issue_reports", columns: ["vehicle_id"])
            try db.create(index: "idx_vehicle_issue_reports_status", on: "vehicle_issue_reports", columns: ["status"])
        }
    }

    private static func registerMigration078PartsRecommendationPermissions(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("078_parts_recommendation_permissions") { db in
            let permissions: [(key: String, hatNames: [String])] = [
                ("parts.approve_recommendation", ["Admin", "Manager"]),
                ("parts.dismiss_recommendation", ["Admin", "Manager"]),
            ]

            for permission in permissions {
                for hatName in permission.hatNames {
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
                        SELECT id, ? FROM hats WHERE name = ?
                        """, arguments: [permission.key, hatName])
                }
            }
        }
    }

    private static func registerMigration079VehicleLocationLogsIndex(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("079_vehicle_location_logs_index") { db in
            try db.create(table: "vehicle_location_logs", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("vehicle_id", .integer).notNull().references("vehicles")
                t.column("user_id", .integer).references("users")
                t.column("latitude", .double)
                t.column("longitude", .double)
                t.column("speed", .double)
                t.column("status", .text).notNull().defaults(to: "unknown")
                t.column("recorded_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_vll_vehicle_latest_live
                ON vehicle_location_logs (vehicle_id, id)
                WHERE deleted_at IS NULL
                """)
        }
    }

    private static func registerMigration080InspectionRecordsVehiclePerformedAtIndex(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("080_inspection_records_vehicle_performed_at_index") { db in
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_ir_vehicle_performed_at_live
                ON inspection_records (vehicle_id, performed_at)
                WHERE deleted_at IS NULL
                """)
        }
    }

    private static func registerMigration081POLineResolvedBrand(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("081_po_line_resolved_brand") { db in
            try addColumnIfMissing(db, table: "po_line_items", column: "brand_id", type: .integer)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_po_line_items_brand
                ON po_line_items (brand_id)
                WHERE deleted_at IS NULL
                """)
        }
    }

    private static func registerMigration082PartsFieldTimestamps(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("082_parts_field_timestamps") { db in
            try addColumnIfMissing(db, table: "parts", column: FieldTimestampHelper.columnName, type: .text)
        }
    }

    private static func registerMigration083StructuredEstimationReviews(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("083_structured_estimation_reviews") { db in
            try addColumnIfMissing(db, table: "estimation_reviews", column: "delay_factors", type: .text)
            try addColumnIfMissing(db, table: "estimation_reviews", column: "on_track_status", type: .text)
            try addColumnIfMissing(db, table: "estimation_reviews", column: "unresolved_question_count", type: .integer)
            try addColumnIfMissing(db, table: "estimation_reviews", column: "crew_feedback", type: .text)
            try addColumnIfMissing(db, table: "estimation_reviews", column: "gc_rating", type: .integer)

            if try !db.tableExists("estimation_question_accuracy_reviews") {
                try db.create(table: "estimation_question_accuracy_reviews") { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("review_id", .integer).notNull()
                        .references("estimation_reviews", onDelete: .cascade)
                    t.column("question_id", .integer).notNull()
                        .references("estimation_questions")
                    t.column("predicted_impact", .text)
                    t.column("actual_impact", .text)
                    t.column("accuracy_rating", .integer).notNull()
                    t.column("notes", .text)
                    t.column("created_at", .text).defaults(sql: "(datetime('now'))")
                }
            }

            if try !db.tableExists("estimation_question_candidates") {
                try db.create(table: "estimation_question_candidates") { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("question_text", .text).notNull()
                    t.column("question_group", .text).notNull()
                    t.column("stage", .text).notNull()
                    t.column("answer_type", .text).notNull().defaults(to: "text")
                    t.column("rationale", .text)
                    t.column("source_signal", .text)
                    t.column("status", .text).notNull().defaults(to: "pending")
                    t.column("generated_at", .text).defaults(sql: "(datetime('now'))")
                    t.column("reviewed_by", .integer).references("users")
                    t.column("reviewed_at", .text)
                }
            }
        }
    }

    private static func registerMigration084SyncedTableFieldTimestamps(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("084_synced_table_field_timestamps") { db in
            let syncedTables = ConflictResolver.allowedSyncTables
                .filter { !$0.hasPrefix("_") }
                .sorted()

            for table in syncedTables {
                guard try db.tableExists(table) else { continue }
                try addColumnIfMissing(db, table: table, column: FieldTimestampHelper.columnName, type: .text)
            }
        }
    }

    private static func registerMigration085CoOccurrenceHierarchyUniqueness(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("085_co_occurrence_hierarchy_uniqueness") { db in
            guard try db.tableExists("co_occurrence_pairs") else { return }

            try db.execute(sql: """
                CREATE TABLE co_occurrence_pairs_new (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    category_a_id INTEGER NOT NULL REFERENCES part_categories,
                    category_b_id INTEGER NOT NULL REFERENCES part_categories,
                    co_occurrence_count INTEGER NOT NULL DEFAULT 0,
                    total_jobs_a INTEGER NOT NULL DEFAULT 0,
                    total_jobs_b INTEGER NOT NULL DEFAULT 0,
                    avg_ratio_a_to_b DOUBLE DEFAULT 1.0,
                    confidence DOUBLE DEFAULT 0.0,
                    last_computed TEXT DEFAULT (datetime('now')),
                    points INTEGER NOT NULL DEFAULT 0,
                    style_a_id INTEGER REFERENCES part_styles,
                    style_b_id INTEGER REFERENCES part_styles,
                    type_a_id INTEGER REFERENCES part_types,
                    type_b_id INTEGER REFERENCES part_types,
                    brand_a_id INTEGER REFERENCES brands,
                    brand_b_id INTEGER REFERENCES brands,
                    match_level TEXT NOT NULL DEFAULT 'category',
                    rejection_count INTEGER NOT NULL DEFAULT 0,
                    is_blocked INTEGER NOT NULL DEFAULT 0,
                    tied_cooldown_until TEXT,
                    _field_timestamps TEXT
                )
                """)

            try db.execute(sql: """
                INSERT INTO co_occurrence_pairs_new
                    (id, category_a_id, category_b_id, co_occurrence_count,
                     total_jobs_a, total_jobs_b, avg_ratio_a_to_b, confidence,
                     last_computed, points, style_a_id, style_b_id, type_a_id,
                     type_b_id, brand_a_id, brand_b_id, match_level,
                     rejection_count, is_blocked, tied_cooldown_until, _field_timestamps)
                SELECT id, category_a_id, category_b_id, co_occurrence_count,
                       total_jobs_a, total_jobs_b, avg_ratio_a_to_b, confidence,
                       last_computed, points, style_a_id, style_b_id, type_a_id,
                       type_b_id, brand_a_id, brand_b_id, match_level,
                       rejection_count, is_blocked, tied_cooldown_until, _field_timestamps
                FROM co_occurrence_pairs
                """)

            try db.execute(sql: "DROP TABLE co_occurrence_pairs")
            try db.execute(sql: "ALTER TABLE co_occurrence_pairs_new RENAME TO co_occurrence_pairs")
            try db.create(index: "idx_co_occurrence_level", on: "co_occurrence_pairs", columns: ["match_level", "points"], ifNotExists: true)
            try db.create(index: "idx_co_occurrence_blocked", on: "co_occurrence_pairs", columns: ["is_blocked", "match_level"], ifNotExists: true)
            try db.create(
                index: "idx_co_occurrence_hierarchy_pair",
                on: "co_occurrence_pairs",
                columns: ["match_level", "category_a_id", "category_b_id", "style_a_id", "style_b_id", "type_a_id", "type_b_id"],
                ifNotExists: true
            )
        }
    }

    private static func registerMigration086PartsAutoAddWishlistToggle(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("086_parts_auto_add_wishlist_toggle") { db in
            try addColumnIfMissing(
                db,
                table: "parts",
                column: "auto_add_to_wishlist",
                type: .integer,
                defaultValue: 0
            )

            for hatName in ["Admin", "Manager"] {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
                    SELECT id, 'wishlist.configure_auto_add' FROM hats WHERE name = ?
                    """, arguments: [hatName])
            }
        }
    }

    private static func registerMigration087WishlistLocationRouting(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("087_wishlist_location_routing") { db in
            try addColumnIfMissing(db, table: "wishlist_items", column: "location_type", type: .text)
            try addColumnIfMissing(db, table: "wishlist_items", column: "location_id", type: .integer)
            try db.create(
                index: "idx_wishlist_part_location_status",
                on: "wishlist_items",
                columns: ["part_id", "location_type", "location_id", "status"],
                ifNotExists: true
            )
        }
    }

    private static func registerMigration075CompanionFeedbackNullableSuggestionId(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("075_companion_feedback_nullable_suggestion_id") { db in
            try db.execute(sql: """
                CREATE TABLE companion_feedback_new (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    suggestion_id INTEGER REFERENCES companion_suggestions,
                    rule_id INTEGER REFERENCES companion_rules,
                    action TEXT NOT NULL,
                    suggested_qty INTEGER NOT NULL,
                    final_qty INTEGER,
                    source_categories TEXT,
                    target_category_id INTEGER,
                    target_style_id INTEGER,
                    user_id INTEGER REFERENCES users,
                    created_at TEXT DEFAULT (datetime('now'))
                )
                """)
            try db.execute(sql: """
                INSERT INTO companion_feedback_new
                    (id, suggestion_id, rule_id, action, suggested_qty, final_qty,
                     source_categories, target_category_id, target_style_id, user_id, created_at)
                SELECT id, suggestion_id, rule_id, action, suggested_qty, final_qty,
                       source_categories, target_category_id, target_style_id, user_id, created_at
                FROM companion_feedback
                """)
            try db.execute(sql: "DROP TABLE companion_feedback")
            try db.execute(sql: "ALTER TABLE companion_feedback_new RENAME TO companion_feedback")
        }
    }

    private static func registerMigration088WarehouseOnboardingNineStepProgress(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("088_warehouse_onboarding_nine_step_progress") { db in
            try addColumnIfMissing(db, table: "warehouse_onboarding_progress", column: "completed_steps", type: .text)
            try addColumnIfMissing(db, table: "warehouse_onboarding_progress", column: "skipped_steps", type: .text)
            try db.execute(sql: """
                UPDATE warehouse_onboarding_progress
                SET total_steps = 9
                WHERE flow_type = 'floor_plan'
                  AND total_steps < 9
                """)
        }
    }

    private static func registerMigration089BreakPolicyPresets(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("089_break_policy_presets") { db in
            try seedBreakPolicyPresets(db)
        }
    }
}
