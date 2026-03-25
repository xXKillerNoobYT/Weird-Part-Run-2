import SwiftUI
import Observation
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
        self.syncEngine = SyncEngine(db: db)
        self.peerManager = PeerManager(db: db)

        // Subscribe to sync engine state changes
        Task { [weak self] in
            guard let engine = self?.syncEngine else { return }
            await engine.setOnStateChanged { @Sendable state in
                Task { @MainActor [weak self] in
                    self?.handleSyncStateChange(state)
                }
            }
        }

        // Subscribe to peer manager state changes
        Task { [weak self] in
            guard let pm = self?.peerManager else { return }
            await pm.setOnStateChanged { @Sendable state in
                Task { @MainActor [weak self] in
                    self?.handlePeerStateChange(state)
                }
            }
        }

        // Load initial pending count
        refreshPendingCount()
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
            let failed = results.filter { !$0.success }
            if !failed.isEmpty, errorMessage == nil {
                errorMessage = "Sync failed with \(failed.count) peer(s)"
            }
        }

        // Update state
        refreshPendingCount()
        if errorMessage == nil {
            syncStatus = .synced
            let formatter = ISO8601DateFormatter()
            lastSyncDate = formatter.string(from: Date())
        } else {
            syncStatus = .error
        }
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
        let formatter = ISO8601DateFormatter()
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
}
