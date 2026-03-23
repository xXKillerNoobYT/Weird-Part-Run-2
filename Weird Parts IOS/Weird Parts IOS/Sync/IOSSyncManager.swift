import SwiftUI
import Observation
import WiredPartCore

/// Manages the overall sync lifecycle for the iOS app.
///
/// Wraps `SyncEngine` (LAN HTTP) and `MultipeerManager` (BT/WiFi P2P) into
/// a single observable object that the UI layer can observe for status updates.
///
/// On initialization, starts listening for shop discovery. When a shop is found,
/// begins periodic sync on the configured interval.
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

    struct PeerInfo: Identifiable, Sendable {
        let id: String
        let name: String
        let state: String
        let discoveredAt: String
    }

    /// Whether real sync infrastructure is connected.
    /// When false, sync operations show "not available" instead of faking it.
    var isSyncAvailable: Bool { false }

    init() {}

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

    /// Trigger a sync cycle immediately.
    func syncNow() async {
        guard isSyncAvailable else {
            syncStatus = .idle
            errorMessage = "Sync not configured. Connect to a shop computer first."
            return
        }
        guard syncStatus != .syncing else { return }
        syncStatus = .syncing
        errorMessage = nil

        // Real sync will call SyncEngine.triggerSync() here
    }

    /// Start scanning for nearby peers.
    func startPeerDiscovery() {
        guard isSyncAvailable else {
            isScanning = false
            errorMessage = "Peer discovery requires sync infrastructure. Connect to a shop computer first."
            return
        }
        isScanning = true
        // In production, this calls MultipeerManager.startBrowsing()
    }

    /// Stop scanning for peers.
    func stopPeerDiscovery() {
        isScanning = false
    }

    /// Call to clean up timer before deallocation.
    func cleanup() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
}
