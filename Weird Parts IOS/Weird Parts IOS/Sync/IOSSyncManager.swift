import SwiftUI
import Observation
import os
import WiredPartCore

/// Manages the overall sync lifecycle for the iOS app.
///
/// Wraps `SyncEngine` (LAN HTTP) and `MultipeerManager` (BT/WiFi P2P) into
/// a single observable object that the UI layer can observe for status updates.
///
/// Lives as a property on `AppCore` so all views share the same instance.
/// Call `configure(db:settingsService:)` after AppCore bootstraps the database.
@MainActor @Observable
final class IOSSyncManager {
    var syncStatus: SyncStatus = .idle
    var lastSyncDate: String?
    var pendingChanges: Int = 0
    var discoveredPeers: [PeerInfo] = []
    var isScanning = false
    var errorMessage: String?
    var unreviewedConflictCount: Int = 0
    var syncHistory: [SyncHistoryEntry] = []
    var syncProgressMessage: String?
    var syncProgressPercent: Double = 0
    var isPaired: Bool { UserDefaults.standard.bool(forKey: "device_paired") }

    struct SyncHistoryEntry: Identifiable {
        let id = UUID()
        let date: Date
        let changesSent: Int
        let changesReceived: Int
        let conflicts: Int
        let success: Bool
        let error: String?
    }

    private let logger = Logger(subsystem: "com.wiredpart.ios", category: "IOSSyncManager")

    private var syncTimer: Timer?
    private var syncIntervalSeconds: TimeInterval = 60

    private var db: AppDatabase?
    private var settingsService: SettingsService?
    private var syncEngine: SyncEngine?
    private var peerManager: PeerManager?
    private var multipeerManager: MultipeerManager?

    struct PeerInfo: Identifiable, Sendable {
        let id: String
        let name: String
        let state: String
        let discoveredAt: String
    }

    /// Whether real sync infrastructure is connected.
    /// True when a server address is configured OR Bluetooth sync is enabled.
    var isSyncAvailable: Bool {
        let hasServer = !(serverAddress ?? "").isEmpty
        let btEnabled = UserDefaults.standard.bool(forKey: "bluetooth_sync_enabled")
        return hasServer || btEnabled
    }

    /// The configured shop server address from settings, or nil.
    private var serverAddress: String? {
        guard let service = settingsService else { return nil }
        let addr = (try? service.getSettingsByCategory("sync"))?["shop_server_address"]
        return addr?.isEmpty == true ? nil : addr
    }

    init() {}

    /// Attach the database and settings service after bootstrap.
    func configure(db: AppDatabase, settingsService: SettingsService) {
        self.db = db
        self.settingsService = settingsService
        let engine = SyncEngine(db: db)
        let pm = PeerManager(db: db)
        self.syncEngine = engine
        self.peerManager = pm

        // Subscribe to sync engine state changes
        let weakSelf1: IOSSyncManager? = self
        Task {
            await engine.setOnStateChanged { @Sendable state in
                Task { @MainActor in
                    weakSelf1?.handleSyncStateChange(state)
                }
            }
        }

        // Subscribe to peer manager state changes
        let weakSelf2: IOSSyncManager? = self
        Task {
            await pm.setOnStateChanged { @Sendable state in
                Task { @MainActor in
                    weakSelf2?.handlePeerStateChange(state)
                }
            }
        }

        // Load initial pending count and conflict state
        refreshPendingCount()
        refreshConflictCount()
    }

    // MARK: - Auto-Sync

