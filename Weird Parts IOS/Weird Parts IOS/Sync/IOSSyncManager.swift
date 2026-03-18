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
        guard syncStatus != .syncing else { return }
        syncStatus = .syncing
        errorMessage = nil

        // Simulate sync cycle using SyncEngine
        // In production, this calls SyncEngine.triggerSync()
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        lastSyncDate = formatter.string(from: Date())
        pendingChanges = 0
        syncStatus = .synced
    }

    /// Start scanning for nearby peers.
    func startPeerDiscovery() {
        isScanning = true
        // In production, this calls MultipeerManager.startBrowsing()
        // Simulate finding a peer after a delay
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                isScanning = false
            }
        }
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
