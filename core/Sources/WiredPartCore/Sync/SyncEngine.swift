import Foundation
import Network

// MARK: - Sync State

/// Status of the sync engine.
public enum SyncStatus: String, Sendable {
    case idle
    case syncing
    case synced
    case error
    case offline
}

/// Snapshot of the sync engine's current state.
public struct SyncState: Sendable {
    public var status: SyncStatus
    public var lastSyncAt: String?
    public var pendingCount: Int
    public var error: String?
    public var consecutiveFailures: Int
    public var lastAttemptAt: String?

    public init(
        status: SyncStatus = .idle,
        lastSyncAt: String? = nil,
        pendingCount: Int = 0,
        error: String? = nil,
        consecutiveFailures: Int = 0,
        lastAttemptAt: String? = nil
    ) {
        self.status = status
        self.lastSyncAt = lastSyncAt
        self.pendingCount = pendingCount
        self.error = error
        self.consecutiveFailures = consecutiveFailures
        self.lastAttemptAt = lastAttemptAt
    }
}

// MARK: - Sync Engine

/// Device-side sync engine — pushes local changes to shop, pulls shop changes.
///
/// Ported from: `src/local/sync-engine.ts`
///
/// Protocol:
/// 1. Check if shop is reachable
/// 2. Push local `_change_log` entries to shop (POST /api/sync/push)
/// 3. Shop returns its changes + conflict resolutions
/// 4. Apply shop changes to local DB via ConflictResolver
/// 5. Mark local changes as synced
/// 6. Acknowledge (POST /api/sync/ack)
///
/// Retry: exponential backoff starting at 30s, max 5 minutes.
/// Resets on successful sync or manual trigger.
public actor SyncEngine {

    // MARK: - Configuration

    /// Normal sync interval (5 minutes).
    public static let syncInterval: TimeInterval = 300

    /// Initial backoff delay (30 seconds).
    public static let minBackoff: TimeInterval = 30

    /// Maximum backoff delay (5 minutes).
    public static let maxBackoff: TimeInterval = 300

    /// Stop auto-retry after this many consecutive failures.
    public static let maxConsecutiveFailures = 10

    // MARK: - State

    private let db: AppDatabase
    private let shopChangeResolver: @Sendable (AppDatabase, [IncomingChange], String) throws -> MergeResult
    private var state = SyncState()
    private var isSyncing = false
    private var periodicTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var networkMonitor: NWPathMonitor?
    private var isNetworkAvailable = true

    /// Called on the main actor when state changes.
    public var onStateChanged: (@Sendable (SyncState) -> Void)?

    /// Set the state-changed callback from outside the actor.
    public func setOnStateChanged(_ callback: (@Sendable (SyncState) -> Void)?) {
        onStateChanged = callback
    }

    public init(db: AppDatabase) {
        self.init(
            db: db,
            shopChangeResolver: { db, changes, localDeviceId in
                try ConflictResolver.resolveAndApplyChanges(
                    db: db,
                    changes: changes,
                    localDeviceId: localDeviceId
                )
            }
        )
    }

    /// Injectable only within the module so regression tests can exercise
    /// retry/ack control flow for an apply result that is otherwise produced by
    /// transient database faults (for example SQLITE_BUSY or disk-full).
    init(
        db: AppDatabase,
        shopChangeResolver: @escaping @Sendable (AppDatabase, [IncomingChange], String) throws -> MergeResult
    ) {
        self.db = db
        self.shopChangeResolver = shopChangeResolver
    }

    /// Get the current sync state.
    public func getState() -> SyncState {
        state
    }

    // MARK: - Core Sync

    /// Run a full sync cycle. Returns true on success.
    ///
    /// - Parameters:
    ///   - deviceId: This device's unique identifier.
    ///   - shopUrl: Base URL of the shop server (e.g., `http://192.168.1.10:8000`).
    ///   - authToken: Optional Bearer token for auth.
    public func runSync(
        deviceId: String,
        shopUrl: String,
        authToken: String? = nil
    ) async -> Bool {
        guard !isSyncing else { return false }
        isSyncing = true
        defer { isSyncing = false }

        updateState(status: .syncing, error: nil, lastAttemptAt: currentTimestamp())

        // Check network
        if !isNetworkAvailable {
            let count = (try? ChangeTracker.getPendingChangeCount(db: db)) ?? 0
            updateState(
                status: .offline,
                pendingCount: count,
                consecutiveFailures: state.consecutiveFailures + 1
            )
            scheduleRetry(deviceId: deviceId, shopUrl: shopUrl, authToken: authToken)
            return false
        }

        // Validate shop URL
        guard !shopUrl.isEmpty, let baseURL = URL(string: shopUrl) else {
            updateState(status: .error, error: "Shop URL not configured")
            return false
        }

        do {
            // 1. Get pending local changes
            let pendingChanges = try ChangeTracker.getPendingChanges(db: db)
            updateState(pendingCount: pendingChanges.count)

            // Build outgoing change list
            let outgoing: [[String: Any]] = pendingChanges.map { entry in
                var dict: [String: Any] = [
                    "device_id": entry.deviceId,
                    "table_name": entry.tableName,
                    "record_id": entry.recordId,
                    "operation": entry.operation,
                    "timestamp": entry.timestamp,
                ]
                if let cf = entry.changedFields { dict["changed_fields"] = cf }
                if let ov = entry.oldValues { dict["old_values"] = ov }
                if let seq = entry.sequence { dict["id"] = seq }
                return dict
            }

            // 2. Push to shop
            let pushURL = baseURL.appendingPathComponent("api/sync/push")
            let pushBody: [String: Any] = [
                "device_id": deviceId,
                "last_sync_at": state.lastSyncAt ?? "1970-01-01",
                "changes": outgoing,
            ]

            let (pushData, pushResponse) = try await httpPost(
                url: pushURL,
                body: pushBody,
                authToken: authToken,
                timeout: 30
            )

            guard let httpResp = pushResponse as? HTTPURLResponse,
                  httpResp.statusCode == 200 else {
                let statusCode = (pushResponse as? HTTPURLResponse)?.statusCode ?? 0
                updateState(
                    status: .error,
                    error: "Push failed: \(statusCode)",
                    consecutiveFailures: state.consecutiveFailures + 1
                )
                scheduleRetry(deviceId: deviceId, shopUrl: shopUrl, authToken: authToken)
                return false
            }

            // Parse push response
            guard let pushResult = try? JSONSerialization.jsonObject(with: pushData) as? [String: Any],
                  let resultData = pushResult["data"] as? [String: Any] else {
                updateState(
                    status: .error,
                    error: "Invalid push response",
                    consecutiveFailures: state.consecutiveFailures + 1
                )
                scheduleRetry(deviceId: deviceId, shopUrl: shopUrl, authToken: authToken)
                return false
            }

            guard let syncBatchId = resultData["sync_batch_id"] as? String,
                  !syncBatchId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                updateState(
                    status: .error,
                    error: "Invalid push response: missing sync_batch_id",
                    consecutiveFailures: state.consecutiveFailures + 1
                )
                scheduleRetry(deviceId: deviceId, shopUrl: shopUrl, authToken: authToken)
                return false
            }

            // 3. Apply shop changes to local DB. `compactMap` would silently drop a
            // malformed item and then incorrectly advance the shop batch, so every
            // advertised item must parse before the acknowledgement path can start.
            if let rawShopChanges = resultData["shop_changes"] {
                guard let shopChangesRaw = rawShopChanges as? [[String: Any]] else {
                    let pendingCount = (try? ChangeTracker.getPendingChangeCount(db: db)) ?? pendingChanges.count
                    updateState(
                        status: .error,
                        pendingCount: pendingCount,
                        error: "Invalid push response: malformed shop_changes",
                        consecutiveFailures: state.consecutiveFailures + 1
                    )
                    scheduleRetry(deviceId: deviceId, shopUrl: shopUrl, authToken: authToken)
                    return false
                }

                let parsedIncomingChanges = shopChangesRaw.map(parseIncomingChange)
                guard parsedIncomingChanges.allSatisfy({ $0 != nil }) else {
                    let pendingCount = (try? ChangeTracker.getPendingChangeCount(db: db)) ?? pendingChanges.count
                    updateState(
                        status: .error,
                        pendingCount: pendingCount,
                        error: "Invalid push response: malformed shop_changes",
                        consecutiveFailures: state.consecutiveFailures + 1
                    )
                    scheduleRetry(deviceId: deviceId, shopUrl: shopUrl, authToken: authToken)
                    return false
                }

                let incomingChanges = parsedIncomingChanges.compactMap { $0 }
                if !incomingChanges.isEmpty {
                    // A shop ACK irrevocably closes this delivery. Persist each row
                    // before attempting it so an FK child remains replayable after ACK.
                    let receiptSource = "shop:\(baseURL.absoluteString)"
                    try SyncReceiveJournal.record(
                        db: db,
                        sourcePeerId: receiptSource,
                        changes: incomingChanges,
                        auditMetadata: "shop_pull"
                    )
                    let replay = try SyncReceiveJournal.applyPending(
                        db: db,
                        localDeviceId: deviceId,
                        sourcePeerId: receiptSource
                    )
                    guard replay.retryable == 0 else {
                        let pendingCount = (try? ChangeTracker.getPendingChangeCount(db: db)) ?? pendingChanges.count
                        updateState(
                            status: .error,
                            pendingCount: pendingCount,
                            error: "Shop changes failed to apply: \(replay.retryable) transient error(s)",
                            consecutiveFailures: state.consecutiveFailures + 1
                        )
                        scheduleRetry(deviceId: deviceId, shopUrl: shopUrl, authToken: authToken)
                        return false
                    }
                }
            }

            // 4. Acknowledge the batch before declaring local rows fully synced.
            // The shop/server side may use this ack to close out delivery state, so an
            // ack failure must remain retryable instead of reporting a clean sync.
            let ackURL = baseURL.appendingPathComponent("api/sync/ack")
            let ackBody: [String: Any] = [
                "device_id": deviceId,
                "sync_batch_id": syncBatchId,
            ]
            let ackDataAndResponse: (Data, URLResponse)
            do {
                ackDataAndResponse = try await httpPost(url: ackURL, body: ackBody, authToken: authToken, timeout: 10)
            } catch {
                let pendingCount = (try? ChangeTracker.getPendingChangeCount(db: db)) ?? pendingChanges.count
                updateState(
                    status: .error,
                    pendingCount: pendingCount,
                    error: "Ack request failed: \(error.localizedDescription)",
                    consecutiveFailures: state.consecutiveFailures + 1
                )
                scheduleRetry(deviceId: deviceId, shopUrl: shopUrl, authToken: authToken)
                return false
            }
            let (_, ackResponse) = ackDataAndResponse
            guard let ackHTTPResponse = ackResponse as? HTTPURLResponse else {
                let pendingCount = (try? ChangeTracker.getPendingChangeCount(db: db)) ?? pendingChanges.count
                updateState(
                    status: .error,
                    pendingCount: pendingCount,
                    error: "Ack failed: non-HTTP response",
                    consecutiveFailures: state.consecutiveFailures + 1
                )
                scheduleRetry(deviceId: deviceId, shopUrl: shopUrl, authToken: authToken)
                return false
            }
            guard (200..<300).contains(ackHTTPResponse.statusCode) else {
                let statusCode = ackHTTPResponse.statusCode
                let pendingCount = (try? ChangeTracker.getPendingChangeCount(db: db)) ?? pendingChanges.count
                updateState(
                    status: .error,
                    pendingCount: pendingCount,
                    error: "Ack failed: \(statusCode)",
                    consecutiveFailures: state.consecutiveFailures + 1
                )
                scheduleRetry(deviceId: deviceId, shopUrl: shopUrl, authToken: authToken)
                return false
            }

            // 5. Mark local changes as synced only after push and ack both succeed.
            if !pendingChanges.isEmpty {
                let syncedIds = pendingChanges.compactMap { $0.id }
                try ChangeTracker.markSynced(db: db, ids: syncedIds, batchId: syncBatchId)
            }

            // Success
            let now = currentTimestamp()
            // Re-read the real backlog instead of hardcoding 0: getPendingChanges is
            // capped at LIMIT 500, so a push of >500 rows leaves a non-empty backlog
            // that a hardcoded 0 would hide (#1794). Matches every error path above,
            // which already reports getPendingChangeCount rather than an assumed count.
            let remainingPending = (try? ChangeTracker.getPendingChangeCount(db: db)) ?? 0
            updateState(
                status: .synced,
                lastSyncAt: now,
                pendingCount: remainingPending,
                error: nil,
                consecutiveFailures: 0
            )

            return true

        } catch {
            updateState(
                status: .error,
                error: error.localizedDescription,
                consecutiveFailures: state.consecutiveFailures + 1
            )
            scheduleRetry(deviceId: deviceId, shopUrl: shopUrl, authToken: authToken)
            return false
        }
    }

    // MARK: - Initial Sync

    /// Pull all data from the shop to populate an empty local DB.
    public func runInitialSync(
        deviceId: String,
        shopUrl: String,
        authToken: String? = nil
    ) async -> Bool {
        guard !isSyncing else { return false }
        isSyncing = true
        defer { isSyncing = false }

        updateState(status: .syncing, error: nil)

        guard !shopUrl.isEmpty, let baseURL = URL(string: shopUrl) else {
            updateState(status: .error, error: "Shop URL not configured")
            return false
        }

        do {
            let url = baseURL.appendingPathComponent("api/sync/initial")
            let body: [String: Any] = ["device_id": deviceId]

            let (data, response) = try await httpPost(
                url: url,
                body: body,
                authToken: authToken,
                timeout: 120
            )

            guard let httpResp = response as? HTTPURLResponse,
                  httpResp.statusCode == 200 else {
                updateState(status: .error, error: "Initial sync failed")
                return false
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let resultData = json["data"] as? [String: Any],
                  let tables = resultData["tables"] as? [String: [[String: Any]]] else {
                updateState(status: .error, error: "Invalid initial sync response")
                return false
            }

            // Pre-compute SQL statements and arguments (Sendable)
            var stmts: [(String, [DatabaseValue])] = []
            for (tableName, rows) in tables {
                // Validate table name against whitelist to prevent SQL injection
                guard ConflictResolver.isAllowedTable(tableName) else { continue }

                for row in rows {
                    let keys = row.keys.sorted()
                    guard !keys.isEmpty else { continue }
                    let placeholders = keys.map { _ in "?" }.joined(separator: ", ")
                    let columns = keys.joined(separator: ", ")
                    let values = keys.map { DatabaseValue.from(row[$0] ?? NSNull()) }
                    let sql = "INSERT OR REPLACE INTO [\(tableName)] (\(columns)) VALUES (\(placeholders))"
                    stmts.append((sql, values))
                }
            }
            let sqlStatements = stmts

            // Execute all statements in a single write transaction, UNDER the
            // _sync_apply_guard so the migration-112 change-tracking triggers do not
            // fire (#1796). Without the guard, every INSERT OR REPLACE of a just-
            // downloaded row logs a synced=0 _change_log entry, and the very next
            // runSync uploads the entire freshly-downloaded dataset back to the shop
            // (and inflates the pending badge by the whole database). Same mechanism
            // ConflictResolver uses to apply remote changes without re-broadcasting them.
            try await db.writer.write { dbConn in
                try dbConn.execute(sql: "INSERT OR IGNORE INTO _sync_apply_guard (id) VALUES (1)")
                defer { try? dbConn.execute(sql: "DELETE FROM _sync_apply_guard") }
                for (sql, values) in sqlStatements {
                    try dbConn.execute(sql: sql, arguments: StatementArguments(values))
                }
            }

            let now = currentTimestamp()
            updateState(
                status: .synced,
                lastSyncAt: now,
                pendingCount: 0,
                error: nil,
                consecutiveFailures: 0
            )

            return true

        } catch {
            updateState(status: .error, error: error.localizedDescription)
            return false
        }
    }

    // MARK: - Periodic Sync

    /// Start a periodic sync that runs every `syncInterval` seconds.
    public func startPeriodicSync(
        deviceId: String,
        shopUrl: String,
        authToken: String? = nil
    ) {
        guard periodicTask == nil else { return }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.syncInterval))
                guard !Task.isCancelled else { break }
                guard let self else { break }
                // Only run if not already retrying and no recent failures
                let failures = await self.state.consecutiveFailures
                if failures == 0 {
                    _ = await self.runSync(
                        deviceId: deviceId,
                        shopUrl: shopUrl,
                        authToken: authToken
                    )
                }
            }
        }
    }

    /// Stop periodic sync and cancel pending retries.
    public func stopPeriodicSync() {
        periodicTask?.cancel()
        periodicTask = nil
        retryTask?.cancel()
        retryTask = nil
    }

    // MARK: - Manual Sync

    /// Trigger a manual sync — resets consecutive failure count.
    public func manualSync(
        deviceId: String,
        shopUrl: String,
        authToken: String? = nil
    ) async -> Bool {
        retryTask?.cancel()
        retryTask = nil
        state.consecutiveFailures = 0
        notifyStateChanged()
        return await runSync(deviceId: deviceId, shopUrl: shopUrl, authToken: authToken)
    }

    // MARK: - Network Monitoring

    /// Start monitoring network connectivity. Syncs when coming back online.
    public func startNetworkMonitoring(
        deviceId: String,
        shopUrl: String,
        authToken: String? = nil
    ) {
        guard networkMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task {
                let wasOffline = await !self.isNetworkAvailable
                let nowOnline = path.status == .satisfied
                await self.setNetworkAvailable(nowOnline)

                if wasOffline && nowOnline {
                    // Network came back — try syncing after a short delay
                    try? await Task.sleep(for: .seconds(2))
                    await self.resetAndSync(
                        deviceId: deviceId,
                        shopUrl: shopUrl,
                        authToken: authToken
                    )
                } else if !nowOnline {
                    await self.updateState(status: .offline)
                }
            }
        }
        let queue = DispatchQueue(label: "com.wiredpart.sync.network", qos: .utility)
        monitor.start(queue: queue)
        networkMonitor = monitor
    }

    /// Stop network monitoring.
    public func stopNetworkMonitoring() {
        networkMonitor?.cancel()
        networkMonitor = nil
    }

    // MARK: - Private Helpers

    private func setNetworkAvailable(_ available: Bool) {
        isNetworkAvailable = available
    }

    private func resetAndSync(
        deviceId: String,
        shopUrl: String,
        authToken: String?
    ) async {
        retryTask?.cancel()
        retryTask = nil
        state.consecutiveFailures = 0
        _ = await runSync(deviceId: deviceId, shopUrl: shopUrl, authToken: authToken)
    }

    private func scheduleRetry(
        deviceId: String,
        shopUrl: String,
        authToken: String?
    ) {
        retryTask?.cancel()
        if state.consecutiveFailures >= Self.maxConsecutiveFailures {
            updateState(error: "Too many failures. Tap to retry.")
            return
        }
        let delay = getBackoffDelay()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            _ = await self.runSync(
                deviceId: deviceId,
                shopUrl: shopUrl,
                authToken: authToken
            )
        }
    }

    /// Calculate backoff delay using exponential strategy.
    internal func getBackoffDelay() -> TimeInterval {
        if state.consecutiveFailures == 0 { return Self.syncInterval }
        let backoff = Self.minBackoff * pow(2.0, Double(state.consecutiveFailures - 1))
        return min(backoff, Self.maxBackoff)
    }

    private func updateState(
        status: SyncStatus? = nil,
        lastSyncAt: String?? = nil,
        pendingCount: Int? = nil,
        error: String?? = nil,
        consecutiveFailures: Int? = nil,
        lastAttemptAt: String?? = nil
    ) {
        if let s = status { state.status = s }
        if let ls = lastSyncAt { state.lastSyncAt = ls }
        if let pc = pendingCount { state.pendingCount = pc }
        if let e = error { state.error = e }
        if let cf = consecutiveFailures { state.consecutiveFailures = cf }
        if let la = lastAttemptAt { state.lastAttemptAt = la }
        notifyStateChanged()
    }

    private func notifyStateChanged() {
        let snapshot = state
        let callback = onStateChanged
        Task { @MainActor in
            callback?(snapshot)
        }
    }

    private func currentTimestamp() -> String { CoreFormatters.iso8601Fractional.string(from: Date()) }

    /// Parse a raw JSON dictionary into an IncomingChange.
    private func parseIncomingChange(_ dict: [String: Any]) -> IncomingChange? {
        guard let tableName = dict["table_name"] as? String,
              let operation = dict["operation"] as? String else {
            return nil
        }

        // Reject changes with invalid table names
        guard ConflictResolver.isAllowedTable(tableName) else {
            return nil
        }
        let recordId: String
        if let rid = dict["record_id"] as? String {
            recordId = rid
        } else if let rid = dict["record_id"] as? Int {
            recordId = String(rid)
        } else {
            return nil
        }

        return IncomingChange(
            id: dict["id"] as? Int64,
            deviceId: dict["device_id"] as? String ?? "",
            tableName: tableName,
            recordId: recordId,
            operation: operation,
            changedFields: dict["changed_fields"] as? String,
            oldValues: dict["old_values"] as? String,
            recordData: (dict["record_data"] as? [String: Any]).flatMap {
                String(data: (try? JSONSerialization.data(withJSONObject: $0)) ?? Data(), encoding: .utf8)
            },
            timestamp: dict["timestamp"] as? String ?? ""
        )
    }

    // MARK: - HTTP Helpers

    /// POST JSON to a URL with optional auth token and timeout.
    private func httpPost(
        url: URL,
        body: [String: Any],
        authToken: String?,
        timeout: TimeInterval
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await URLSession.shared.data(for: request)
    }
}

// MARK: - DatabaseValue Helper

import GRDB

extension DatabaseValue {
    /// Convert an Any value to a DatabaseValue for SQL binding.
    static func from(_ value: Any) -> DatabaseValue {
        switch value {
        case let s as String:
            return s.databaseValue
        case let i as Int:
            return i.databaseValue
        case let i64 as Int64:
            return i64.databaseValue
        case let d as Double:
            return d.databaseValue
        case let b as Bool:
            return b.databaseValue
        case is NSNull:
            return .null
        default:
            return String(describing: value).databaseValue
        }
    }
}
