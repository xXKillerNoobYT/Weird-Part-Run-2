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
    /// Host-side: name of the peer we are actively pushing a full sync to (nil when idle).
    var activeSyncPeerName: String?
    /// Host-side: human summary of the most recent completed peer transfer.
    var lastHostSyncSummary: String?
    var isPaired: Bool {
        guard let service = settingsService else {
            return false
        }
        let map: [String: String]
        do {
            map = try service.getSettingsByCategory("sync")
        } catch {
            syncSettingsReadFailed(error, context: "load pairing status")
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

    // @ObservationIgnored keeps this a plain stored property so nonisolated(unsafe)
    // takes effect (deinit needs synchronous access); no view observes the timer.
    @ObservationIgnored nonisolated(unsafe) private var syncTimer: Timer?
    private var syncIntervalSeconds: TimeInterval = 60

    private var db: AppDatabase?
    private var settingsService: SettingsService?
    private var syncEngine: SyncEngine?
    private var peerManager: PeerManager?
    private var multipeerManager: MultipeerManager?
    private var multipeerDiscoveryMode: PeerDiscoveryMode?
    private var peerDiscoveryStartupTask: Task<Void, Never>?
    private var peerDiscoveryGeneration = 0
    private var lastSurfacedSyncReadFailure: String?

    struct PeerInfo: Identifiable, Sendable {
        let id: String
        let name: String
        let state: String
        let discoveredAt: String
        let address: String?
        let isManuallySyncable: Bool
    }

    enum PeerDiscoveryMode: Equatable {
        case existingCompanySync
        case onboardingJoin
    }

    /// Bluetooth/Multipeer sync is ON by default — offline peer-to-peer sync is
    /// this app's primary transport (Wi-Fi is only a speed boost). The stored
    /// flag exists so a user can explicitly turn it OFF; an unset flag means on.
    static var bluetoothSyncEnabled: Bool {
        if UserDefaults.standard.object(forKey: "bluetooth_sync_enabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "bluetooth_sync_enabled")
    }

    /// Whether real sync infrastructure is connected.
    /// True when a server address is configured OR Bluetooth sync is enabled.
    var isSyncAvailable: Bool {
        let hasServer = !(serverAddress ?? "").isEmpty
        return hasServer || Self.bluetoothSyncEnabled
    }

    /// Whether automatic launch/foreground sync is enabled by settings.
    var isAutoSyncEnabled: Bool {
        guard let service = settingsService else { return false }
        do {
            return try service.isAutoSyncEnabled()
        } catch {
            syncSettingsReadFailed(error, context: "load auto-sync setting")
            return false
        }
    }

    /// The configured shop server address from settings, or nil.
    private var serverAddress: String? {
        guard let service = settingsService else { return nil }
        do {
            let addr = try service.getSettingsByCategory("sync")["shop_server_address"]
            return Self.normalizedShopServerAddress(addr)
        } catch {
            syncSettingsReadFailed(error, context: "load sync server address")
            return nil
        }
    }

    private func syncSettingsReadFailed(_ error: Error, context: String) {
        let message = userFriendlyError(error, context: context)
        let failureKey = "\(context): \(message)"
        guard lastSurfacedSyncReadFailure != failureKey else { return }
        lastSurfacedSyncReadFailure = failureKey
        syncStatus = .error
        errorMessage = message
        logger.error("[IOSSyncManager] \(context) failed: \(error.localizedDescription)")
    }

    private func syncReadFailed(_ error: Error, context: String, logMessage: String) {
        syncStatus = .error
        errorMessage = userFriendlyError(error, context: context)
        logger.error("[IOSSyncManager] \(logMessage): \(error.localizedDescription)")
    }

    private func syncReviewActionFailed(_ message: String) {
        syncStatus = .error
        errorMessage = message
        logger.error("[IOSSyncManager] \(message)")
    }

    func surfaceConflictReviewActionFailure(_ message: String) {
        syncReviewActionFailed(message)
    }

    /// Publishes the fail-closed state for any LAN pairing failure after pairing starts.
    /// The caller remains responsible for rethrowing the original error unchanged.
    func surfaceShopPairingFailure(_ error: Error) {
        syncStatus = .error
        syncProgressMessage = nil
        if error is SyncIdentityStoreError {
            errorMessage = "Couldn't securely load this device's sync identity. Pairing stopped; try again."
        } else if let syncError = error as? SyncError {
            errorMessage = syncError.localizedDescription
        } else {
            errorMessage = "Pairing verification failed. Check the shop address and pairing code, then try again."
        }
        logger.error("[IOSSyncManager] Shop pairing failed: \(error.localizedDescription)")
    }

    /// Trims a user-entered or persisted shop server address and rejects blank values.
    static func normalizedShopServerAddress(_ address: String?) -> String? {
        let trimmed = address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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

        // Bluetooth sync is ON by default: once this device belongs to a company,
        // start peer discovery and the auto-sync timer at launch so devices find
        // each other and exchange changes WITHOUT someone camping on the Devices
        // page. Previously nothing auto-started peer sync post-onboarding, so a
        // job created on one device never reached the other until a manual visit.
        // Skipped under UI testing (network churn breaks XCTest runs).
        // "Belongs to a company" = has an active business profile (device that
        // CREATED the company — may not have a company_id persisted yet) OR has
        // a company_id setting (device that JOINED via pairing). Gating only on
        // company_id left creator devices dark until they opened Add-a-Device
        // once (Copilot review on PR #1422). startPeerDiscovery() generates and
        // persists a company_id when one is missing.
        let companyId = (try? settingsService.getSettingsByCategory("company")["company_id"]) ?? nil
        let hasProfile = (try? settingsService.hasBusinessProfile()) ?? false
        let hasCompanyId = !(companyId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !ProcessInfo.processInfo.arguments.contains("-UITesting"),
           Self.bluetoothSyncEnabled,
           hasProfile || hasCompanyId {
            startPeerDiscovery()
            if isAutoSyncEnabled {
                startAutoSync()
            }
        }
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

        peerDiscoveryStartupTask?.cancel()
        peerDiscoveryStartupTask = nil
        peerDiscoveryGeneration += 1
        let startupGeneration = peerDiscoveryGeneration

        if mode == .existingCompanySync {
            multipeerManager?.stop()
            multipeerManager = nil
            multipeerDiscoveryMode = nil
            removeMultipeerDiscoveredPeers()
        }

        let companyId: String
        switch mode {
        case .existingCompanySync:
            do {
                companyId = try peerDiscoveryCompanyId()
            } catch {
                if let pm = peerManager {
                    Task { await pm.stopPeerSync() }
                }
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

        // Bluetooth discovery + pairing for onboarding join now runs through the
        // PeerManager's own Multipeer manager (started just below via startMultipeer).
        // That is the manager `pairViaMultipeer` uses, so the discovered host can
        // actually be invited/paired. A separate MultipeerManager here would
        // double-browse the same service and leave pairing unable to reach the host.
        let bluetoothDiscoveryEnabled = Self.bluetoothSyncEnabled

        // Also start LAN peer discovery when available. Existing sync discovery
        // stays company-scoped. Join/onboarding discovery relaxes LAN browsing
        // so a fresh device can discover a shop HTTP address before the pairing
        // response verifies and persists the real company ID.
        if let pm = peerManager {
            peerDiscoveryStartupTask = Task {
                let deviceId = DeviceIdentity.current
                let deviceName = Self.advertisedDeviceName
                do {
                    guard isCurrentPeerDiscoveryStartup(startupGeneration) else { return }
                    if await pm.getState().running {
                        guard isCurrentPeerDiscoveryStartup(startupGeneration) else { return }
                        await pm.stopPeerSync()
                    }
                    guard isCurrentPeerDiscoveryStartup(startupGeneration) else { return }
                    try await pm.startPeerSync(
                        deviceId: deviceId,
                        deviceName: deviceName,
                        companyId: companyId,
                        allowAnyCompanyPeerDiscovery: mode == .onboardingJoin,
                        startMultipeer: bluetoothDiscoveryEnabled && (mode == .existingCompanySync || mode == .onboardingJoin),
                        startSyncServer: mode == .existingCompanySync
                    )
                    if !isScanning {
                        await pm.stopPeerSync()
                    }
                } catch {
                    guard isCurrentPeerDiscoveryStartup(startupGeneration) else { return }
                    handleLanPeerDiscoveryStartupFailure(
                        error,
                        hasActiveMultipeerDiscovery: bluetoothDiscoveryEnabled && mode == .onboardingJoin
                    )
                }
            }
        }
    }

    private func isCurrentPeerDiscoveryStartup(_ generation: Int) -> Bool {
        !Task.isCancelled && isScanning && peerDiscoveryGeneration == generation
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
        peerDiscoveryGeneration += 1
        peerDiscoveryStartupTask?.cancel()
        peerDiscoveryStartupTask = nil
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
        // Resolve the stable company id used to scope peer discovery/sync.
        //
        // Newly-created companies (the "Create New Business" onboarding path) never
        // had a `company_id` setting written — nothing in the app set it — so peer
        // discovery and "Add a Device" pairing failed with `noCompanyIdConfigured`.
        // Generate and persist one on first use (get-or-create). It is idempotent:
        // once written, the same id is returned forever. Devices that JOIN an
        // existing company overwrite this with the shop's company id during pairing,
        // so both ends share one id and cross-company peers are still rejected.
        do {
            return try Self.peerDiscoveryCompanyId {
                try settingsService.getSettingsByCategory("company")
            }
        } catch SyncError.noCompanyIdConfigured {
            let generated = UUID().uuidString
            try settingsService.updateSetting(key: "company_id", value: generated, category: "company")
            logger.info("[IOSSyncManager] No company_id was set; generated and persisted one for peer sync.")
            return generated
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
            let deviceName = Self.advertisedDeviceName
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

        // Allow a not-yet-in-company device to connect over Bluetooth to complete
        // the code handshake (the code is the security gate).
        await pm.setBluetoothPairingHostMode(true)
        return try await pm.issuePairingCode()
    }

    /// End an Add-a-Device pairing offer: invalidate any outstanding code and
    /// close the cross-company Bluetooth connection window. Called when the
    /// pairing sheet is dismissed (Copilot review on PR #1422 — the window must
    /// not stay open once no code is being offered).
    func endPairingOffer() async {
        guard let pm = peerManager else { return }
        await pm.clearPairingCode()
    }

    /// Joiner: pair with a Bluetooth-discovered host over Multipeer (no Wi-Fi).
    /// Mirrors `pairWithShop` but exchanges the code over the Bluetooth session and
    /// adopts the host's company id so both devices share one company.
    func pairWithPeerOverBluetooth(hostDeviceId: String, hostName: String, pairingCode: String) async throws {
        syncStatus = .syncing
        syncProgressMessage = "Connecting over Bluetooth…"
        syncProgressPercent = 0.1

        guard let normalizedCode = SyncCrypto.normalizedPairingCode(pairingCode) else {
            syncStatus = .error
            syncProgressMessage = nil
            errorMessage = "Pairing code must be eight letters or numbers."
            throw SyncError.invalidPairingCode
        }
        guard let pm = peerManager, let db else {
            syncStatus = .error
            syncProgressMessage = nil
            errorMessage = SyncError.noDatabaseAvailable.localizedDescription
            throw SyncError.noDatabaseAvailable
        }

        let myDeviceId = DeviceIdentity.current
        let myDeviceName = Self.advertisedDeviceName

        let response = try await pm.pairViaMultipeer(
            hostDeviceId: hostDeviceId,
            myDeviceId: myDeviceId,
            myDeviceName: myDeviceName,
            pairingCode: normalizedCode,
            platform: "iOS"
        )

        syncProgressMessage = "Registering verified device…"
        syncProgressPercent = 0.3

        try ChangeTracker.registerPeerDevice(
            db: db,
            peerId: response.serverDeviceId,
            peerName: hostName.isEmpty ? "Paired Device" : hostName,
            platform: "ios",
            keyAgreementPublicKey: response.serverKeyAgreementPublicKey
        )
        if let service = settingsService {
            try service.upsertSettingsMap([
                "paired_shop_device_id": response.serverDeviceId,
                "paired_company_id": response.companyId,
                "device_pairing_verified_at": response.pairedAt,
                "auto_sync": "true",
                "sync_interval": "60",
            ], category: "sync")
            // Adopt the host's company id (see the LAN pairWithShop path).
            let joinedCompanyId = response.companyId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !joinedCompanyId.isEmpty {
                try service.updateSetting(key: "company_id", value: joinedCompanyId, category: "company")
            }
        }
        UserDefaults.standard.set(true, forKey: "device_paired")
        UserDefaults.standard.set(true, forKey: "bluetooth_sync_enabled")

        syncProgressMessage = "Paired over Bluetooth."
        syncProgressPercent = 0.4
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
            if let pm = peerManager {
                Task {
                    await pm.stopMultipeerDiscovery()
                }
            }
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
        // Host-side transfer feedback: who we're actively sending to, and the last
        // completed transfer per peer (drives "Syncing…"/"Synced N records" UI).
        if let syncingId = state.syncingWith {
            activeSyncPeerName = state.peers.first(where: { $0.deviceId == syncingId })?.deviceName
                ?? discoveredPeers.first(where: { $0.id == syncingId })?.name
                ?? "device"
        } else {
            activeSyncPeerName = nil
        }
        if let latest = state.lastPeerSyncs.values.max(by: { $0.syncedAt < $1.syncedAt }) {
            lastHostSyncSummary = latest.success
                ? "Sent \(latest.pushed) records to \(latest.peerName)"
                : "Sync with \(latest.peerName) failed"
        }

        // Merge LAN peers into our peer list
        let lanPeers = state.peers.map { peer in
            let address = formattedPeerAddress(host: peer.host, port: Int(peer.port))
            return PeerInfo(
                id: peer.deviceId,
                name: peer.deviceName,
                state: peer.transport == "multipeer"
                    ? Self.multipeerDisplayState(peer.multipeerState)
                    : (peer.multipeerState == "connected" ? "connected" : peer.transport),
                discoveredAt: peer.discoveredAt,
                address: address,
                isManuallySyncable: Self.isManuallySyncablePeer(
                    transport: peer.transport,
                    multipeerState: peer.multipeerState,
                    address: address
                )
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
                state: Self.multipeerDisplayState(peer.state.rawValue),
                discoveredAt: peer.discoveredAt,
                address: nil,
                isManuallySyncable: Self.isManuallySyncablePeer(
                    transport: "multipeer",
                    multipeerState: peer.state.rawValue,
                    address: nil
                )
            )
        }

        // Merge: keep LAN/addressable entries when the same device is also seen via Multipeer.
        // Bluetooth-only rows are useful fallbacks, but they must not replace a peer with a
        // usable Wi-Fi address during onboarding pairing.
        let nonMultipeer = discoveredPeers.filter { !isMultipeerDiscoveredPeer($0) }
        let nonMultipeerIds = Set(nonMultipeer.map(\.id))
        let multipeerOnly = mpPeers.filter { !nonMultipeerIds.contains($0.id) }
        discoveredPeers = nonMultipeer + multipeerOnly
    }

    private func removeMultipeerDiscoveredPeers() {
        discoveredPeers.removeAll { isMultipeerDiscoveredPeer($0) }
    }

    private func isMultipeerDiscoveredPeer(_ peer: PeerInfo) -> Bool {
        peer.state == "multipeer" || peer.state == "connecting"
            || (peer.state == "connected" && peer.address == nil)
    }

    /// Maps a raw Multipeer connection state ("found"/"connecting"/"connected")
    /// onto a `PeerInfo` display state. `connecting` stays distinct so the peer
    /// browser can show an in-progress row instead of a generic waiting state;
    /// `found` (and any future states) collapse to the waiting "multipeer" row.
    private static func multipeerDisplayState(_ multipeerState: String?) -> String {
        switch multipeerState {
        case "connected": return "connected"
        case "connecting": return "connecting"
        default: return "multipeer"
        }
    }

    private func formattedPeerAddress(host: String, port: Int) -> String? {
        guard !host.isEmpty, port > 0 else { return nil }
        let formattedHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return "\(formattedHost):\(port)"
    }

    private static func isManuallySyncablePeer(
        transport: String,
        multipeerState: String?,
        address: String?
    ) -> Bool {
        if transport == "multipeer" {
            return multipeerState == "connected"
        }
        return transport == "lan" && address != nil
    }

    private func refreshPendingCount() {
        guard let db else { return }
        do {
            pendingChanges = try ChangeTracker.getPendingChangeCount(db: db)
        } catch {
            syncReadFailed(
                error,
                context: "load pending sync changes",
                logMessage: "pending change count refresh failed"
            )
        }
    }

    /// Refresh and return the current unreviewed conflict count.
    @discardableResult
    func refreshConflictCount() -> Int {
        guard let db else { return 0 }
        do {
            let stats = try ConflictResolver.getConflictStats(db: db)
            unreviewedConflictCount = stats.unreviewed
            return stats.last24h
        } catch {
            syncReadFailed(
                error,
                context: "load sync conflict count",
                logMessage: "conflict count refresh failed"
            )
            return 0
        }
    }

    /// Get unreviewed conflicts for the review page.
    func getUnreviewedConflicts() -> [ConflictLogEntry] {
        guard let db else { return [] }
        do {
            return try ConflictResolver.getUnreviewedConflicts(db: db)
        } catch {
            syncReadFailed(
                error,
                context: "load unreviewed sync conflicts",
                logMessage: "unreviewed conflict load failed"
            )
            return []
        }
    }

    /// Mark a single conflict as reviewed.
    @discardableResult
    func markConflictReviewed(conflictId: Int64) -> Bool {
        guard let db else {
            syncReviewActionFailed("Sync conflict could not be marked reviewed because the database is unavailable.")
            return false
        }
        do {
            try ConflictResolver.markConflictReviewed(db: db, conflictId: conflictId)
            refreshConflictCount()
            return true
        } catch {
            syncReadFailed(
                error,
                context: "mark sync conflict reviewed",
                logMessage: "markConflictReviewed failed for id \(conflictId)"
            )
            return false
        }
    }

    /// Apply the reviewer's chosen side of a conflict to the live record, then
    /// mark it reviewed. Unlike `markConflictReviewed`, this actually writes the
    /// chosen value when it differs from the LWW winner and change-logs it so the
    /// decision syncs to peers.
    @discardableResult
    func resolveConflict(_ conflict: ConflictLogEntry, keepLocal: Bool) -> Bool {
        guard let db else {
            syncReviewActionFailed("Sync conflict could not be resolved because the database is unavailable.")
            return false
        }
        do {
            try ConflictResolver.applyConflictResolution(
                db: db,
                conflict: conflict,
                choice: keepLocal ? .keepLocal : .keepRemote
            )
            refreshConflictCount()
            refreshPendingCount()
            return true
        } catch {
            syncReadFailed(
                error,
                context: "apply sync conflict resolution",
                logMessage: "applyConflictResolution failed for id \(conflict.id.map(String.init) ?? "nil")"
            )
            return false
        }
    }

    /// Mark all unreviewed conflicts as reviewed.
    @discardableResult
    func markAllConflictsReviewed() -> Bool {
        guard let db else {
            syncReviewActionFailed("Sync conflicts could not be marked reviewed because the database is unavailable.")
            return false
        }
        let conflicts: [ConflictLogEntry]
        do {
            conflicts = try ConflictResolver.getUnreviewedConflicts(db: db)
        } catch {
            syncReadFailed(
                error,
                context: "load unreviewed sync conflicts before marking reviewed",
                logMessage: "unreviewed conflict load failed before markAllConflictsReviewed"
            )
            return false
        }
        var allReviewed = true
        for conflict in conflicts {
            guard let id = conflict.id else {
                allReviewed = false
                syncReviewActionFailed("A sync conflict could not be marked reviewed because its conflict id is missing. Reload conflicts and try again.")
                continue
            }

            do {
                try ConflictResolver.markConflictReviewed(db: db, conflictId: id)
            } catch {
                allReviewed = false
                syncReadFailed(
                    error,
                    context: "mark sync conflicts reviewed",
                    logMessage: "markConflictReviewed failed for id \(id)"
                )
            }
        }
        refreshConflictCount()
        return allReviewed
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

        guard let normalizedShopAddress = Self.normalizedShopServerAddress(shopAddress) else {
            syncStatus = .error
            syncProgressMessage = nil
            errorMessage = SyncError.invalidShopAddress.localizedDescription
            throw SyncError.invalidShopAddress
        }

        guard let normalizedPairingCode = SyncCrypto.normalizedPairingCode(pairingCode) else {
            syncStatus = .error
            syncProgressMessage = nil
            errorMessage = "Pairing code must be eight letters or numbers."
            throw SyncError.invalidPairingCode
        }

        let deviceId = DeviceIdentity.current
        let deviceName = Self.advertisedDeviceName

        guard let db, let pm = peerManager else {
            syncStatus = .error
            syncProgressMessage = nil
            errorMessage = SyncError.noDatabaseAvailable.localizedDescription
            throw SyncError.noDatabaseAvailable
        }
        let pairingIdentity: SyncDeviceIdentity
        let pairResponse: SyncPairResponse
        do {
            pairingIdentity = try await pm.localSyncIdentity(deviceId: deviceId)
            pairResponse = try await verifyPairingCodeWithShop(
                shopAddress: normalizedShopAddress,
                pairingCode: normalizedPairingCode,
                deviceId: deviceId,
                deviceName: deviceName,
                pairingIdentity: pairingIdentity
            )
        } catch {
            surfaceShopPairingFailure(error)
            throw error
        }

        syncProgressMessage = "Registering verified device..."
        syncProgressPercent = 0.2

        guard let serverKey = pairResponse.serverKeyAgreementPublicKey,
              Data(base64Encoded: serverKey)?.count == 32 else {
            let error = SyncError.pairingVerificationFailed("The shop did not provide a trusted LAN key.")
            syncStatus = .error
            syncProgressMessage = nil
            errorMessage = error.localizedDescription
            throw error
        }
        try ChangeTracker.registerPeerDevice(
            db: db,
            peerId: pairResponse.serverDeviceId,
            peerName: "Shop Computer",
            platform: "shop",
            keyAgreementPublicKey: serverKey
        )

        // Store verified pairing state only after the shop accepts the code and
        // local trusted-device registration succeeds.
        if let service = settingsService {
            try service.upsertSettingsMap([
                "shop_server_address": normalizedShopAddress,
                "paired_shop_device_id": pairResponse.serverDeviceId,
                "paired_company_id": pairResponse.companyId,
                "device_pairing_verified_at": pairResponse.pairedAt,
                "auto_sync": "true",
                "sync_interval": "60",
            ], category: "sync")

            // Adopt the shop's company id as this device's own peer-discovery id
            // (the "company" category is what `peerDiscoveryCompanyId()` reads).
            // Without this, a joined device keeps its own generated company_id and
            // would advertise/discover under a different id than the shop, so the
            // two would reject each other as cross-company peers after pairing.
            let joinedCompanyId = pairResponse.companyId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !joinedCompanyId.isEmpty {
                try service.updateSetting(key: "company_id", value: joinedCompanyId, category: "company")
            }
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
        deviceName: String,
        pairingIdentity: SyncDeviceIdentity
    ) async throws -> SyncPairResponse {
        let baseURL = try normalizedShopBaseURL(shopAddress)
        let url = baseURL.appendingPathComponent("sync/pair")
        let pairingPrivateKey = pairingIdentity.privateKeyB64
        let pairingPublicKey = pairingIdentity.publicKeyB64
        let pairingProof = SyncCrypto.pairingProof(
            normalizedCode: pairingCode,
            deviceId: deviceId,
            clientPublicKeyB64: pairingPublicKey
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SyncPairRequest(
            deviceId: deviceId,
            deviceName: deviceName,
            pairingProof: pairingProof,
            platform: "iOS",
            keyAgreementPublicKey: pairingPublicKey
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

        guard let wrappedResponse = try? JSONDecoder().decode(SyncPairEncryptedResponse.self, from: data),
              let encryptedPayload = Data(base64Encoded: wrappedResponse.encryptedPayload) else {
            throw SyncError.pairingVerificationFailed("Pairing response encryption was invalid.")
        }
        let sharedKey = try SyncCrypto.derivePairingSharedKeyData(
            ourPrivateKeyB64: pairingPrivateKey,
            theirPublicKeyB64: wrappedResponse.serverKeyAgreementPublicKey,
            normalizedCode: pairingCode,
            clientPublicKeyB64: pairingPublicKey,
            serverPublicKeyB64: wrappedResponse.serverKeyAgreementPublicKey
        )
        let aad = Data(
            [
                "wiredpart-sync-pairing-response-aad-v1",
                deviceId,
                pairingPublicKey,
                wrappedResponse.serverKeyAgreementPublicKey,
            ].joined(separator: "\n").utf8
        )
        let plainResponse = try SyncCrypto.decryptAESGCM(
            data: encryptedPayload,
            keyData: sharedKey,
            aad: aad
        )
        let pairResponse = try JSONDecoder().decode(SyncPairResponse.self, from: plainResponse)
        guard pairResponse.accepted else {
            throw SyncError.pairingVerificationFailed("Pairing was not accepted by the shop.")
        }
        return pairResponse
    }

    private func normalizedShopBaseURL(_ shopAddress: String) throws -> URL {
        guard let trimmed = Self.normalizedShopServerAddress(shopAddress) else {
            throw SyncError.invalidShopAddress
        }
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
    /// Human-friendly name this device advertises to peers. On Mac Catalyst
    /// `UIDevice.current.name` returns a generic "iPad", so use the Mac's own
    /// computer/host name instead so a Mac doesn't appear as an iPad.
    static var advertisedDeviceName: String {
        #if targetEnvironment(macCatalyst)
        let host = ProcessInfo.processInfo.hostName
            .replacingOccurrences(of: ".local", with: "")
            .trimmingCharacters(in: .whitespaces)
        return host.isEmpty ? "Mac" : "\(host) (Mac)"
        #else
        return UIDevice.current.name
        #endif
    }

    /// The device id of a host this device paired with over Bluetooth (no Wi-Fi
    /// server address). Used to route the initial sync over the Multipeer session.
    private func pairedBluetoothHostDeviceId() -> String? {
        guard serverAddress == nil, let service = settingsService else { return nil }
        guard let sync = try? service.getSettingsByCategory("sync") else { return nil }
        let id = (sync["paired_shop_device_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    func performInitialSync() async throws {
        syncStatus = .syncing
        syncProgressMessage = "Starting initial sync..."
        syncProgressPercent = 0.0

        guard db != nil else {
            syncProgressMessage = nil
            throw SyncError.noDatabaseAvailable
        }

        let deviceId = DeviceIdentity.current

        // Prefer Wi-Fi/LAN when a shop server address is known (faster full download);
        // otherwise fall back to the Bluetooth initial sync for a device that paired
        // over Bluetooth (no server address).
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
        } else if let hostDeviceId = pairedBluetoothHostDeviceId(), let pm = peerManager {
            // Bluetooth: ask the paired host to replay the whole company over the
            // live Multipeer session — no Wi-Fi/server needed.
            syncProgressMessage = "Downloading data over Bluetooth…"
            syncProgressPercent = 0.3
            do {
                try await pm.requestFullSyncOverMultipeer(hostDeviceId: hostDeviceId)
            } catch {
                syncProgressMessage = nil
                syncStatus = .error
                errorMessage = "Bluetooth sync failed. Keep both devices close with Bluetooth on and try again."
                throw error
            }
            syncProgressMessage = "Initial sync complete."
            syncProgressPercent = 1.0
            syncStatus = .synced
            lastSyncDate = Formatters.iso8601Basic.string(from: Date())
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
    /// @ObservationIgnored keeps this a plain stored property so nonisolated(unsafe)
    /// takes effect (deinit needs synchronous access); no view observes the token.
    @ObservationIgnored nonisolated(unsafe) private var foregroundObserver: NSObjectProtocol?

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
