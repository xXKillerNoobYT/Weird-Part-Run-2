import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("Backup Restore Data Safety Tests", .serialized)
struct BackupRestoreDataSafetyTests {
    @Test("Restore from a missing backup leaves the current database file untouched")
    func testRestoreMissingBackupLeavesCurrentDatabaseUntouched() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("wei-1103-restore-missing-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let targetPath = directory.appendingPathComponent("live.sqlite").path
        let missingBackupPath = directory.appendingPathComponent("missing-backup.sqlite").path
        let liveBytes = Data("live database bytes".utf8)
        try liveBytes.write(to: URL(fileURLWithPath: targetPath))

        do {
            try AppDatabase.restoreDatabase(from: missingBackupPath, to: targetPath)
            Issue.record("Restore should throw when the backup file is missing")
        } catch {
            let preservedBytes = try Data(contentsOf: URL(fileURLWithPath: targetPath))
            #expect(preservedBytes == liveBytes)
        }
    }

    @Test("Restore rolls back the whole live bundle when staged sidecar promotion fails")
    func testRestoreRollbackAfterPartialStagedPromotionFailure() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("wei-1103-restore-partial-promotion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let targetPath = directory.appendingPathComponent("live.sqlite").path
        let backupPath = directory.appendingPathComponent("backup.sqlite").path
        let liveBytes = Data("live database bytes".utf8)
        let liveWalBytes = Data("live wal bytes".utf8)
        let liveShmBytes = Data("live shm bytes".utf8)
        let backupBytes = Data("backup database bytes".utf8)
        let backupWalBytes = Data("backup wal bytes".utf8)

        try liveBytes.write(to: URL(fileURLWithPath: targetPath))
        try liveWalBytes.write(to: URL(fileURLWithPath: targetPath + "-wal"))
        try liveShmBytes.write(to: URL(fileURLWithPath: targetPath + "-shm"))
        try backupBytes.write(to: URL(fileURLWithPath: backupPath))
        try backupWalBytes.write(to: URL(fileURLWithPath: backupPath + "-wal"))

        do {
            try AppDatabase.restoreDatabase(from: backupPath, to: targetPath) {
                // The live bundle has already been moved to rollback storage. Place
                // an incompatible item at the WAL destination so the staged base DB
                // can be promoted first, then sidecar promotion throws.
                try FileManager.default.createDirectory(atPath: targetPath + "-wal", withIntermediateDirectories: false)
            }
            Issue.record("Restore should throw when staged sidecar promotion fails")
        } catch {
            #expect(try Data(contentsOf: URL(fileURLWithPath: targetPath)) == liveBytes)
            #expect(try Data(contentsOf: URL(fileURLWithPath: targetPath + "-wal")) == liveWalBytes)
            #expect(try Data(contentsOf: URL(fileURLWithPath: targetPath + "-shm")) == liveShmBytes)
        }
    }

    @Test("Repeated rapid backups all create usable snapshots")
    func testRapidRepeatedBackupsDoNotCollide() throws {
        let fixture = try Self.makeCriticalFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let sourceSnapshot = try Self.snapshot(at: fixture.databasePath)
        var backupPaths: [String] = []
        for index in 0..<20 {
            let backupPath = try #require(AppDatabase.backupDatabase(atPath: fixture.databasePath))
            backupPaths.append(backupPath)
            #expect(FileManager.default.fileExists(atPath: backupPath))

            let restoredPath = fixture.directory.appendingPathComponent("rapid-restore-\(index).sqlite").path
            try AppDatabase.restoreDatabase(from: backupPath, to: restoredPath)
            let restoredSnapshot = try Self.snapshot(at: restoredPath)
            #expect(restoredSnapshot == sourceSnapshot)
        }

        #expect(Set(backupPaths).count == backupPaths.count)
        for backupPath in backupPaths.suffix(5) {
            #expect(FileManager.default.fileExists(atPath: backupPath))
        }
    }

