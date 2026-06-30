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
    var isPaired: Bool {
        guard let map = try? settingsService?.getSettingsByCategory("sync") else {
            return false
        }
        return !(map["device_pairing_verified_at"] ?? "").isEmpty
            && !(map["paired_shop_device_id"] ?? "").isEmpty
    }

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

    nonisolated(unsafe) private var syncTimer: Timer?
    private var syncIntervalSeconds: TimeInterval = 60

    private var db: AppDatabase?
    private var settingsService: SettingsService?
    private var syncEngine: SyncEngine?
    private var peerManager: PeerManager?
    private var multipeerManager: MultipeerManager?
    private var multipeerDiscoveryMode: PeerDiscoveryMode?

    struct PeerInfo: Identifiable, Sendable {
        let id: String
        let name: String
        let state: String
        let discoveredAt: String
        let address: String?
    }

    enum PeerDiscoveryMode: Equatable {
        case existingCompanySync
        case onboardingJoin
    }

    /// Whether real sync infrastructure is connected.
    /// True when a server address is configured OR Bluetooth sync is enabled.
    var isSyncAvailable: Bool {
        let hasServer = !(serverAddress ?? "").isEmpty
        let btEnabled = UserDefaults.standard.bool(forKey: "bluetooth_sync_enabled")
        return hasServer || btEnabled
    }

    /// Whether automatic launch/foreground sync is enabled by settings.
    var isAutoSyncEnabled: Bool {
        (try? settingsService?.isAutoSyncEnabled()) ?? true
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
                await self?.handleAutoSyncTimerTick()
            }
        }
    }

    /// Handles one scheduled auto-sync tick.
    ///
    /// Re-check persisted auto-sync opt-in at execution time so a timer that was
    /// scheduled while enabled cannot keep syncing after another settings path
    /// stores `auto_sync = false`.
    func handleAutoSyncTimerTick() async {
        guard isSyncAvailable else { return }
        guard isAutoSyncEnabled else {
            stopAutoSync()
            return
        }
        await syncNow()
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

    /// Trigger a sync cycle for one selected peer from the Nearby Devices row.
    ///
    /// This intentionally bypasses the configured LAN server and `syncWithAllPeers()`
    /// global fan-out so a row-level Sync tap only touches the peer the user chose.
    func syncWithPeer(peerDeviceId: String) async {
        guard isSyncAvailable else {
            syncStatus = .idle
            errorMessage = "Sync not configured. Set up in Settings → Sync."
            return
        }
        guard syncStatus != .syncing else { return }
        guard let pm = peerManager else {
            syncStatus = .error
            errorMessage = SyncError.noDatabaseAvailable.localizedDescription
            return
        }

        syncStatus = .syncing
        errorMessage = nil

        let result = await pm.syncWithPeer(deviceId: peerDeviceId)
        if !result.success {
            let peerLabel: String
            if result.peerName == peerDeviceId {
                peerLabel = peerDeviceId
            } else {
                peerLabel = "\(result.peerName) (\(peerDeviceId))"
            }
            let failureReason = result.error ?? "Sync failed"
            errorMessage = "\(failureReason) for \(peerLabel)"
        }

        let conflictCount = refreshConflictCount()
        refreshPendingCount()
        let success = errorMessage == nil
        if success {
            syncStatus = .synced
            lastSyncDate = Formatters.iso8601Basic.string(from: Date())
        } else {
            syncStatus = .error
        }

        let entry = SyncHistoryEntry(
            date: Date(),
            changesSent: result.pushed,
            changesReceived: result.pulled,
            conflicts: conflictCount,
            success: success,
            error: errorMessage
        )
        syncHistory.insert(entry, at: 0)
        if syncHistory.count > 20 { syncHistory = Array(syncHistory.prefix(20)) }
    }

    // MARK: - Peer Discovery

    /// Start scanning for nearby peers via Multipeer Connectivity.
    ///
    /// Existing sync discovery stays company-scoped and fails closed if the
    /// stored company ID is missing. First-run onboarding uses
    /// `startOnboardingPeerDiscovery()` so a brand-new device can find a shop
    /// computer before it has downloaded and persisted the company settings.
    func startPeerDiscovery() {
        startPeerDiscovery(mode: .existingCompanySync)
    }

    /// Start first-run join discovery before this device has a local company ID.
    func startOnboardingPeerDiscovery() {
        startPeerDiscovery(mode: .onboardingJoin)
    }

    private func startPeerDiscovery(mode: PeerDiscoveryMode) {
        guard isSyncAvailable else {
            isScanning = false
            errorMessage = "Sync not configured. Enable Bluetooth sync or set a server address in Settings."
            return
        }

        if mode == .existingCompanySync {
            multipeerManager?.stop()
            multipeerManager = nil
            multipeerDiscoveryMode = nil
            removeMultipeerDiscoveredPeers()
            if let pm = peerManager {
                Task { await pm.stopPeerSync() }
            }
        }

        let companyId: String
        switch mode {
        case .existingCompanySync:
            do {
                companyId = try peerDiscoveryCompanyId()
            } catch {
                handlePeerDiscoveryCompanyIdFailure(error)
                return
            }
        case .onboardingJoin:
            companyId = "onboarding-join-\(UUID().uuidString)"
        }

        isScanning = true
        errorMessage = nil
        if syncStatus == .error {
            syncStatus = .idle
        }

        // Start multipeer if BT is enabled
        let bluetoothDiscoveryEnabled = UserDefaults.standard.bool(forKey: "bluetooth_sync_enabled")
        if bluetoothDiscoveryEnabled && mode == .onboardingJoin {
            if multipeerDiscoveryMode != mode {
                multipeerManager?.stop()
                multipeerManager = nil
                removeMultipeerDiscoveredPeers()
            }
            if multipeerManager == nil {
                let deviceId = DeviceIdentity.current
                let deviceName = UIDevice.current.name
                multipeerManager = MultipeerManager(
                    deviceId: deviceId,
                    deviceName: deviceName,
                    companyId: companyId,
                    allowAnyCompanyPeerDiscovery: mode == .onboardingJoin,
                    autoInvitePeers: mode == .existingCompanySync,
                    advertiseSelf: mode == .existingCompanySync
                )
                multipeerDiscoveryMode = mode
                multipeerManager?.onPeersChanged = { [weak self] peers in
                    Task { @MainActor [weak self] in
                        self?.handleMultipeerPeersChanged(peers)
                    }
                }
            }
            multipeerManager?.start()
        }

        // Also start LAN peer discovery when available. Existing sync discovery
        // stays company-scoped. Join/onboarding discovery relaxes LAN browsing
        // so a fresh device can discover a shop HTTP address before the pairing
        // response verifies and persists the real company ID.
        if let pm = peerManager {
            Task {
                let deviceId = DeviceIdentity.current
                let deviceName = UIDevice.current.name
                do {
                    if await pm.getState().running {
                        await pm.stopPeerSync()
                    }
                    try await pm.startPeerSync(
                        deviceId: deviceId,
                        deviceName: deviceName,
                        companyId: companyId,
                        allowAnyCompanyPeerDiscovery: mode == .onboardingJoin,
                        startMultipeer: bluetoothDiscoveryEnabled && mode == .existingCompanySync,
                        startSyncServer: mode == .existingCompanySync
                    )
                } catch {
                    handleLanPeerDiscoveryStartupFailure(
                        error,
                        hasActiveMultipeerDiscovery: bluetoothDiscoveryEnabled && mode == .onboardingJoin
                    )
                }
            }
        }
    }

    func handleLanPeerDiscoveryStartupFailure(
        _ error: Error,
        hasActiveMultipeerDiscovery: Bool
    ) {
        logger.error("[IOSSyncManager] LAN peer discovery failed to start: \(error.localizedDescription)")
        syncStatus = .error
        errorMessage = "LAN peer discovery failed: \(error.localizedDescription)"
        if !hasActiveMultipeerDiscovery {
            isScanning = false
        }
    }

    /// Stop scanning for peers.
    func stopPeerDiscovery() {
        isScanning = false
        multipeerManager?.stop()
        multipeerManager = nil
        multipeerDiscoveryMode = nil
        if let pm = peerManager {
            Task {
                await pm.stopPeerSync()
            }
        }
    }

    private func peerDiscoveryCompanyId() throws -> String {
        guard let settingsService else {
            throw SyncError.noCompanyIdConfigured
        }
        return try Self.peerDiscoveryCompanyId {
            try settingsService.getSettingsByCategory("company")
        }
    }

    static func peerDiscoveryCompanyId(
        loadCompanySettings: () throws -> [String: String]
    ) throws -> String {
        let settings = try loadCompanySettings()
        let companyId = settings["company_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !companyId.isEmpty else {
            throw SyncError.noCompanyIdConfigured
        }
        return companyId
    }

    func handlePeerDiscoveryCompanyIdFailure(_ error: Error) {
        logger.error("[IOSSyncManager] Peer discovery blocked because company id could not be verified: \(error.localizedDescription)")
        syncStatus = .error
        errorMessage = "Peer discovery unavailable: \(error.localizedDescription)"
        isScanning = false
    }

    /// Issue a one-time pairing code from the shop-side sync server.
    func issueShopPairingCode() async throws -> String {
        guard let pm = peerManager else {
            throw SyncError.noDatabaseAvailable
        }

        let currentState = await pm.getState()
        if !currentState.running {
            let deviceId = DeviceIdentity.current
            let deviceName = UIDevice.current.name
            let companyId: String
            do {
                companyId = try peerDiscoveryCompanyId()
            } catch {
                handlePeerDiscoveryCompanyIdFailure(error)
                throw error
            }
            try await pm.startPeerSync(
                deviceId: deviceId,
                deviceName: deviceName,
                companyId: companyId
            )
            isScanning = true
        }

        return try await pm.issuePairingCode()
    }

    /// Enable or disable Bluetooth/Multipeer sync.
    func setBluetoothEnabled(_ enabled: Bool, startDiscovery: Bool = true) {
        UserDefaults.standard.set(enabled, forKey: "bluetooth_sync_enabled")
        if enabled {
            if startDiscovery {
                startPeerDiscovery()
            }
        } else {
            multipeerManager?.stop()
            multipeerManager = nil
            multipeerDiscoveryMode = nil
            // Remove multipeer-only peers
            removeMultipeerDiscoveredPeers()
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
                state: peer.multipeerState == "connected" ? "connected" : peer.transport,
                discoveredAt: peer.discoveredAt,
                address: peer.host.isEmpty || peer.port == 0 ? nil : "\(peer.host):\(peer.port)"
            )
        }

        // Keep multipeer-only peers that aren't also in LAN
        let lanIds = Set(lanPeers.map(\.id))
        let multipeerOnly = discoveredPeers.filter { !lanIds.contains($0.id) && isMultipeerDiscoveredPeer($0) }
        discoveredPeers = lanPeers + multipeerOnly
    }

    private func handleMultipeerPeersChanged(_ peers: [MultipeerPeerInfo]) {
        let mpPeers = peers.map { peer in
            PeerInfo(
                id: peer.deviceId,
                name: peer.deviceName,
                state: peer.state.rawValue == "connected" ? "connected" : "multipeer",
                discoveredAt: peer.discoveredAt,
                address: nil
            )
        }

        // Merge: replace multipeer entries, keep LAN entries
        let mpIds = Set(mpPeers.map(\.id))
        let nonMultipeer = discoveredPeers.filter { !mpIds.contains($0.id) && !isMultipeerDiscoveredPeer($0) }
        discoveredPeers = nonMultipeer + mpPeers
    }

    private func removeMultipeerDiscoveredPeers() {
        discoveredPeers.removeAll { isMultipeerDiscoveredPeer($0) }
    }

    private func isMultipeerDiscoveredPeer(_ peer: PeerInfo) -> Bool {
        peer.state == "multipeer" || peer.state == "connected"
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

        guard let normalizedPairingCode = SyncCrypto.normalizedPairingCode(pairingCode) else {
            syncStatus = .error
            syncProgressMessage = nil
            errorMessage = "Pairing code must be eight letters or numbers."
            throw SyncError.invalidPairingCode
        }

        let deviceId = DeviceIdentity.current
        let deviceName = UIDevice.current.name

        guard let db else {
            syncStatus = .error
            syncProgressMessage = nil
            errorMessage = SyncError.noDatabaseAvailable.localizedDescription
            throw SyncError.noDatabaseAvailable
        }

        let pairResponse = try await verifyPairingCodeWithShop(
            shopAddress: shopAddress,
            pairingCode: normalizedPairingCode,
            deviceId: deviceId,
            deviceName: deviceName
        )

        syncProgressMessage = "Registering verified device..."
        syncProgressPercent = 0.2

        try ChangeTracker.registerPeerDevice(
            db: db,
            peerId: pairResponse.serverDeviceId,
            peerName: "Shop Computer",
            platform: "shop"
        )

        // Store verified pairing state only after the shop accepts the code and
        // local trusted-device registration succeeds.
        if let service = settingsService {
            try service.upsertSettingsMap([
                "shop_server_address": shopAddress,
                "paired_shop_device_id": pairResponse.serverDeviceId,
                "paired_company_id": pairResponse.companyId,
                "device_pairing_verified_at": pairResponse.pairedAt,
                "auto_sync": "true",
                "sync_interval": "60",
            ], category: "sync")
        }
        UserDefaults.standard.set(true, forKey: "device_paired")
        UserDefaults.standard.set(true, forKey: "bluetooth_sync_enabled")

        syncProgressMessage = "Device registered."
        syncProgressPercent = 0.3
    }

    private func verifyPairingCodeWithShop(
        shopAddress: String,
        pairingCode: String,
        deviceId: String,
        deviceName: String
    ) async throws -> SyncPairResponse {
        let baseURL = try normalizedShopBaseURL(shopAddress)
        let url = baseURL.appendingPathComponent("sync/pair")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SyncPairRequest(
            deviceId: deviceId,
            deviceName: deviceName,
            pairingCode: pairingCode,
            platform: "iOS"
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.syncFailed("Invalid pairing response")
        }

        guard httpResponse.statusCode == 200 else {
            syncStatus = .error
            syncProgressMessage = nil
            errorMessage = httpResponse.statusCode == 403
                ? "Pairing code was not accepted by the shop."
                : "Pairing verification failed: \(httpResponse.statusCode)"
            throw SyncError.pairingVerificationFailed(errorMessage ?? "Pairing verification failed")
        }

        let pairResponse = try JSONDecoder().decode(SyncPairResponse.self, from: data)
        guard pairResponse.accepted else {
            throw SyncError.pairingVerificationFailed("Pairing was not accepted by the shop.")
        }
        return pairResponse
    }

    private func normalizedShopBaseURL(_ shopAddress: String) throws -> URL {
        let trimmed = shopAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let addressWithScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: addressWithScheme),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw SyncError.invalidShopAddress
        }
        return url
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
    /// Fix #215: store the observer token so deinit can remove it.
    func setupAppLifecycleSync() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isSyncAvailable, self.isAutoSyncEnabled else { return }
                await self.syncNow()
            }
        }
    }

    /// Observer token returned by addObserver. Retained so deinit can remove it.
    nonisolated(unsafe) private var foregroundObserver: NSObjectProtocol?

    deinit {
        // Fix #215: invalidate timer and remove notification observer so logout /
        // sync-manager recreation doesn't leak orphan observers and timers.
        syncTimer?.invalidate()
        syncTimer = nil
        if let token = foregroundObserver {
            NotificationCenter.default.removeObserver(token)
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
            "shop_server_address", "paired_shop_device_id", "paired_company_id",
            "device_pairing_verified_at",
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
        case noCompanyIdConfigured
        case invalidPairingCode
        case invalidShopAddress
        case pairingVerificationFailed(String)
        case syncFailed(String)

        var errorDescription: String? {
            switch self {
            case .noDatabaseAvailable: return "Database not available."
            case .noServerConfigured: return "No sync server configured."
            case .noCompanyIdConfigured: return "Company ID is not configured. Open Settings and verify the company profile before starting peer discovery."
            case .invalidPairingCode: return "Pairing code must be eight letters or numbers."
            case .invalidShopAddress: return "Shop address is invalid."
            case .pairingVerificationFailed(let msg): return msg
            case .syncFailed(let msg): return "Sync failed: \(msg)"
            }
        }
    }
}
