import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// Fleet diagnostics: logs must replicate their important entries, prune
/// themselves per level, and never carry secrets between devices (owner
/// requests 2026-08-03 and 2026-08-15).
@Suite("Device log service")
struct DeviceLogServiceTests {

    private func makeService(
        deviceId: String = "dev-A",
        verbose: Bool = true
    ) throws -> (AppDatabase, DeviceLogService) {
        let db = try AppDatabase.openInMemoryDatabase()
        let device = DeviceLogService.DeviceInfo(
            deviceId: deviceId,
            fingerprint: "fp-\(deviceId)",
            name: "Test \(deviceId)",
            appVersion: "1.0.0",
            buildNumber: "67",
            osVersion: "27.0",
            platform: "ios",
            model: "iPhone17_1"
        )
        return (db, DeviceLogService(db: db, device: device, verboseEnabled: verbose))
    }

    @Test("Entries are written and read newest-first, filterable by level and device")
    func writeAndRead() throws {
        let (_, svc) = try makeService()
        svc.info("startup", "app launched")
        svc.error("sync", "join failed", detail: #"{"seconds":8}"#)
        let all = try svc.recent()
        #expect(all.count == 2)
        #expect(all.first?.message == "join failed")   // newest first
        let errorsOnly = try svc.recent(filter: .init(levels: [.error]))
        #expect(errorsOnly.count == 1)
        #expect(errorsOnly.first?.category == "sync")
        #expect(errorsOnly.first?.detail == #"{"seconds":8}"#)
        #expect(try svc.recent(filter: .init(deviceIds: ["nobody"])).isEmpty)
    }

    @Test("Logs at warn and above REPLICATE — writes are change-tracked like company data")
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

    /// Owner-approved 2026-08-15: verbose logging stays local so N devices'
    /// debug output cannot cross-replicate over the Bluetooth transport.
    @Test("Debug and trace do NOT replicate — the sync payload stays bounded")
    func verboseStaysLocal() throws {
        let (db, svc) = try makeService()
        svc.debug("sync", "batch 3 of 41 applied")
        svc.trace("sync", "row 118 merged")
        svc.info("sync", "snapshot complete")

        let replicated = try db.writer.read { dbc in
            try Int.fetchOne(dbc, sql: """
                SELECT COUNT(*) FROM _change_log WHERE table_name = 'device_logs'
                """) ?? 0
        }
        #expect(replicated == 0, "nothing below warn may enter the sync payload")
        #expect(try svc.recent().count == 3, "but all three are readable locally")

        svc.warn("sync", "peer dropped")
        let afterWarn = try db.writer.read { dbc in
            try Int.fetchOne(dbc, sql: """
                SELECT COUNT(*) FROM _change_log WHERE table_name = 'device_logs'
                """) ?? 0
        }
        #expect(afterWarn == 1, "warn and above must replicate")
    }

    @Test("The developer toggle keeps verbose entries out of the database entirely")
    func verboseToggleOff() throws {
        let (_, svc) = try makeService(verbose: false)
        svc.debug("sync", "noisy")
        svc.trace("sync", "noisier")
        svc.info("sync", "kept")
        let all = try svc.recent()
        #expect(all.count == 1)
        #expect(all.first?.level == .info)
    }

    /// Whole-second timestamps could not order two devices' entries against
    /// each other, which is the one thing this table exists to support.
    @Test("Timestamps carry milliseconds so same-second entries stay ordered")
    func millisecondTimestamps() throws {
        let (_, svc) = try makeService()
        for i in 1...5 { svc.info("sync", "step \(i)") }
        let all = try svc.recent()
        #expect(all.count == 5)
        #expect(
            all.allSatisfy { $0.createdAt.contains(".") },
            "created_at must have sub-second precision, got \(all.map(\.createdAt))"
        )
        // Newest-first, and strictly ordered even though all five land inside
        // the same second.
        #expect(all.map(\.message) == ["step 5", "step 4", "step 3", "step 2", "step 1"])
        #expect(all.compactMap(\.seq) == [5, 4, 3, 2, 1], "per-device seq must be monotonic")
    }