    @Test("Production backup and restore preserves critical beta records")
    func testProductionBackupRestorePreservesCriticalBetaRecords() throws {
        let fixture = try Self.makeCriticalFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let sourceSnapshot = try Self.snapshot(at: fixture.databasePath)
        let backupPath = try #require(AppDatabase.backupDatabase(atPath: fixture.databasePath))
        let restoredPath = fixture.directory.appendingPathComponent("restored-production.sqlite").path

        try AppDatabase.restoreDatabase(from: backupPath, to: restoredPath)
        _ = try AppDatabase.openDatabase(atPath: restoredPath)

        let restoredSnapshot = try Self.snapshot(at: restoredPath)
        #expect(restoredSnapshot == sourceSnapshot)
        Self.assertCriticalSnapshot(restoredSnapshot)
    }

    private struct Fixture {
        let directory: URL
        let databasePath: String
    }

    private struct CriticalSnapshot: Equatable {
        let schemaVersion: String?
        let partName: String?
        let stockQuantity: Int
        let stockMovementQuantity: Int
        let jobName: String?
        let jobMaterialQuantity: Int
        let returnedMaterialQuantity: Int
        let laborHours: Double
        let clockOutAnswer: String?
        let dailyReportStatus: String?
        let purchaseOrderNumber: String?
        let jpoNumber: String?
        let jpoQuantityRequested: Int
        let receivedQuantity: Int
        let receivingSessionStatus: String?
        let receivingItemQuantity: Int
        let returnNumber: String?
        let returnQuantity: Int
        let orderHistoryStatus: String?
        let priceHistoryCost: Double
        let savedReportName: String?
        let reportAnnotation: String?
        let reportTemplateName: String?
        let auditEventType: String?
    }