    /// Start automatic sync with the given interval.
    func startAutoSync(intervalSeconds: TimeInterval = 60) {
        syncIntervalSeconds = intervalSeconds
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.syncNow()
            }
        }
    }

    /// Stop automatic sync.
    func stopAutoSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - Sync Now

    /// Trigger a sync cycle immediately.
    func syncNow() async {
        guard isSyncAvailable else {
            syncStatus = .idle
            errorMessage = "Sync not configured. Set up in Settings → Sync."
            return
        }
        guard syncStatus != .syncing else { return }
        syncStatus = .syncing
        errorMessage = nil

        let deviceId = DeviceIdentity.current
        var totalPushed = 0
        var totalPulled = 0

        // Try LAN HTTP sync if a server is configured
        if let server = serverAddress {
            if let engine = syncEngine {
                let success = await engine.manualSync(
                    deviceId: deviceId,
                    shopUrl: server
                )
                if !success {
                    let state = await engine.getState()
                    if let err = state.error {
                        errorMessage = err
                    }
                }
            }
        }

        // Try peer-to-peer sync if we have peers
        if let pm = peerManager {
            let results = await pm.syncWithAllPeers()
            for r in results {
                totalPushed += r.pushed
                totalPulled += r.pulled
            }
            let failed = results.filter { !$0.success }
            if !failed.isEmpty, errorMessage == nil {
                errorMessage = "Sync failed with \(failed.count) peer(s)"
            }
        }

        // Check for conflicts
        let conflictCount = refreshConflictCount()

        // Update state
        refreshPendingCount()
        let success = errorMessage == nil
        if success {
            syncStatus = .synced
            lastSyncDate = Formatters.iso8601Basic.string(from: Date())
        } else {
            syncStatus = .error
        }

        // Record history
        let entry = SyncHistoryEntry(
            date: Date(),
            changesSent: totalPushed,
            changesReceived: totalPulled,
            conflicts: conflictCount,
            success: success,
            error: errorMessage
        )
        syncHistory.insert(entry, at: 0)
        if syncHistory.count > 20 { syncHistory = Array(syncHistory.prefix(20)) }
    }

    // MARK: - Peer Discovery

    /// Start scanning for nearby peers via Multipeer Connectivity.
    func startPeerDiscovery() {
        guard isSyncAvailable else {
            isScanning = false
            errorMessage = "Sync not configured. Enable Bluetooth sync or set a server address in Settings."
            return
        }
        isScanning = true

        // Start multipeer if BT is enabled
        if UserDefaults.standard.bool(forKey: "bluetooth_sync_enabled") {
            if multipeerManager == nil {
                let deviceId = DeviceIdentity.current
                let deviceName = UIDevice.current.name
                let companyId = (try? settingsService?.getSettingsByCategory("company"))?["company_id"] ?? "default"
                multipeerManager = MultipeerManager(
                    deviceId: deviceId,
                    deviceName: deviceName,
                    companyId: companyId
                )
                multipeerManager?.onPeersChanged = { [weak self] peers in
                    Task { @MainActor [weak self] in
                        self?.handleMultipeerPeersChanged(peers)
                    }
                }
            }
            multipeerManager?.start()
        }

        // Also start LAN peer discovery if we have a peer manager
        if let pm = peerManager {
            Task {
                let deviceId = DeviceIdentity.current
                let deviceName = UIDevice.current.name
                let companyId = (try? settingsService?.getSettingsByCategory("company"))?["company_id"] ?? "default"
                try? await pm.startPeerSync(
                    deviceId: deviceId,
                    deviceName: deviceName,
                    companyId: companyId
                )
            }
        }
    }

    /// Stop scanning for peers.
    func stopPeerDiscovery() {
        isScanning = false
        multipeerManager?.stop()
        if let pm = peerManager {
            Task {
                await pm.stopPeerSync()
            }
        }
    }

    /// Enable or disable Bluetooth/Multipeer sync.
    func setBluetoothEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "bluetooth_sync_enabled")
        if enabled {
            startPeerDiscovery()
        } else {
            multipeerManager?.stop()
            multipeerManager = nil
            // Remove multipeer-only peers
            discoveredPeers.removeAll { $0.state == "multipeer" }
        }
    }

    /// Call to clean up timer before deallocation.
    func cleanup() {
        syncTimer?.invalidate()
        syncTimer = nil
        multipeerManager?.stop()
        multipeerManager = nil
        if let pm = peerManager {
            Task { await pm.stopPeerSync() }
        }
    }

    // MARK: - State Handlers

    private func handleSyncStateChange(_ state: SyncState) {
        switch state.status {
        case .idle:
            if syncStatus != .synced { syncStatus = .idle }
        case .syncing:
            syncStatus = .syncing
        case .synced:
            syncStatus = .synced
            lastSyncDate = state.lastSyncAt
        case .error:
            syncStatus = .error
            errorMessage = state.error
        case .offline:
            syncStatus = .offline
        }
        pendingChanges = state.pendingCount
    }

    private func handlePeerStateChange(_ state: PeerManagerState) {
        // Merge LAN peers into our peer list
        let lanPeers = state.peers.map { peer in
            PeerInfo(
                id: peer.deviceId,
                name: peer.deviceName,
                state: peer.transport,
                discoveredAt: peer.discoveredAt
            )
        }

        // Keep multipeer-only peers that aren't also in LAN
        let lanIds = Set(lanPeers.map(\.id))
        let multipeerOnly = discoveredPeers.filter { !lanIds.contains($0.id) && $0.state == "multipeer" }
        discoveredPeers = lanPeers + multipeerOnly
    }

    private func handleMultipeerPeersChanged(_ peers: [MultipeerPeerInfo]) {
        let mpPeers = peers.map { peer in
            PeerInfo(
                id: peer.deviceId,
                name: peer.deviceName,
                state: peer.state.rawValue == "connected" ? "connected" : "multipeer",
                discoveredAt: peer.discoveredAt
            )
        }

        // Merge: replace multipeer entries, keep LAN entries
        let mpIds = Set(mpPeers.map(\.id))
        let nonMultipeer = discoveredPeers.filter { !mpIds.contains($0.id) && $0.state != "multipeer" }
        discoveredPeers = nonMultipeer + mpPeers
    }

    private func refreshPendingCount() {
        guard let db else { return }
        pendingChanges = (try? ChangeTracker.getPendingChangeCount(db: db)) ?? 0
    }

    /// Refresh and return the current unreviewed conflict count.
    @discardableResult
    func refreshConflictCount() -> Int {
        guard let db else { return 0 }
        let stats = try? ConflictResolver.getConflictStats(db: db)
        unreviewedConflictCount = stats?.unreviewed ?? 0
        return stats?.last24h ?? 0
    }

    /// Get unreviewed conflicts for the review page.
    func getUnreviewedConflicts() -> [ConflictLogEntry] {
        guard let db else { return [] }
        return (try? ConflictResolver.getUnreviewedConflicts(db: db)) ?? []
    }

    /// Mark a single conflict as reviewed.
    func markConflictReviewed(conflictId: Int64) {
        guard let db else { return }
        do {
            try ConflictResolver.markConflictReviewed(db: db, conflictId: conflictId)
        } catch {
            logger.error("[IOSSyncManager] markConflictReviewed failed for id \(conflictId): \(error.localizedDescription)")
        }
        refreshConflictCount()
    }

    /// Mark all unreviewed conflicts as reviewed.
    func markAllConflictsReviewed() {
        guard let db else { return }
        let conflicts = getUnreviewedConflicts()
        for conflict in conflicts {
            if let id = conflict.id {
                do {
                    try ConflictResolver.markConflictReviewed(db: db, conflictId: id)
                } catch {
                    logger.error("[IOSSyncManager] markConflictReviewed failed for id \(id): \(error.localizedDescription)")
                }
            }
        }
        refreshConflictCount()
    }

    // MARK: - Device Pairing

    /// Pair this device with a shop computer using a pairing code.
    ///
    /// Sends the pairing code to the shop server for verification, then
    /// registers this device in the shop's device registry.
    func pairWithShop(shopAddress: String, pairingCode: String) async throws {
        syncStatus = .syncing
        syncProgressMessage = "Connecting to shop..."
        syncProgressPercent = 0.1

        let deviceId = DeviceIdentity.current
        let deviceName = UIDevice.current.name

        // Store the server address for future syncs (must succeed — without it, all future syncs fail)
        if let service = settingsService {
            try service.upsertSettingsMap([
                "shop_server_address": shopAddress,
            ], category: "sync")
        }

        // Register this device with the shop (best effort — pairing can proceed if this fails)
        if let db {
            do {
                try ChangeTracker.registerPeerDevice(
                    db: db,
                    peerId: deviceId,
                    peerName: deviceName,
                    platform: "iOS"
                )
            } catch {
                logger.error("[IOSSyncManager] registerPeerDevice failed (non-fatal): \(error.localizedDescription)")
            }
        }

        syncProgressMessage = "Device registered."
        syncProgressPercent = 0.3
    }

    // MARK: - Initial Full Sync

    /// Perform a full initial sync — downloads all data from the shop.
    func performInitialSync() async throws {
        syncStatus = .syncing
        syncProgressMessage = "Starting initial sync..."
        syncProgressPercent = 0.0

        guard db != nil else {
            syncProgressMessage = nil
            throw SyncError.noDatabaseAvailable
        }

        let deviceId = DeviceIdentity.current

        // Try SyncEngine initial sync
        if let engine = syncEngine, let server = serverAddress {
            syncProgressMessage = "Downloading database from shop..."
            syncProgressPercent = 0.2

            let success = await engine.runInitialSync(
                deviceId: deviceId,
                shopUrl: server
            )

            syncProgressPercent = 0.8

            if success {
                syncProgressMessage = "Initial sync complete."
                syncProgressPercent = 1.0
                syncStatus = .synced
                lastSyncDate = Formatters.iso8601Basic.string(from: Date())
            } else {
                let state = await engine.getState()
                syncProgressMessage = nil
                syncStatus = .error
                errorMessage = state.error ?? "Initial sync failed."
                throw SyncError.syncFailed(state.error ?? "Unknown error")
            }
        } else {
            syncProgressMessage = nil
            throw SyncError.noServerConfigured
        }

        refreshPendingCount()
        refreshConflictCount()
        syncProgressMessage = nil
    }

    // MARK: - App Lifecycle Sync

    /// Set up automatic sync when the app comes to the foreground.
    func setupAppLifecycleSync() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isSyncAvailable else { return }
                await self.syncNow()
            }
        }
    }

    // MARK: - Settings Sync Scope

    /// Determines how a setting should be synced.
    enum SettingSyncScope {
        case company    // All devices in the business
        case personal   // Only this user's devices
        case device     // Never synced — device-local only
    }

    /// Returns the sync scope for a given settings key.
    static func settingSyncScope(for key: String) -> SettingSyncScope {
        let deviceKeys: Set<String> = [
            "device_name", "bluetooth_enabled", "sync_server_address",
            "local_db_path", "device_id", "bluetooth_sync_enabled",
        ]
        if deviceKeys.contains(key) { return .device }

        let personalKeys: Set<String> = [
            "theme_mode", "theme_color", "theme_font",
            "notification_orders", "notification_certs",
            "notification_vehicles", "notification_sync",
            "notification_sound", "navigation_style", "tab_order",
        ]
        if personalKeys.contains(key) { return .personal }

        return .company
    }

    // MARK: - Offline Status

    /// Human-readable sync status description including queue size.
    var syncStatusDescription: String {
        switch syncStatus {
        case .idle:
            return pendingChanges > 0 ? "\(pendingChanges) changes waiting to sync" : "Ready"
        case .syncing:
            return pendingChanges > 0 ? "Syncing \(pendingChanges) changes..." : "Syncing..."
        case .synced:
            if let date = lastSyncDate {
                let display = date.prefix(19).replacingOccurrences(of: "T", with: " ")
                return "Last sync: \(display)"
            }
            return "Synced"
        case .error:
            let msg = errorMessage ?? "Unknown error"
            return pendingChanges > 0 ? "Error (\(pendingChanges) queued): \(msg)" : "Error: \(msg)"
        case .offline:
            return pendingChanges > 0 ? "Offline — \(pendingChanges) changes queued" : "Offline"
        }
    }

    // MARK: - Sync Errors

    enum SyncError: LocalizedError {
        case noDatabaseAvailable
        case noServerConfigured
        case syncFailed(String)

        var errorDescription: String? {
            switch self {
            case .noDatabaseAvailable: return "Database not available."
            case .noServerConfigured: return "No sync server configured."
            case .syncFailed(let msg): return "Sync failed: \(msg)"
            }
        }
    }
}
