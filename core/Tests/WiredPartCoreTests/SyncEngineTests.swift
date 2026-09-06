import Testing
import Foundation
import GRDB
@testable import WiredPartCore

@Suite("SyncEngine Tests")
struct SyncEngineTests {

    private func freshDB() throws -> AppDatabase {
        let db = try AppDatabase.openInMemoryDatabase()
        // Migration 112 backfills seeded reference rows into _change_log; these
        // tests assert on specific tracked entries, so start from an empty log.
        try db.writer.write { dbConn in
            try dbConn.execute(sql: "DELETE FROM _change_log")
        }
        return db
    }

    @Test("Initial state is idle with zero pending")
    func testInitialState() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)
        let state = await engine.getState()
        #expect(state.status == .idle)
        #expect(state.pendingCount == 0)
        #expect(state.consecutiveFailures == 0)
        #expect(state.lastSyncAt == nil)
        #expect(state.error == nil)
    }

    @Test("Sync with empty shop URL returns error")
    func testEmptyShopUrl() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)
        let result = await engine.runSync(
            deviceId: "dev-001",
            shopUrl: "",
            authToken: nil
        )
        #expect(result == false)
        let state = await engine.getState()
        #expect(state.status == .error)
        #expect(state.error == "Shop URL not configured")
    }

    @Test("Sync with unreachable URL increments failure counter")
    func testUnreachableUrl() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)
        // Use a URL that will fail quickly (connection refused)
        let result = await engine.runSync(
            deviceId: "dev-001",
            shopUrl: "http://127.0.0.1:1",
            authToken: nil
        )
        #expect(result == false)
        let state = await engine.getState()
        #expect(state.status == .error)
        #expect(state.consecutiveFailures == 1)
    }

    @Test("Multiple failures increment counter")
    func testMultipleFailures() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)
        _ = await engine.runSync(deviceId: "dev-001", shopUrl: "http://127.0.0.1:1")
        _ = await engine.runSync(deviceId: "dev-001", shopUrl: "http://127.0.0.1:1")
        let state = await engine.getState()
        #expect(state.consecutiveFailures == 2)
    }

    @Test("Manual sync resets failure counter")
    func testManualSyncResets() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)
        // First, cause a failure
        _ = await engine.runSync(deviceId: "dev-001", shopUrl: "http://127.0.0.1:1")
        let stateBefore = await engine.getState()
        #expect(stateBefore.consecutiveFailures == 1)

        // Manual sync resets counter (even if it fails)
        _ = await engine.manualSync(deviceId: "dev-001", shopUrl: "http://127.0.0.1:1")
        // Counter was reset to 0 before the sync attempt, then incremented to 1 by the failure
        let stateAfter = await engine.getState()
        #expect(stateAfter.consecutiveFailures == 1)
    }

    @Test("Backoff calculation follows exponential pattern")
    func testBackoffCalculation() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)

        // 0 failures → normal interval
        let delay0 = await engine.getBackoffDelay()
        #expect(delay0 == SyncEngine.syncInterval)

        // Cause failures and check backoff
        _ = await engine.runSync(deviceId: "dev-001", shopUrl: "http://127.0.0.1:1")
        let delay1 = await engine.getBackoffDelay()
        #expect(delay1 == SyncEngine.minBackoff) // 30s × 2^0 = 30s

        _ = await engine.runSync(deviceId: "dev-001", shopUrl: "http://127.0.0.1:1")
        let delay2 = await engine.getBackoffDelay()
        #expect(delay2 == SyncEngine.minBackoff * 2) // 30s × 2^1 = 60s

        _ = await engine.runSync(deviceId: "dev-001", shopUrl: "http://127.0.0.1:1")
        let delay3 = await engine.getBackoffDelay()
        #expect(delay3 == SyncEngine.minBackoff * 4) // 30s × 2^2 = 120s
    }

    @Test("Periodic sync lifecycle starts and stops")
    func testPeriodicLifecycle() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)

        await engine.startPeriodicSync(
            deviceId: "dev-001",
            shopUrl: "http://127.0.0.1:1"
        )
        // Should be running — calling start again is a no-op
        await engine.startPeriodicSync(
            deviceId: "dev-001",
            shopUrl: "http://127.0.0.1:1"
        )

        await engine.stopPeriodicSync()
        // State should still be accessible after stop
        let state = await engine.getState()
        #expect(state.status == .idle || state.status == .error || state.status == .syncing)
    }

    @Test("State change callback fires")
    func testStateChangeCallback() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)

        let expectation = Mutex(false)
        await engine.setOnStateChanged { _ in
            expectation.withLock { $0 = true }
        }

        _ = await engine.runSync(deviceId: "dev-001", shopUrl: "")
        // Give main actor a moment to dispatch
        try await Task.sleep(for: .milliseconds(100))
        let fired = expectation.withLock { $0 }
        #expect(fired == true)
    }

    @Test("Sync ack failure is retryable and does not mark changes synced")
    func testAckFailureDoesNotReportSynced() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)

        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: 1,
            operation: .insert,
            deviceId: "dev-001"
        )
        #expect(try ChangeTracker.getPendingChangeCount(db: db) == 1)

        let server = try HTTPStubServer { request in
            switch request.path {
            case "/api/sync/push":
                return HTTPStubResponse(
                    statusCode: 200,
                    body: #"{"data":{"sync_batch_id":"batch-ack-fails","shop_changes":[]}}"#
                )
            case "/api/sync/ack":
                return HTTPStubResponse(
                    statusCode: 500,
                    body: #"{"error":"ack failed"}"#
                )
            default:
                return HTTPStubResponse(statusCode: 404, body: #"{"error":"not found"}"#)
            }
        }
        let port = try await server.start()
        defer { server.stop() }

        let result = await engine.runSync(
            deviceId: "dev-001",
            shopUrl: "http://127.0.0.1:\(port)",
            authToken: nil
        )

        #expect(result == false)
        #expect(try ChangeTracker.getPendingChangeCount(db: db) == 1)

        let state = await engine.getState()
        #expect(state.status == .error)
        #expect(state.pendingCount == 1)
        #expect(state.error == "Ack failed: 500")
        #expect(state.consecutiveFailures == 1)
    }

    @Test("Shop apply errors do not acknowledge or report a clean sync")
    func testShopApplyErrorDoesNotAckOrReportSynced() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db) { _, _, _ in
            MergeResult(errors: 1)
        }
        let ackCallCount = Mutex(0)

        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: 1,
            operation: .insert,
            deviceId: "dev-001"
        )

        let server = try HTTPStubServer { request in
            switch request.path {
            case "/api/sync/push":
                // The injected resolver above models a retryable apply failure;
                // keep a valid shop change here so the receive path invokes it.
                return HTTPStubResponse(
                    statusCode: 200,
                    body: #"{"data":{"sync_batch_id":"batch-apply-fails","shop_changes":[{"device_id":"shop","table_name":"users","record_id":"42","operation":"INSERT","record_data":{"id":"42","display_name":"Remote","pin_hash":"hash","is_active":"1"},"timestamp":"2026-09-06T18:00:00Z"}]}}"#
                )
            case "/api/sync/ack":
                ackCallCount.withLock { $0 += 1 }
                return HTTPStubResponse(statusCode: 200, body: #"{"ok":true}"#)
            default:
                return HTTPStubResponse(statusCode: 404, body: #"{"error":"not found"}"#)
            }
        }
        let port = try await server.start()
        defer { server.stop() }

        let result = await engine.runSync(
            deviceId: "dev-001",
            shopUrl: "http://127.0.0.1:\(port)",
            authToken: nil
        )

        #expect(result == false)
        #expect(ackCallCount.withLock { $0 } == 0)
        #expect(try ChangeTracker.getPendingChangeCount(db: db) == 1)

        let state = await engine.getState()
        #expect(state.status == .error)
        #expect(state.pendingCount == 1)
        #expect(state.error == "Shop changes failed to apply: 1 transient error(s)")
        #expect(state.consecutiveFailures == 1)
    }

    @Test("Deterministic shop refusal is acknowledged without a retry loop")
    func testDeterministicShopRefusalStillAcknowledges() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)
        let ackCallCount = Mutex(0)

        let server = try HTTPStubServer { request in
            switch request.path {
            case "/api/sync/push":
                // An unknown operation is a deterministic refusal (`skipped`),
                // not a retryable apply error.
                return HTTPStubResponse(
                    statusCode: 200,
                    body: #"{"data":{"sync_batch_id":"batch-deterministic-refusal","shop_changes":[{"device_id":"shop","table_name":"users","record_id":"42","operation":"PURGE","timestamp":"2026-09-06T18:00:00Z"}]}}"#
                )
            case "/api/sync/ack":
                ackCallCount.withLock { $0 += 1 }
                return HTTPStubResponse(statusCode: 200, body: #"{"ok":true}"#)
            default:
                return HTTPStubResponse(statusCode: 404, body: #"{"error":"not found"}"#)
            }
        }
        let port = try await server.start()
        defer { server.stop() }

        let result = await engine.runSync(
            deviceId: "dev-001",
            shopUrl: "http://127.0.0.1:\(port)",
            authToken: nil
        )

        #expect(result == true)
        #expect(ackCallCount.withLock { $0 } == 1)

        let state = await engine.getState()
        #expect(state.status == .synced)
        #expect(state.consecutiveFailures == 0)
    }

    @Test("Malformed shop changes are retryable and do not acknowledge or mark local rows synced")
    func testMalformedShopChangeDoesNotAckOrMarkSynced() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)
        let ackCallCount = Mutex(0)

        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: 1,
            operation: .insert,
            deviceId: "dev-001"
        )

        let server = try HTTPStubServer { request in
            switch request.path {
            case "/api/sync/push":
                // The second entry is not structurally parseable because it has no table name.
                return HTTPStubResponse(
                    statusCode: 200,
                    body: #"{"data":{"sync_batch_id":"batch-malformed-change","shop_changes":[{"device_id":"shop","table_name":"users","record_id":"42","operation":"INSERT","record_data":{"id":"42","display_name":"Remote","pin_hash":"hash","is_active":"1"},"timestamp":"2026-09-06T18:00:00Z"},{"device_id":"shop","record_id":"43","operation":"INSERT","timestamp":"2026-09-06T18:00:00Z"}]}}"#
                )
            case "/api/sync/ack":
                ackCallCount.withLock { $0 += 1 }
                return HTTPStubResponse(statusCode: 200, body: #"{"ok":true}"#)
            default:
                return HTTPStubResponse(statusCode: 404, body: #"{"error":"not found"}"#)
            }
        }
        let port = try await server.start()
        defer { server.stop() }

        let result = await engine.runSync(
            deviceId: "dev-001",
            shopUrl: "http://127.0.0.1:\(port)",
            authToken: nil
        )

        #expect(result == false)
        #expect(ackCallCount.withLock { $0 } == 0)
        #expect(try ChangeTracker.getPendingChangeCount(db: db) == 1)

        let state = await engine.getState()
        #expect(state.status == .error)
        #expect(state.pendingCount == 1)
        #expect(state.error == "Invalid push response: malformed shop_changes")
        #expect(state.consecutiveFailures == 1)
    }

    @Test("Transient shop apply failure retries the original batch and acknowledges once after success")
    func testTransientApplyFailureRetriesOriginalBatch() async throws {
        let db = try freshDB()
        let resolverCallCount = Mutex(0)
        let engine = SyncEngine(db: db) { _, _, _ in
            resolverCallCount.withLock { count in
                count += 1
                return MergeResult(errors: count == 1 ? 1 : 0)
            }
        }
        let pushCallCount = Mutex(0)
        let ackCallCount = Mutex(0)

        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: 1,
            operation: .insert,
            deviceId: "dev-001"
        )

        let server = try HTTPStubServer { request in
            switch request.path {
            case "/api/sync/push":
                pushCallCount.withLock { $0 += 1 }
                return HTTPStubResponse(
                    statusCode: 200,
                    body: #"{"data":{"sync_batch_id":"batch-retry","shop_changes":[{"device_id":"shop","table_name":"users","record_id":"42","operation":"INSERT","record_data":{"id":"42","display_name":"Remote","pin_hash":"hash","is_active":"1"},"timestamp":"2026-09-06T18:00:00Z"}]}}"#
                )
            case "/api/sync/ack":
                ackCallCount.withLock { $0 += 1 }
                return HTTPStubResponse(statusCode: 200, body: #"{"ok":true}"#)
            default:
                return HTTPStubResponse(statusCode: 404, body: #"{"error":"not found"}"#)
            }
        }
        let port = try await server.start()
        defer { server.stop() }
        let shopUrl = "http://127.0.0.1:\(port)"

        let firstResult = await engine.runSync(deviceId: "dev-001", shopUrl: shopUrl, authToken: nil)
        #expect(firstResult == false)
        #expect(ackCallCount.withLock { $0 } == 0)
        #expect(try ChangeTracker.getPendingChangeCount(db: db) == 1)

        let secondResult = await engine.runSync(deviceId: "dev-001", shopUrl: shopUrl, authToken: nil)
        #expect(secondResult == true)
        #expect(pushCallCount.withLock { $0 } == 2)
        #expect(resolverCallCount.withLock { $0 } >= 2)
        #expect(ackCallCount.withLock { $0 } == 1)
        let journalCount = try await db.writer.read { dbConn in
            try Int.fetchOne(
                dbConn,
                sql: "SELECT COUNT(*) FROM _sync_receive_journal WHERE source_peer_id = ?",
                arguments: ["shop:\(shopUrl)"]
            )
        }
        #expect(journalCount == 1, "a retry must replay the durable receipt rather than creating another copy")
        #expect(try ChangeTracker.getPendingChangeCount(db: db) == 0)
    }

    @Test("Shop foreign-key deferral remains journaled and unacknowledged")
    func testShopForeignKeyDeferralDoesNotAck() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db) { _, _, _ in
            MergeResult(foreignKeyDeferrals: 1)
        }
        let ackCallCount = Mutex(0)
        let server = try HTTPStubServer { request in
            switch request.path {
            case "/api/sync/push":
                return HTTPStubResponse(
                    statusCode: 200,
                    body: #"{"data":{"sync_batch_id":"batch-fk-deferred","shop_changes":[{"id":95,"device_id":"shop","table_name":"part_styles","record_id":"95","operation":"INSERT","record_data":{"id":"95","category_id":"995","name":"Deferred"},"timestamp":"2026-09-06T00:00:00Z"}]}}"#
                )
            case "/api/sync/ack":
                ackCallCount.withLock { $0 += 1 }
                return HTTPStubResponse(statusCode: 200, body: #"{"ok":true}"#)
            default:
                return HTTPStubResponse(statusCode: 404, body: #"{"error":"not found"}"#)
            }
        }
        let port = try await server.start()
        defer { server.stop() }

        #expect(await engine.runSync(deviceId: "dev-001", shopUrl: "http://127.0.0.1:\(port)") == false)
        #expect(ackCallCount.withLock { $0 } == 0)
        let receipt = try await db.writer.read { dbConn in
            try Row.fetchOne(
                dbConn,
                sql: "SELECT state, audit_metadata FROM _sync_receive_journal WHERE source_sequence = 95"
            )
        }
        #expect(receipt?["state"] as String? == "deferred")
        #expect(receipt?["audit_metadata"] as String? == "shop_pull")
    }

    @Test("Sync rejects push responses without a batch ID before acking")
    func testMissingBatchIdDoesNotAckOrReportSynced() async throws {
        let db = try freshDB()
        let engine = SyncEngine(db: db)
        let ackCallCount = Mutex(0)

        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: 1,
            operation: .insert,
            deviceId: "dev-001"
        )

        let server = try HTTPStubServer { request in
            switch request.path {
            case "/api/sync/push":
                return HTTPStubResponse(
                    statusCode: 200,
                    body: #"{"data":{"shop_changes":[]}}"#
                )
            case "/api/sync/ack":
                ackCallCount.withLock { $0 += 1 }
                return HTTPStubResponse(statusCode: 200, body: #"{"ok":true}"#)
            default:
                return HTTPStubResponse(statusCode: 404, body: #"{"error":"not found"}"#)
            }
        }
        let port = try await server.start()
        defer { server.stop() }

        let result = await engine.runSync(
            deviceId: "dev-001",
            shopUrl: "http://127.0.0.1:\(port)",
            authToken: nil
        )

        #expect(result == false)
        #expect(ackCallCount.withLock { $0 } == 0)
        #expect(try ChangeTracker.getPendingChangeCount(db: db) == 1)

        let state = await engine.getState()
        #expect(state.status == .error)
        #expect(state.error == "Invalid push response: missing sync_batch_id")
        #expect(state.consecutiveFailures == 1)
    }
}

// Simple thread-safe wrapper for test assertions
private final class Mutex<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ value: T) { self.value = value }
    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

// Extension to allow setting callback from outside actor
extension SyncEngine {
    func setOnStateChanged(_ callback: @escaping @Sendable (SyncState) -> Void) {
        self.onStateChanged = callback
    }
}