    private static func makeCriticalFixture() throws -> Fixture {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("wei-3986-backup-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let databasePath = directory.appendingPathComponent("production.sqlite").path
        let appDatabase = try AppDatabase.openDatabase(atPath: databasePath)
        try seedCriticalRecords(in: appDatabase.writer)
        return Fixture(directory: directory, databasePath: databasePath)
    }

    private static func seedCriticalRecords(in writer: any DatabaseWriter) throws {
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO users (display_name, email, pin_hash)
                VALUES ('WEI-3986 Beta Foreman', 'wei-3986@example.invalid', 'fixture-pin-hash')
                """)
            let userId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO suppliers (name, email, is_active)
                VALUES ('WEI-3986 Fixture Supply', 'supplier@example.invalid', 1)
                """)
            let supplierId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO part_categories (name, description)
                VALUES ('WEI-3986 Fixtures', 'Backup restore fixture category')
                """)
            let categoryId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO parts (category_id, code, name, company_cost_price, company_markup_percent, min_stock_level, target_stock_level)
                VALUES (?, 'WEI-3986-PART', 'WEI-3986 Service Disconnect', 12.50, 20.0, 5, 25)
                """, arguments: [categoryId])
            let partId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO stock (part_id, location_type, location_id, qty, supplier_id)
                VALUES (?, 'warehouse', 1, 42, ?)
                """, arguments: [partId, supplierId])

            try db.execute(sql: """
                INSERT INTO jobs (job_number, job_name, customer_name, status, priority, job_type, lead_user_id, created_by, estimated_hours)
                VALUES ('JOB-WEI-3986', 'WEI-3986 Beta Upgrade Job', 'Backup Fixture Customer', 'active', 'high', 'commercial', ?, ?, 8.0)
                """, arguments: [userId, userId])
            let jobId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO stock_movements (part_id, qty, to_location_type, to_location_id, supplier_id, movement_type, reason, reference_number, job_id, performed_by, unit_cost_at_move)
                VALUES (?, 42, 'warehouse', 1, ?, 'receive', 'Fixture receiving movement survives restore', 'RCV-WEI-3986', ?, ?, 12.50)
                """, arguments: [partId, supplierId, jobId, userId])

            try db.execute(sql: """
                INSERT INTO job_parts (job_id, part_id, qty_consumed, qty_returned, unit_cost_at_consume, consumed_by, notes)
                VALUES (?, ?, 3, 1, 12.50, ?, 'Fixture material and return quantity survive restore')
                """, arguments: [jobId, partId, userId])

            try db.execute(sql: """
                INSERT INTO labor_entries (user_id, job_id, clock_in, clock_out, regular_hours, status, notes)
                VALUES (?, ?, '2026-06-01T08:00:00Z', '2026-06-01T16:00:00Z', 8.0, 'approved', 'Fixture labor survives restore')
                """, arguments: [userId, jobId])
            let laborEntryId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO clock_out_questions (question_text, answer_type, is_required, sort_order, created_by)
                VALUES ('WEI-3986 final data safety check?', 'text', 1, 1, ?)
                """, arguments: [userId])
            let clockOutQuestionId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO clock_out_responses (labor_entry_id, question_id, answer_text)
                VALUES (?, ?, 'All critical beta records verified')
                """, arguments: [laborEntryId, clockOutQuestionId])

            try db.execute(sql: """
                INSERT INTO daily_reports (job_id, report_date, report_json, status, reviewed_by, reviewed_at)
                VALUES (?, '2026-06-01', '{"preBilling":"ready","bookkeeper":"reviewed"}', 'reviewed', ?, '2026-06-01T17:30:00Z')
                """, arguments: [jobId, userId])

            try db.execute(sql: """
                INSERT INTO job_parts_orders (job_id, order_number, status, priority, order_type, requested_by, approved_by, approved_at, notes)
                VALUES (?, 'JPO-WEI-3986', 'approved', 'high', 'job', ?, ?, '2026-06-01T09:00:00Z', 'Fixture JPO survives restore')
                """, arguments: [jobId, userId, userId])
            let jpoId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO jpo_line_items (jpo_id, part_id, qty_requested, qty_ordered, qty_received, priority, suggested_supplier_id, notes)
                VALUES (?, ?, 5, 5, 5, 'high', ?, 'Fixture JPO line survives restore')
                """, arguments: [jpoId, partId, supplierId])

            try db.execute(sql: """
                INSERT INTO purchase_orders (po_number, supplier_id, status, order_date, subtotal, total_cost, submitted_by)
                VALUES ('PO-WEI-3986', ?, 'ordered', '2026-06-01', 62.50, 62.50, ?)
                """, arguments: [supplierId, userId])
            let poId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO po_line_items (po_id, part_id, qty_ordered, qty_received, unit_cost, received_unit_cost, status, received_by, received_at)
                VALUES (?, ?, 5, 5, 12.50, 12.50, 'received', ?, '2026-06-01T10:00:00Z')
                """, arguments: [poId, partId, userId])
            let poLineId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO receiving_sessions (po_id, started_by, mode, status, completed_at, notes)
                VALUES (?, ?, 'packing_slip', 'completed', '2026-06-01T10:30:00Z', 'Fixture receiving session survives restore')
                """, arguments: [poId, userId])
            let receivingSessionId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO receiving_session_items (session_id, po_line_id, expected_qty, received_qty, actual_cost, scanned_at, notes)
                VALUES (?, ?, 5, 5, 12.50, '2026-06-01T10:15:00Z', 'Fixture received line survives restore')
                """, arguments: [receivingSessionId, poLineId])

            try db.execute(sql: """
                INSERT INTO returns (return_number, return_type, po_id, supplier_id, job_id, status, reason, credit_amount, initiated_by, approved_by, approved_at)
                VALUES ('RET-WEI-3986', 'supplier', ?, ?, ?, 'approved', 'Fixture return survives restore', 12.50, ?, ?, '2026-06-01T12:00:00Z')
                """, arguments: [poId, supplierId, jobId, userId, userId])
            let returnId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO return_line_items (return_id, part_id, po_line_id, qty, condition, disposition, unit_cost, notes)
                VALUES (?, ?, ?, 1, 'new', 'return_to_supplier', 12.50, 'Fixture return line survives restore')
                """, arguments: [returnId, partId, poLineId])

            try db.execute(sql: """
                INSERT INTO order_status_history (entity_type, entity_id, old_status, new_status, changed_by, notes)
                VALUES ('purchase_order', ?, 'submitted', 'ordered', ?, 'Fixture order status history survives restore')
                """, arguments: [poId, userId])

            try db.execute(sql: """
                INSERT INTO price_history (part_id, change_type, old_value, new_value, old_sell_price, new_sell_price, source, source_id, changed_by)
                VALUES (?, 'cost_update', 10.00, 12.50, 12.00, 15.00, 'receiving', ?, ?)
                """, arguments: [partId, receivingSessionId, userId])

            try db.execute(sql: """
                INSERT INTO report_annotations (report_type, context_key, content, author_id)
                VALUES ('pre_billing', 'JOB-WEI-3986', 'WEI-3986 pre-billing reviewed', ?)
                """, arguments: [userId])

            try db.execute(sql: """
                INSERT INTO report_templates (name, report_type, config_json, created_by)
                VALUES ('WEI-3986 Bookkeeper Export', 'bookkeeper', '{"columns":["labor","materials","returns"]}', ?)
                """, arguments: [userId])

            try db.execute(sql: """
                INSERT INTO audit_sessions_v2 (session_type, started_by, status, parts_counted, discrepancies_found, completed_at)
                VALUES ('cycle_count', ?, 'completed', 1, 0, '2026-06-01T13:00:00Z')
                """, arguments: [userId])
            let auditSessionId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO audit_session_events (session_id, event_type, notes, recorded_by)
                VALUES (?, 'beta_restore_verification', 'Fixture audit event survives restore', ?)
                """, arguments: [auditSessionId, userId])

            try db.execute(sql: """
                INSERT INTO saved_reports (name, report_type, columns_json, filters_json, created_by, is_shared, last_run_at)
                VALUES ('WEI-3986 Job Cost Rollup', 'job_cost', '["job","materials","labor"]', '{"job":"JOB-WEI-3986"}', ?, 1, '2026-06-01T17:00:00Z')
                """, arguments: [userId])
        }
    }

    private static func snapshot(at path: String) throws -> CriticalSnapshot {
        try DatabaseQueue(path: path).read { db in
            CriticalSnapshot(
                schemaVersion: try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'db_schema_version'"),
                partName: try String.fetchOne(db, sql: "SELECT name FROM parts WHERE code = 'WEI-3986-PART'"),
                stockQuantity: try Int.fetchOne(db, sql: "SELECT qty FROM stock WHERE part_id = (SELECT id FROM parts WHERE code = 'WEI-3986-PART')") ?? 0,
                stockMovementQuantity: try Int.fetchOne(db, sql: "SELECT qty FROM stock_movements WHERE reference_number = 'RCV-WEI-3986'") ?? 0,
                jobName: try String.fetchOne(db, sql: "SELECT job_name FROM jobs WHERE job_number = 'JOB-WEI-3986'"),
                jobMaterialQuantity: try Int.fetchOne(db, sql: "SELECT qty_consumed FROM job_parts WHERE job_id = (SELECT id FROM jobs WHERE job_number = 'JOB-WEI-3986') AND part_id = (SELECT id FROM parts WHERE code = 'WEI-3986-PART')") ?? 0,
                returnedMaterialQuantity: try Int.fetchOne(db, sql: "SELECT qty_returned FROM job_parts WHERE job_id = (SELECT id FROM jobs WHERE job_number = 'JOB-WEI-3986') AND part_id = (SELECT id FROM parts WHERE code = 'WEI-3986-PART')") ?? 0,
                laborHours: try Double.fetchOne(db, sql: "SELECT regular_hours FROM labor_entries WHERE job_id = (SELECT id FROM jobs WHERE job_number = 'JOB-WEI-3986')") ?? 0,
                clockOutAnswer: try String.fetchOne(db, sql: "SELECT answer_text FROM clock_out_responses WHERE labor_entry_id = (SELECT id FROM labor_entries WHERE job_id = (SELECT id FROM jobs WHERE job_number = 'JOB-WEI-3986'))"),
                dailyReportStatus: try String.fetchOne(db, sql: "SELECT status FROM daily_reports WHERE job_id = (SELECT id FROM jobs WHERE job_number = 'JOB-WEI-3986')"),
                purchaseOrderNumber: try String.fetchOne(db, sql: "SELECT po_number FROM purchase_orders WHERE po_number = 'PO-WEI-3986'"),
                jpoNumber: try String.fetchOne(db, sql: "SELECT order_number FROM job_parts_orders WHERE order_number = 'JPO-WEI-3986'"),
                jpoQuantityRequested: try Int.fetchOne(db, sql: "SELECT qty_requested FROM jpo_line_items WHERE jpo_id = (SELECT id FROM job_parts_orders WHERE order_number = 'JPO-WEI-3986')") ?? 0,
                receivedQuantity: try Int.fetchOne(db, sql: "SELECT qty_received FROM po_line_items WHERE po_id = (SELECT id FROM purchase_orders WHERE po_number = 'PO-WEI-3986')") ?? 0,
                receivingSessionStatus: try String.fetchOne(db, sql: "SELECT status FROM receiving_sessions WHERE po_id = (SELECT id FROM purchase_orders WHERE po_number = 'PO-WEI-3986')"),
                receivingItemQuantity: try Int.fetchOne(db, sql: "SELECT received_qty FROM receiving_session_items WHERE session_id = (SELECT id FROM receiving_sessions WHERE po_id = (SELECT id FROM purchase_orders WHERE po_number = 'PO-WEI-3986'))") ?? 0,
                returnNumber: try String.fetchOne(db, sql: "SELECT return_number FROM returns WHERE return_number = 'RET-WEI-3986'"),
                returnQuantity: try Int.fetchOne(db, sql: "SELECT qty FROM return_line_items WHERE return_id = (SELECT id FROM returns WHERE return_number = 'RET-WEI-3986')") ?? 0,
                orderHistoryStatus: try String.fetchOne(db, sql: "SELECT new_status FROM order_status_history WHERE entity_type = 'purchase_order' AND entity_id = (SELECT id FROM purchase_orders WHERE po_number = 'PO-WEI-3986')"),
                priceHistoryCost: try Double.fetchOne(db, sql: "SELECT new_value FROM price_history WHERE part_id = (SELECT id FROM parts WHERE code = 'WEI-3986-PART') AND change_type = 'cost_update'") ?? 0,
                savedReportName: try String.fetchOne(db, sql: "SELECT name FROM saved_reports WHERE name = 'WEI-3986 Job Cost Rollup'"),
                reportAnnotation: try String.fetchOne(db, sql: "SELECT content FROM report_annotations WHERE context_key = 'JOB-WEI-3986'"),
                reportTemplateName: try String.fetchOne(db, sql: "SELECT name FROM report_templates WHERE name = 'WEI-3986 Bookkeeper Export'"),
                auditEventType: try String.fetchOne(db, sql: "SELECT event_type FROM audit_session_events WHERE event_type = 'beta_restore_verification'")
            )
        }
    }

    private static func assertCriticalSnapshot(_ snapshot: CriticalSnapshot) {
        let schemaVersion = Int(snapshot.schemaVersion ?? "") ?? 0
        #expect(schemaVersion > 0)
        #expect(snapshot.partName == "WEI-3986 Service Disconnect")
        #expect(snapshot.stockQuantity == 42)
        #expect(snapshot.stockMovementQuantity == 42)
        #expect(snapshot.jobName == "WEI-3986 Beta Upgrade Job")
        #expect(snapshot.jobMaterialQuantity == 3)
        #expect(snapshot.returnedMaterialQuantity == 1)
        #expect(snapshot.laborHours == 8.0)
        #expect(snapshot.clockOutAnswer == "All critical beta records verified")
        #expect(snapshot.dailyReportStatus == "reviewed")
        #expect(snapshot.purchaseOrderNumber == "PO-WEI-3986")
        #expect(snapshot.jpoNumber == "JPO-WEI-3986")
        #expect(snapshot.jpoQuantityRequested == 5)
        #expect(snapshot.receivedQuantity == 5)
        #expect(snapshot.receivingSessionStatus == "completed")
        #expect(snapshot.receivingItemQuantity == 5)
        #expect(snapshot.returnNumber == "RET-WEI-3986")
        #expect(snapshot.returnQuantity == 1)
        #expect(snapshot.orderHistoryStatus == "ordered")
        #expect(snapshot.priceHistoryCost == 12.50)
        #expect(snapshot.savedReportName == "WEI-3986 Job Cost Rollup")
        #expect(snapshot.reportAnnotation == "WEI-3986 pre-billing reviewed")
        #expect(snapshot.reportTemplateName == "WEI-3986 Bookkeeper Export")
        #expect(snapshot.auditEventType == "beta_restore_verification")
    }
}