    @Test("minLevel means 'this level and worse', and survives a sender that never wrote severity")
    func minLevelOrdering() throws {
        let (db, svc) = try makeService()
        svc.debug("sync", "d")
        svc.info("sync", "i")
        svc.warn("sync", "w")
        svc.error("sync", "e")
        svc.critical("startup", "c")

        let warnAndWorse = try svc.recent(filter: .init(minLevel: .warn))
        #expect(Set(warnAndWorse.map(\.message)) == ["w", "e", "c"])

        // A peer running an older build sends a row with no severity of its
        // own; the column default (30) would misrepresent it as info. Filtering
        // must still find it.
        try db.writer.write { dbc in
            try dbc.execute(sql: """
                INSERT INTO device_logs (device_id, level, category, message)
                VALUES ('old-sender', 'error', 'sync', 'legacy error')
                """)
        }
        let stillFound = try svc.recent(filter: .init(minLevel: .warn))
        #expect(
            stillFound.contains { $0.message == "legacy error" },
            "a level-correct row with a defaulted severity must not be filtered out"
        )
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
        let fieldErrors = try macService.recent(
            filter: .init(levels: [.error], deviceIds: ["ipad-field"])
        )
        #expect(fieldErrors.first?.message == "download stalled at 8s")
    }

    /// Owner 2026-08-15: *"the log is suposed to be per a device with all the
    /// relvint info on the device … including the incompy device id"*.
    @Test("Every entry carries the originating device's identity")
    func perDeviceIdentity() throws {
        let (_, svc) = try makeService(deviceId: "iphone-field")
        svc.error("sync", "join failed")
        let entry = try #require(try svc.recent().first)
        #expect(entry.deviceId == "iphone-field")
        #expect(entry.deviceFingerprint == "fp-iphone-field")
        #expect(entry.deviceName == "Test iphone-field")
        #expect(entry.appVersion == "1.0.0")
        #expect(entry.buildNumber == "67")
        #expect(entry.osVersion == "27.0")
        #expect(entry.platform == "ios")
        #expect(entry.deviceModel == "iPhone17_1")
        #expect(entry.utcOffsetMinutes != nil)
    }

    /// Owner 2026-08-15: *"filters so we can find the info then work are way
    /// out if needed"*.
    @Test("Context expansion returns the entries surrounding a chosen line")
    func contextAroundAnEntry() throws {
        let (_, svc) = try makeService()
        for i in 1...20 { svc.info("sync", "step \(i)") }
        let all = try svc.recent()
        let anchor = try #require(all.first { $0.message == "step 10" })

        let window = try svc.context(around: anchor.id, before: 3, after: 3)
        #expect(window.map(\.message) == [
            "step 7", "step 8", "step 9", "step 10", "step 11", "step 12", "step 13",
        ], "oldest-first window centred on the anchor")
    }

    @Test("Cross-device context interleaves both sides of a sync failure")
    func contextAcrossDevices() throws {
        let (db, svc) = try makeService(deviceId: "mac-shop")
        svc.error("sync", "host: batch rejected")
        let anchor = try #require(try svc.recent().first)
        try db.writer.write { dbc in
            try dbc.execute(sql: """
                INSERT INTO device_logs (device_id, level, severity, category, message, created_at)
                VALUES ('iphone-field', 'error', 50, 'sync', 'joiner: commit failed',
                        strftime('%Y-%m-%d %H:%M:%f','now'))
                """)
        }
        let merged = try svc.contextAcrossDevices(around: anchor.id, seconds: 30)
        #expect(Set(merged.map(\.deviceId)) == ["mac-shop", "iphone-field"])
    }

    @Test("Prune removes entries past their level's retention window and keeps recent ones")
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

    /// Migration 121's single global newest-wins cap let a noisy level evict a
    /// quiet one. Retention and caps are per level so that cannot happen.
    @Test("A debug flood cannot evict a single error")
    func debugFloodCannotEvictErrors() throws {
        let (db, svc) = try makeService()
        svc.error("sync", "the one error that matters")

        // Far more debug rows than the debug cap allows.
        let flood = DeviceLogService.maxRows(for: .debug) + 500
        try db.writer.write { dbc in
            for i in 0..<flood {
                try dbc.execute(
                    sql: """
                    INSERT INTO device_logs (device_id, level, severity, category, message, seq, created_at)
                    VALUES ('dev-A', 'debug', 20, 'sync', ?, ?, strftime('%Y-%m-%d %H:%M:%f','now'))
                    """,
                    arguments: ["noise \(i)", i]
                )
            }
        }

        try svc.prune()

        let errorsLeft = try svc.recent(filter: .init(levels: [.error]))
        #expect(
            errorsLeft.contains { $0.message == "the one error that matters" },
            "the error must survive a debug flood"
        )
        let debugLeft = try db.writer.read { dbc in
            try Int.fetchOne(dbc, sql: "SELECT COUNT(*) FROM device_logs WHERE level = 'debug'") ?? 0
        }
        #expect(debugLeft <= DeviceLogService.maxRows(for: .debug), "debug must be capped")
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

    /// `_` is a LIKE wildcard and this codebase is full of snake_case, so an
    /// unescaped search would match almost everything.
    @Test("Free-text search treats underscores and percent signs literally")
    func searchEscaping() throws {
        let (_, svc) = try makeService()
        svc.error("sync", "no such column: deleted_at")
        svc.error("sync", "no such column: deletedXat")
        let hits = try svc.recent(filter: .init(search: "deleted_at"))
        #expect(hits.count == 1)
        #expect(hits.first?.message.contains("deleted_at") == true)
    }
}
