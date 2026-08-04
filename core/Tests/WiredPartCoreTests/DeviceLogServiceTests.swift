import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// Fleet diagnostics: logs must replicate, prune themselves, and never carry
/// secrets between devices (owner request 2026-08-03).
@Suite("Device log service")
struct DeviceLogServiceTests {

    private func makeService(deviceId: String = "dev-A") throws -> (AppDatabase, DeviceLogService) {
        let db = try AppDatabase.openInMemoryDatabase()
        return (db, DeviceLogService(db: db, deviceId: deviceId, deviceName: "Test \(deviceId)", appVersion: "1.0.0"))
    }

    @Test("Entries are written and read newest-first, filterable by level and device")
    func writeAndRead() throws {
        let (_, svc) = try makeService()
        svc.info("startup", "app launched")
        svc.error("sync", "join failed", detail: #"{"seconds":8}"#)
        let all = try svc.recent()
        #expect(all.count == 2)
        #expect(all.first?.message == "join failed")   // newest first
        let errorsOnly = try svc.recent(level: .error)
        #expect(errorsOnly.count == 1)
        #expect(errorsOnly.first?.category == "sync")
        #expect(errorsOnly.first?.detail == #"{"seconds":8}"#)
        #expect(try svc.recent(deviceId: "nobody").isEmpty)
    }

    @Test("Logs REPLICATE — writes are change-tracked like company data")
    func logsAreChangeTracked() throws {
        let (db, svc) = try makeService()
        svc.error("sync", "pairing timed out")
        let logged = try db.writer.read { dbc in
            try Int.fetchOne(dbc, sql: """
                SELECT COUNT(*) FROM _change_log
                WHERE table_name = 'device_logs' AND operation = 'INSERT'
                """) ?? 0
        }
        #expect(logged >= 1, "device_logs writes must enter the sync change log")
        #expect(ConflictResolver.allowedSyncTables.contains("device_logs"))
    }

    @Test("Fleet view: one device reads another device's synced-in logs")
    func fleetView() throws {
        let (db, macService) = try makeService(deviceId: "mac-shop")
        macService.info("startup", "shop mac up")
        // Simulate an iPad's log arriving over sync.
        try db.writer.write { dbc in
            try dbc.execute(sql: """
                INSERT INTO device_logs (device_id, device_name, app_version, level, category, message)
                VALUES ('ipad-field', 'I Work Tablet', '1.0.0', 'error', 'sync', 'download stalled at 8s')
                """)
        }
        let summary = try macService.deviceSummary()
        #expect(summary.count == 2)
        let ipad = summary.first { $0.deviceId == "ipad-field" }
        #expect(ipad?.deviceName == "I Work Tablet")
        #expect(ipad?.errors == 1)
        let fieldErrors = try macService.recent(level: .error, deviceId: "ipad-field")
        #expect(fieldErrors.first?.message == "download stalled at 8s")
    }

    @Test("Prune removes entries past the retention window and keeps recent ones")
    func pruneByAge() throws {
        let (db, svc) = try makeService()
        svc.info("sync", "fresh entry")
        try db.writer.write { dbc in
            try dbc.execute(sql: """
                INSERT INTO device_logs (device_id, level, category, message, created_at)
                VALUES ('dev-A', 'info', 'sync', 'ancient entry', datetime('now', '-45 days'))
                """)
        }
        #expect(try svc.recent().count == 2)
        let removed = try svc.prune()
        #expect(removed >= 1)
        let left = try svc.recent()
        #expect(left.count == 1)
        #expect(left.first?.message == "fresh entry")
    }

    @Test("Secrets never reach a replicated log line")
    func redaction() throws {
        let (_, svc) = try makeService()
        svc.error("agent-link", "minted wpal_AbCdEfGhIjKlMnOpQrStUvWxYz012345 for Claude")
        svc.error("auth", "token: sk-super-secret-value")
        let lines = try svc.recent().map(\.message)
        #expect(lines.allSatisfy { !$0.contains("wpal_AbCdEfGhIjKlMnOpQrStUvWxYz012345") })
        #expect(lines.allSatisfy { !$0.lowercased().contains("sk-super-secret-value") })
        #expect(lines.contains { $0.contains("[redacted]") })
    }
}
