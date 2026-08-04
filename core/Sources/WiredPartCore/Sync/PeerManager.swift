import Foundation
import GRDB
import os.log

// MARK: - Peer Sync Result

/// Outcome of syncing with a single peer.
public struct PeerSyncResult: Sendable {
    public let peerDeviceId: String
    public let peerName: String
    public var pushed: Int
    public var pulled: Int
    public var success: Bool
    public var error: String?
    public let syncedAt: String

    public init(
        peerDeviceId: String,
        peerName: String,
        pushed: Int = 0,
        pulled: Int = 0,
        success: Bool = true,
        error: String? = nil,
        syncedAt: String? = nil
    ) {
        self.peerDeviceId = peerDeviceId
        self.peerName = peerName
        self.pushed = pushed
        self.pulled = pulled
        self.success = success
        self.error = error
        self.syncedAt = syncedAt ?? CoreFormatters.iso8601Fractional.string(from: Date())
    }
}

// MARK: - Peer Manager State

/// Snapshot of the peer manager's current state.
public struct PeerManagerState: Sendable {
    public var running: Bool
    public var syncPort: UInt16
    public var peers: [DiscoveredPeer]
    public var lastPeerSyncs: [String: PeerSyncResult]
    public var syncingWith: String?

    public init(
        running: Bool = false,
        syncPort: UInt16 = 0,
        peers: [DiscoveredPeer] = [],
        lastPeerSyncs: [String: PeerSyncResult] = [:],
        syncingWith: String? = nil
    ) {
        self.running = running
        self.syncPort = syncPort
        self.peers = peers
        self.lastPeerSyncs = lastPeerSyncs
        self.syncingWith = syncingWith
    }
}

private enum PeerSyncHTTPError: LocalizedError {
    case nonHTTPResponse(endpoint: String)
    case httpError(endpoint: String, statusCode: Int)
    case malformedResponse(endpoint: String)

    var errorDescription: String? {
        switch self {
        case .nonHTTPResponse(let endpoint):
            return "LAN sync \(endpoint) failed: non-HTTP response"
        case .httpError(let endpoint, let statusCode):
            return "LAN sync \(endpoint) failed: HTTP \(statusCode)"
        case .malformedResponse(let endpoint):
            return "LAN sync \(endpoint) failed: malformed response"
        }
    }
}

// MARK: - Peer Manager

/// Peer discovery and sync coordinator.
///
/// Ported from: `src/local/peer-manager.ts`
///
/// Dual discovery:
/// - mDNS via NWBrowser (LAN)
/// - Apple Multipeer Connectivity (BT + Wi-Fi P2P)
///
/// Sync flow per peer:
/// 1. Push our pending changes to peer's sync server
/// 2. Pull peer's changes from their sync server
/// 3. Apply received changes via ConflictResolver
///
/// Sync order: Office computers first, then least-recently-synced.
/// Typed envelope for Multipeer messages so the Bluetooth channel can carry more
/// than sync changes (e.g. the pairing handshake). Legacy senders transmit a bare
/// `[IncomingChange]` JSON array; the receiver falls back to that when envelope
/// decoding fails, so this is backwards-compatible.
struct MPEnvelope: Codable {
    let type: String   // pairing, changes, full-sync request/completion/acknowledgement
    let payload: Data
}

struct FullSyncApplyAcknowledgement: Codable {
    let authorizationToken: String
    let succeeded: Bool
    let error: String?
}

private struct HostedSnapshotReservation {
    let authorizationToken: String
    let peerName: String
    var rowsSent: Int?
}

struct BluetoothPairingAttemptContext {
    let protocolVersion: Int
    let expectedHostDeviceId: String
    let clientDeviceId: String
    let clientPrivateKeyB64: String
    let clientPublicKeyB64: String
    let normalizedPairingCode: String
    let requestNonce: String
    let requestPairingProof: String
}

private struct PendingBluetoothPairingAttempt {
    let requestNonce: String
    let continuation: CheckedContinuation<SyncPairResponse, Error>
}

public enum MultipeerPairingError: Error {
    case notAvailable
    case connectionTimeout
    case sendFailed
    case responseTimeout
    case rejected
    case requestAlreadyInProgress
    case protocolUpgradeRequired
    case responseVerificationFailed
    case transportStopped
}

public actor PeerManager {

    private let db: AppDatabase
    private let identityStore: any SyncDeviceIdentityStoring
    private var state = PeerManagerState()
    private let logger = Logger(subsystem: "com.wiredpart.core", category: "PeerManager")

    private var syncServer: LanSyncServer?
    private var serverState: SyncServerState?
    private var peerDiscovery: PeerDiscovery?

    #if canImport(MultipeerConnectivity)
    private var multipeerManager: MultipeerManager?
    // Joiner-side: each waiter is owned by its request nonce as well as host id.
    private var pendingPairContinuations: [String: PendingBluetoothPairingAttempt] = [:]
    private var pendingBluetoothPairingContexts: [String: BluetoothPairingAttemptContext] = [:]
    // Joiner-side: continuations awaiting a full initial sync to complete, keyed by host deviceId.
    private var pendingFullSyncContinuations: [String: CheckedContinuation<Void, Error>] = [:]
    // Full-snapshot pages remain in memory until completion, then commit in one transaction.
    private var pendingSnapshotChanges: [String: [IncomingChange]] = [:]
    // Ignore remaining queued pages after a failed snapshot until an explicit retry starts.
    private var failedSnapshotPeers: Set<String> = []
    // Pairing-issued capabilities bind initial snapshots to the successful code exchange.
    private var hostedSnapshotTokens: [String: String] = [:]
    private var hostedSnapshotReservations: [String: HostedSnapshotReservation] = [:]
    private var receivedSnapshotTokens: [String: String] = [:]
    private var inFlightPairRequests: Set<String> = []
    private var inFlightFullSyncRequests: Set<String> = []
    private var isDrainingMultipeerMessages = false
    #endif

    private var peerPollTask: Task<Void, Never>?
    private var inboxProcessTask: Task<Void, Never>?

    /// X25519 key agreement keys for this session. Generated when peer sync starts.
    private var kaPrivateKeyB64: String = ""
    private var kaPublicKeyB64: String = ""

    /// Company ID for this sync session. Sent as X-Company-ID on key-exchange requests (#191).
    private var companyId: String = ""

    /// Cached X25519 public keys from peers, keyed by peer device ID.
    private var peerKAPublicKeys: [String: String] = [:]

    /// Called when state changes.
    public var onStateChanged: (@Sendable (PeerManagerState) -> Void)?

    /// Set the state-changed callback from outside the actor.
    public func setOnStateChanged(_ callback: (@Sendable (PeerManagerState) -> Void)?) {
        onStateChanged = callback
    }

    /// The app always uses the durable Keychain-backed store. XCTest processes
    /// receive an in-memory store because iOS test bundles do not carry the app
    /// Keychain entitlement; keeping that decision here prevents a test-only
    /// environment workaround from ever reaching pairing or encryption logic.
    public init(db: AppDatabase) {
        self.init(
            db: db,
            identityStore: Self.identityStoreForRuntime(
                isRunningUnitTests: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            )
        )
    }

    public init(
        db: AppDatabase,
        identityStore: any SyncDeviceIdentityStoring
    ) {
        self.db = db
        self.identityStore = identityStore
    }

    /// Internal so the test bundle can prove its identity storage is isolated
    /// without changing the production Keychain failure contract.
    static func identityStoreForRuntime(
        isRunningUnitTests: Bool
    ) -> any SyncDeviceIdentityStoring {
        isRunningUnitTests
            ? InMemorySyncDeviceIdentityStore()
            : PlatformSyncDeviceIdentityStore.shared
    }

    /// Get current state snapshot.
    public func getState() -> PeerManagerState {
        state
    }

    /// Return the durable X25519 identity shared by LAN pairing and sync.
    public func localSyncIdentity(deviceId: String) throws -> SyncDeviceIdentity {
        try identityStore.loadOrCreateIdentity(deviceId: deviceId)
    }

    // MARK: - Lifecycle

    /// Start the P2P sync system: sync server, mDNS, Multipeer, polling loops.
    public func startPeerSync(
        deviceId: String,
        deviceName: String,
        companyId: String,
        allowAnyCompanyPeerDiscovery: Bool = false,
        startMultipeer: Bool = true,
        startSyncServer: Bool = true
    ) async throws {
        guard !state.running else { return }

        // 0. Load or create the persistent X25519 identity for this device.
        let identity = try identityStore.loadOrCreateIdentity(deviceId: deviceId)
        kaPrivateKeyB64 = identity.privateKeyB64
        kaPublicKeyB64 = identity.publicKeyB64
        self.companyId = companyId          // Fix #191: stored for key-exchange requests
        peerKAPublicKeys.removeAll()

        // 1. Start LAN sync server unless this is discovery-only onboarding.
        let port: UInt16
        if startSyncServer {
            let sState = SyncServerState(
                deviceId: deviceId,
                deviceName: deviceName,
                companyId: companyId,
                db: db,
                identity: identity
            )
            self.serverState = sState
            self.kaPrivateKeyB64 = sState.kaPrivateKeyB64
            self.kaPublicKeyB64 = sState.kaPublicKeyB64

            let server = LanSyncServer(state: sState)
            port = try await server.start()
            self.syncServer = server
        } else {
            self.serverState = nil
            self.syncServer = nil
            port = 0
        }

        state.running = true
        state.syncPort = port
        notifyStateChanged()

        // 2. Start mDNS discovery
        let discovery = PeerDiscovery(
            deviceId: deviceId,
            companyId: companyId,
            deviceName: deviceName,
            port: port,
            allowAnyCompanyPeerDiscovery: allowAnyCompanyPeerDiscovery,
            advertiseSelf: startSyncServer
        )
        discovery.onPeersChanged = { [weak self] peers in
            guard let self else { return }
            Task { await self.handleLanPeersChanged(peers) }
        }
        discovery.start()
        self.peerDiscovery = discovery

        // 3. Start Multipeer Connectivity (Apple platforms)
        #if canImport(MultipeerConnectivity)
        if startMultipeer {
            let mpManager = MultipeerManager(
                deviceId: deviceId,
                deviceName: deviceName,
                companyId: companyId,
                allowAnyCompanyPeerDiscovery: allowAnyCompanyPeerDiscovery,
                autoInvitePeers: startSyncServer,
                advertiseSelf: startSyncServer
            )
            mpManager.onPeersChanged = { [weak self] _ in
                guard let self else { return }
                Task { await self.mergePeerLists() }
            }
            mpManager.onDataReceived = { [weak self] _ in
                guard let self else { return }
                // MultipeerManager owns a serial FIFO receive queue. Drain that queue
                // from this actor so change batches cannot be reordered by independent Tasks.
                Task { await self.drainMultipeerMessages() }
            }
            mpManager.start()
            self.multipeerManager = mpManager
        }
        #endif

        // 4. Start peer poll loop (every 10 seconds)
        peerPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self else { break }
                await self.mergePeerLists()
            }
        }

        // 5. Start inbox processing loop (every 5 seconds)
        inboxProcessTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { break }
                await self.processInbox()
            }
        }

        // Initial peer list merge
        mergePeerLists()
    }

    /// Stop the P2P sync system.
    public func stopPeerSync() async {
        peerPollTask?.cancel()
        peerPollTask = nil
        inboxProcessTask?.cancel()
        inboxProcessTask = nil

        peerDiscovery?.stop()
        peerDiscovery = nil

        #if canImport(MultipeerConnectivity)
        failPendingMultipeerOperations(with: MultipeerPairingError.transportStopped)
        multipeerManager?.stop()
        multipeerManager = nil
        #endif

        await syncServer?.stop()
        syncServer = nil
        serverState = nil

        state = PeerManagerState()
        notifyStateChanged()
    }

    /// Stop only the Multipeer Connectivity transport while preserving LAN discovery/sync.
    ///
    /// Used when the app-level Bluetooth setting is disabled while peer sync is
    /// already running. LAN discovery and the sync server should continue, but
    /// Bluetooth/Wi-Fi P2P advertising and browsing must stop immediately.
    public func stopMultipeerDiscovery() async {
        #if canImport(MultipeerConnectivity)
        failPendingMultipeerOperations(with: MultipeerPairingError.transportStopped)
        multipeerManager?.stop()
        multipeerManager = nil
        #endif

        state.peers.removeAll { $0.transport == "multipeer" }
        notifyStateChanged()
    }

    #if canImport(MultipeerConnectivity)
    private func failPendingMultipeerOperations(with error: Error) {
        let pairContinuations = pendingPairContinuations.values.map(\.continuation)
        pendingPairContinuations.removeAll()
        pendingBluetoothPairingContexts.removeAll()
        let fullSyncContinuations = Array(pendingFullSyncContinuations.values)
        pendingFullSyncContinuations.removeAll()
        pendingSnapshotChanges.removeAll()
        failedSnapshotPeers.removeAll()

        for continuation in pairContinuations {
            continuation.resume(throwing: error)
        }
        for continuation in fullSyncContinuations {
            continuation.resume(throwing: error)
        }

        // A reservation is retryable only until completion has been sent. Once
        // rowsSent is set, the snapshot capability has crossed the no-replay
        // boundary and transport shutdown must discard it rather than reissue it.
        for (peerDeviceId, reservation) in hostedSnapshotReservations where reservation.rowsSent == nil {
            hostedSnapshotTokens[peerDeviceId] = reservation.authorizationToken
        }
        hostedSnapshotReservations.removeAll()
        inFlightPairRequests.removeAll()
        inFlightFullSyncRequests.removeAll()
        isDrainingMultipeerMessages = false
    }
    #endif

    // MARK: - Peer Discovery Merging

    private func handleLanPeersChanged(_ peers: [DiscoveredPeer]) {
        // Merge will be called by the poll loop
    }

    /// Merge LAN and Multipeer peer lists, deduplicating by device_id.
    /// LAN is preferred when a device appears in both.
    private func mergePeerLists() {
        var merged: [String: DiscoveredPeer] = [:]

        // LAN peers (preferred)
        if let lanPeers = peerDiscovery?.getPeers() {
            for peer in lanPeers {
                merged[peer.deviceId] = peer
            }
        }

        // Multipeer peers (only if not already found via LAN)
        #if canImport(MultipeerConnectivity)
        if let mpPeers = multipeerManager?.getPeers() {
            for mp in mpPeers {
                if merged[mp.deviceId] == nil {
                    let peer = DiscoveredPeer(
                        deviceId: mp.deviceId,
                        deviceName: mp.deviceName,
                        companyId: mp.companyId,
                        host: "",
                        port: 0,
                        transport: "multipeer",
                        multipeerState: mp.state.rawValue
                    )
                    merged[mp.deviceId] = peer
                }
            }
        }
        #endif

        state.peers = Array(merged.values)
        notifyStateChanged()
    }

    // MARK: - Sync With Peer

    /// Sync with a specific peer via LAN HTTP.
    public func syncWithPeer(_ peer: DiscoveredPeer) async -> PeerSyncResult {
        // #1417 hardening part 2: a peer that paired but has NOT completed its
        // initial snapshot (its hosted token is still outstanding — consumed
        // only on durable apply acknowledgement) must not receive incremental
        // change-log pushes. Loose records mean nothing on an empty database,
        // and recording "Sent N records" made the owner's failed field join
        // look like a success. Skip quietly; pushes resume the moment the
        // snapshot acknowledges. lastPeerSyncs is deliberately NOT updated —
        // neither a fake success nor a scary "failed" belongs in the UI.
        if hostedSnapshotTokens[peer.deviceId] != nil {
            logger.info("[PeerManager] Deferring incremental push to \(String(peer.deviceId.prefix(8)), privacy: .public) — initial snapshot not yet acknowledged")
            return PeerSyncResult(
                peerDeviceId: peer.deviceId,
                peerName: peer.deviceName,
                success: false,
                error: "Waiting for the new device's initial download to finish."
            )
        }
        state.syncingWith = peer.deviceId
        notifyStateChanged()

        defer {
            state.syncingWith = nil
            notifyStateChanged()
        }

        guard let sState = serverState else {
            let result = PeerSyncResult(
                peerDeviceId: peer.deviceId,
                peerName: peer.deviceName,
                success: false,
                error: "Sync server not running"
            )
            state.lastPeerSyncs[peer.deviceId] = result
            return result
        }

        let deviceId = sState.deviceId
        let companyId = sState.companyId

        do {
            // Get pending changes
            let pendingChanges = try ChangeTracker.getPendingChanges(db: db)
            let enrichedChanges = try enrichChangesWithData(pendingChanges)

            var pushed = 0
            var pulled = 0

            #if canImport(MultipeerConnectivity)
            if peer.transport == "multipeer", let mpManager = multipeerManager {
                // Bluetooth/Multipeer path. If the session is still forming (user
                // tapped Sync during "connecting"), wait briefly for it instead of
                // falling through to the HTTP path — a multipeer-only peer has a
                // placeholder host, so HTTP could only throw badURL (-1000), which
                // is the raw error the owner hit from the Nearby Devices sheet.
                if !mpManager.isConnected(toPeer: peer.deviceId) {
                    _ = await awaitMultipeerConnection(to: peer.deviceId, using: mpManager)
                }
                guard mpManager.isConnected(toPeer: peer.deviceId) else {
                    let result = PeerSyncResult(
                        peerDeviceId: peer.deviceId,
                        peerName: peer.deviceName,
                        success: false,
                        error: "Still connecting to \(peer.deviceName) over Bluetooth — try again in a moment."
                    )
                    state.lastPeerSyncs[peer.deviceId] = result
                    return result
                }
                if !enrichedChanges.isEmpty {
                    let encoder = JSONEncoder()
                    let changesData = try encoder.encode(enrichedChanges)
                    let payload = try encoder.encode(MPEnvelope(type: "changes", payload: changesData))
                    // A failed send used to fall through to success:true with
                    // pushed:0 — indistinguishable from a real sync in the UI
                    // (audit 2026-08-03, same dishonesty class as #1625).
                    guard mpManager.send(data: payload, toPeer: peer.deviceId) else {
                        throw MultipeerPairingError.sendFailed
                    }
                    do {
                        pushed = enrichedChanges.count
                        let syncedIds = pendingChanges.compactMap { $0.id }
                        try ChangeTracker.markSynced(
                            db: db,
                            ids: syncedIds,
                            batchId: "mp-\(Int(Date().timeIntervalSince1970))"
                        )
                    }
                }
            } else {
                // LAN HTTP sync path
                (pushed, pulled) = try await syncViaHTTP(
                    peer: peer,
                    deviceId: deviceId,
                    companyId: companyId,
                    pendingChanges: pendingChanges,
                    enrichedChanges: enrichedChanges
                )
            }
            #else
            // LAN HTTP sync path (non-Apple platforms)
            (pushed, pulled) = try await syncViaHTTP(
                peer: peer,
                deviceId: deviceId,
                companyId: companyId,
                pendingChanges: pendingChanges,
                enrichedChanges: enrichedChanges
            )
            #endif

            // Update peer sync time
            try ChangeTracker.updatePeerSyncTime(db: db, peerId: peer.deviceId)

            let result = PeerSyncResult(
                peerDeviceId: peer.deviceId,
                peerName: peer.deviceName,
                pushed: pushed,
                pulled: pulled,
                success: true
            )
            state.lastPeerSyncs[peer.deviceId] = result
            return result

        } catch {
            let result = PeerSyncResult(
                peerDeviceId: peer.deviceId,
                peerName: peer.deviceName,
                success: false,
                error: error.localizedDescription
            )
            state.lastPeerSyncs[peer.deviceId] = result
            return result
        }
    }

    /// Sync with one currently discovered peer by stable device ID.
    ///
    /// Row-level UI actions should use this selector instead of `syncWithAllPeers()`
    /// so tapping one peer cannot fan out to every known peer.
    public func syncWithPeer(deviceId: String) async -> PeerSyncResult {
        mergePeerLists()

        guard let peer = state.peers.first(where: { $0.deviceId == deviceId }) else {
            let result = PeerSyncResult(
                peerDeviceId: deviceId,
                peerName: deviceId,
                success: false,
                error: "Peer not found: \(deviceId)"
            )
            state.lastPeerSyncs[deviceId] = result
            notifyStateChanged()
            return result
        }

        return await syncWithPeer(peer)
    }

    /// Sync with all discovered peers sequentially.
    /// Office-like peers first, then by least-recently-synced.
    public func syncWithAllPeers() async -> [PeerSyncResult] {
        var results: [PeerSyncResult] = []

        let sorted = state.peers.sorted { a, b in
            let aIsOffice = Self.isOfficePeer(a)
            let bIsOffice = Self.isOfficePeer(b)
            if aIsOffice && !bIsOffice { return true }
            if !aIsOffice && bIsOffice { return false }

            let aLastSync = state.lastPeerSyncs[a.deviceId]?.syncedAt ?? ""
            let bLastSync = state.lastPeerSyncs[b.deviceId]?.syncedAt ?? ""
            return aLastSync < bLastSync
        }

        for peer in sorted {
            // Skip unconnected Multipeer peers
            if peer.transport == "multipeer" && peer.multipeerState != "connected" {
                continue
            }
            let result = await syncWithPeer(peer)
            results.append(result)
        }

        return results
    }

    /// Refresh the sync server's outbox with current pending changes.
    public func refreshOutbox() async throws {
        guard let sState = serverState else { return }

        let pendingChanges = try ChangeTracker.getPendingChanges(db: db)
        let enriched = try enrichChangesWithData(pendingChanges)
        await sState.setOutbox(enriched)
    }

    /// Issue a one-time pairing code on the running shop sync server.
    public func issuePairingCode() async throws -> String {
        guard let sState = serverState else {
            throw SyncServerError.serverNotRunning
        }
        return try await sState.issueActivePairingCode()
    }

    /// Clear any active pairing code on the running shop sync server.
    public func clearPairingCode() async {
        await serverState?.clearActivePairingCode()
        setBluetoothPairingHostMode(false)
    }

    /// Host: allow cross-company Bluetooth connections while a pairing code is
    /// offered, so a not-yet-in-company device can connect to complete the code
    /// handshake over Bluetooth. Enable when issuing a code; disable when cleared.
    public func setBluetoothPairingHostMode(_ enabled: Bool) {
        #if canImport(MultipeerConnectivity)
        multipeerManager?.setAcceptAnyCompanyForPairing(enabled)
        #endif
    }

    // MARK: - Private: LAN HTTP Sync

    private func syncViaHTTP(
        peer: DiscoveredPeer,
        deviceId: String,
        companyId: String,
        pendingChanges: [ChangeLogEntry],
        enrichedChanges: [IncomingChange]
    ) async throws -> (pushed: Int, pulled: Int) {
        var pushed = 0
        var pulled = 0

        let baseURL = try Self.makeLANSyncBaseURL(for: peer)
        let lastSyncAt = state.lastPeerSyncs[peer.deviceId]?.syncedAt

        // Resolve shared key for this peer (fetches /sync/key once then caches)
        let sharedKeyData = try await resolveSharedKey(
            baseURL: baseURL,
            peerDeviceId: peer.deviceId,
            localDeviceId: deviceId
        )

        // 1. Push our changes
        if !enrichedChanges.isEmpty {
            let pushRequest = SyncPushRequest(
                deviceId: deviceId,
                companyId: companyId,
                lastSyncAt: lastSyncAt,
                changes: enrichedChanges
            )

            let encoder = JSONEncoder()
            let plainPushBody = try encoder.encode(pushRequest)

            let pushURL = baseURL.appendingPathComponent("sync/push")
            var urlRequest = URLRequest(url: pushURL)
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = 30
            let pushRequestId = UUID().uuidString
            try applyPayload(
                &urlRequest,
                plain: plainPushBody,
                sharedKeyData: sharedKeyData,
                localDeviceId: deviceId,
                endpoint: "push",
                requestId: pushRequestId
            )

            let (pushData, pushResp) = try await URLSession.shared.data(for: urlRequest)
            try Self.validateSyncHTTPResponse(pushResp, endpoint: "push")
            let plainPushData = try decrypt(
                pushData,
                sharedKeyData: sharedKeyData,
                endpoint: "push",
                requestId: pushRequestId,
                localDeviceId: deviceId
            )
            let result = try JSONDecoder().decode(SyncPushResponse.self, from: plainPushData)
            pushed = result.accepted
            let syncedIds = pendingChanges.compactMap { $0.id }
            try ChangeTracker.markSynced(db: db, ids: syncedIds, batchId: result.syncBatchId)
        }

        // 2. Pull peer's changes
        let vectorClock = try ChangeTracker.getVectorClock(db: db, deviceId: deviceId)
        let pullRequest = SyncPullRequest(
            deviceId: deviceId,
            companyId: companyId,
            lastSyncAt: lastSyncAt,
            vectorClock: vectorClock
        )

        let plainPullBody = try JSONEncoder().encode(pullRequest)
        let pullURL = baseURL.appendingPathComponent("sync/pull")
        var pullURLRequest = URLRequest(url: pullURL)
        pullURLRequest.httpMethod = "POST"
        pullURLRequest.timeoutInterval = 30
        let pullRequestId = UUID().uuidString
        try applyPayload(
            &pullURLRequest,
            plain: plainPullBody,
            sharedKeyData: sharedKeyData,
            localDeviceId: deviceId,
            endpoint: "pull",
            requestId: pullRequestId
        )

        let (pullData, pullResp) = try await URLSession.shared.data(for: pullURLRequest)
        try Self.validateSyncHTTPResponse(pullResp, endpoint: "pull")
        let plainPullData = try decrypt(
            pullData,
            sharedKeyData: sharedKeyData,
            endpoint: "pull",
            requestId: pullRequestId,
            localDeviceId: deviceId
        )
        let result = try JSONDecoder().decode(SyncPullResponse.self, from: plainPullData)
        pulled = result.changes.count

        if !result.changes.isEmpty {
            _ = try ConflictResolver.resolveAndApplyChanges(
                db: db,
                changes: result.changes,
                localDeviceId: deviceId
            )

            // Update vector clock with highest sequence from this peer
            let maxSeq = result.changes.compactMap { $0.id }.max() ?? 0
            if maxSeq > 0 {
                try ChangeTracker.updateVectorClock(
                    db: db,
                    peerId: result.serverDeviceId,
                    lastSequence: maxSeq,
                    deviceId: deviceId
                )
            }
        }

        return (pushed, pulled)
    }

    private static func validateSyncHTTPResponse(_ response: URLResponse, endpoint: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PeerSyncHTTPError.nonHTTPResponse(endpoint: endpoint)
        }
        guard httpResponse.statusCode == 200 else {
            throw PeerSyncHTTPError.httpError(endpoint: endpoint, statusCode: httpResponse.statusCode)
        }
    }

    static func makeLANSyncBaseURL(for peer: DiscoveredPeer) throws -> URL {
        let trimmedHost = peer.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, peer.port > 0 else {
            throw URLError(.badURL)
        }
        guard !trimmedHost.hasPrefix("WiredPart-") || trimmedHost.contains(".") else {
            throw URLError(.badURL)
        }

        let normalized = normalizedLANHostAndPort(trimmedHost, fallbackPort: peer.port)

        var components = URLComponents()
        components.scheme = "http"
        components.host = normalized.host
        components.port = Int(normalized.port)

        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }

    private static func normalizedLANHostAndPort(
        _ rawHost: String,
        fallbackPort: UInt16
    ) -> (host: String, port: UInt16) {
        if let components = URLComponents(string: rawHost),
           components.scheme != nil,
           let host = components.host {
            return (host: host, port: normalizedPort(components.port, fallback: fallbackPort))
        }

        if let components = URLComponents(string: "http://\(rawHost)"),
           let host = components.host {
            return (host: host, port: normalizedPort(components.port, fallback: fallbackPort))
        }

        if rawHost.hasPrefix("[") {
            return (host: rawHost, port: fallbackPort)
        }

        if rawHost.contains(":") {
            let escapedZone = rawHost.replacingOccurrences(of: "%", with: "%25")
            return (host: "[\(escapedZone)]", port: fallbackPort)
        }

        return (host: rawHost, port: fallbackPort)
    }

    private static func normalizedPort(_ port: Int?, fallback: UInt16) -> UInt16 {
        guard let port, let exact = UInt16(exactly: port) else {
            return fallback
        }
        return exact
    }

    // MARK: - Private: Payload Encryption Helpers

    /// Fetch the peer's X25519 KA public key from GET /sync/key (cached).
    /// Every LAN sync requires a negotiated shared key; failures abort the sync.
    private func resolveSharedKey(
        baseURL: URL,
        peerDeviceId: String,
        localDeviceId: String
    ) async throws -> Data {
        // Use cached peer KA public key if available
        let peerKAKey: String
        if let cached = peerKAPublicKeys[peerDeviceId], !cached.isEmpty {
            peerKAKey = cached
        } else {
            peerKAKey = try await fetchPeerKAPublicKey(
                baseURL: baseURL,
                peerDeviceId: peerDeviceId,
                localDeviceId: localDeviceId
            )
        }
        guard !peerKAKey.isEmpty, !kaPrivateKeyB64.isEmpty else {
            throw PeerSyncHTTPError.malformedResponse(endpoint: "key")
        }
        return try SyncCrypto.deriveSharedKeyData(
            ourPrivateKeyB64: kaPrivateKeyB64,
            theirPublicKeyB64: peerKAKey
        )
    }

    /// Call GET /sync/key on the peer to get their X25519 KA public key.
    /// Returns the key if successful. There is no plaintext downgrade path.
    /// Transport, authorization, and malformed-response failures propagate so a
    /// failed key exchange can never silently downgrade a capable peer to plaintext.
    /// Fixes #191: sends X-Company-ID header so the server can reject unknown peers.
    private func fetchPeerKAPublicKey(
        baseURL: URL,
        peerDeviceId: String,
        localDeviceId: String
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("sync/key")
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        // Fix #191: identify our company so the server can gate key exchange to known peers.
        if !companyId.isEmpty {
            req.setValue(companyId, forHTTPHeaderField: "X-Company-ID")
        }
        req.setValue(localDeviceId, forHTTPHeaderField: "X-Sync-Device-ID")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PeerSyncHTTPError.nonHTTPResponse(endpoint: "key")
        }
        guard httpResponse.statusCode == 200 else {
            throw PeerSyncHTTPError.httpError(endpoint: "key", statusCode: httpResponse.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(SyncKeyResponse.self, from: data),
              !decoded.key.isEmpty else {
            throw PeerSyncHTTPError.malformedResponse(endpoint: "key")
        }
        guard try trustedPeerKey(deviceId: peerDeviceId) == decoded.key else {
            throw PeerSyncHTTPError.malformedResponse(endpoint: "key")
        }
        peerKAPublicKeys[peerDeviceId] = decoded.key
        return decoded.key
    }

    private func trustedPeerKey(deviceId: String) throws -> String? {
        let encoded = try db.writer.read { dbConn in
            try String.fetchOne(
                dbConn,
                sql: "SELECT certificate FROM _device_registry WHERE device_id = ? AND is_trusted = 1 AND is_deactivated = 0",
                arguments: [deviceId]
            )
        }
        guard let encoded, encoded.hasPrefix("x25519:") else { return nil }
        let key = String(encoded.dropFirst("x25519:".count))
        guard Data(base64Encoded: key)?.count == 32 else { return nil }
        return key
    }

    /// Attach an encrypted body + key-agreement headers to a URLRequest.
    private func applyPayload(
        _ request: inout URLRequest,
        plain: Data,
        sharedKeyData: Data,
        localDeviceId: String,
        endpoint: String,
        requestId: String
    ) throws {
        let encrypted = try SyncCrypto.encryptAESGCM(
            data: plain,
            keyData: sharedKeyData,
            aad: LanSyncServer.syncAAD(
                endpoint: endpoint,
                direction: "request",
                deviceId: localDeviceId,
                requestId: requestId
            )
        )
        request.httpBody = encrypted
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-Sync-Encrypted")
        request.setValue(kaPublicKeyB64, forHTTPHeaderField: "X-Sync-Sender-Key")
        request.setValue(localDeviceId, forHTTPHeaderField: "X-Sync-Device-ID")
        request.setValue(requestId, forHTTPHeaderField: "X-Sync-Request-ID")
    }

    /// Decrypt a response body if a shared key was used for this request.
    private func decrypt(
        _ data: Data,
        sharedKeyData: Data,
        endpoint: String,
        requestId: String,
        localDeviceId: String
    ) throws -> Data {
        try SyncCrypto.decryptAESGCM(
            data: data,
            keyData: sharedKeyData,
            aad: LanSyncServer.syncAAD(
                endpoint: endpoint,
                direction: "response",
                deviceId: localDeviceId,
                requestId: requestId
            )
        )
    }

    // MARK: - Private: Inbox Processing

    /// Process changes received by our sync server from peers who pushed to us.
    private func processInbox() async {
        guard let sState = serverState else { return }
        let inbox = await sState.drainInbox()
        guard !inbox.isEmpty else { return }

        let deviceId = sState.deviceId

        do {
            _ = try ConflictResolver.resolveAndApplyChanges(
                db: db,
                changes: inbox,
                localDeviceId: deviceId
            )
        } catch {
            // Non-critical — changes will be retried on next sync
        }
    }

    // MARK: - Private: Multipeer Message Handling

    #if canImport(MultipeerConnectivity)
    /// Whether a peer may WRITE company data to this device.
    ///
    /// A peer qualifies while it is trusted and not deactivated, OR while we
    /// are mid-onboarding against it as our snapshot host (the host sends the
    /// initial company snapshot as `changes` frames before our own trust row
    /// for it is durable). Anything else is rejected — discovery is
    /// deliberately open, writes never are.
    func isTrustedWritePeer(_ peerDeviceId: String) -> Bool {
        if (try? isTrustedBluetoothPeer(peerDeviceId)) == true { return true }
        // In-flight initial snapshot from the host we are joining.
        return pendingSnapshotChanges[peerDeviceId] != nil
            || receivedSnapshotTokens[peerDeviceId] != nil
    }

    func isTrustedBluetoothPeer(_ peerDeviceId: String) throws -> Bool {
        try db.writer.read { dbConn in
            try Bool.fetchOne(
                dbConn,
                sql: "SELECT is_trusted = 1 AND is_deactivated = 0 FROM _device_registry WHERE device_id = ?",
                arguments: [peerDeviceId]
            ) ?? false
        }
    }

    private func drainMultipeerMessages() async {
        guard let mpManager = multipeerManager else { return }
        // Actor methods are reentrant at `await` points. Multiple receive callbacks
        // can therefore enter this method while an earlier pairing/snapshot message
        // is suspended. Keep exactly one queue consumer so later envelopes cannot
        // overtake the message currently being processed.
        guard !isDrainingMultipeerMessages else { return }
        isDrainingMultipeerMessages = true
        defer { isDrainingMultipeerMessages = false }

        while let message = mpManager.popReceivedMessage() {
            do {
                _ = try await processMultipeerMessage(message)
            } catch {
                failPendingFullSync(from: message.fromDeviceId, with: error)
                logger.error(
                    "Bluetooth message from \(String(message.fromDeviceId.prefix(8)), privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Process one FIFO message and do not return until any database application is durable.
    /// Internal visibility supports deterministic ordering/failure regression tests.
    func processMultipeerMessage(
        _ message: ReceivedMultipeerMessage,
        sendApplyAcknowledgement: ((FullSyncApplyAcknowledgement, String) -> Bool)? = nil
    ) async throws -> MultipeerMessageOutcome {
        if let env = try? JSONDecoder().decode(MPEnvelope.self, from: message.data) {
            if failedSnapshotPeers.contains(message.fromDeviceId),
               env.type == "changes" || env.type == "fullSyncComplete" {
                return .ignored
            }
            switch env.type {
            case "changes":
                // SECURITY (audit 2026-08-03): company data may only be written
                // by a peer that completed pairing and is still trusted.
                // handleFullSyncRequest checked this; the write paths did not —
                // and MultipeerManager auto-accepts any invitation asserting our
                // company_id, which is broadcast in cleartext in the Bonjour TXT
                // record. Any nearby device could therefore INSERT/UPDATE/DELETE
                // in every allowed table without ever pairing.
                guard isTrustedWritePeer(message.fromDeviceId) else {
                    logger.error("[PeerManager] Rejected changes from untrusted peer \(String(message.fromDeviceId.prefix(8)), privacy: .public)")
                    return .ignored
                }
                do {
                    let changes = try decodeIncomingChanges(env.payload)
                    let count: Int
                    if pendingSnapshotChanges[message.fromDeviceId] != nil {
                        pendingSnapshotChanges[message.fromDeviceId, default: []]
                            .append(contentsOf: changes)
                        count = changes.count
                    } else {
                        count = try applyIncomingChanges(changes)
                    }
                    return .changesApplied(count)
                } catch {
                    sendFullSyncApplyAcknowledgement(
                        succeeded: false,
                        error: error.localizedDescription,
                        to: message.fromDeviceId
                    )
                    throw error
                }
            case "pairRequest":
                await handlePairRequest(from: message.fromDeviceId, payload: env.payload)
                return .pairRequest
            case "pairResponse":
                handlePairResponse(from: message.fromDeviceId, payload: env.payload)
                return .pairResponse
            case "fullSyncRequest":
                let request = try JSONDecoder().decode(FullSyncRequest.self, from: env.payload)
                await handleFullSyncRequest(
                    from: message.fromDeviceId,
                    authorizationToken: request.authorizationToken
                )
                return .fullSyncRequest
            case "fullSyncComplete":
                let completion: FullSyncCompletion
                if env.payload.isEmpty {
                    completion = .success // Backward compatibility with pre-integrity hosts.
                } else {
                    completion = try JSONDecoder().decode(FullSyncCompletion.self, from: env.payload)
                }
                guard completion.succeeded else {
                    throw MultipeerSnapshotError.remoteFailure(completion.error ?? "")
                }
                if pendingSnapshotChanges[message.fromDeviceId] != nil {
                    do {
                        _ = try applyIncomingChanges(
                            pendingSnapshotChanges[message.fromDeviceId, default: []]
                        )
                    } catch {
                        // Tell the host before the FIFO drain propagates the local
                        // failure. The host can then consume the old capability and
                        // release its reservation immediately instead of timing out.
                        sendFullSyncApplyAcknowledgement(
                            succeeded: false,
                            error: error.localizedDescription,
                            to: message.fromDeviceId,
                            using: sendApplyAcknowledgement
                        )
                        throw error
                    }
                }
                if pendingFullSyncContinuations[message.fromDeviceId] != nil {
                    guard sendFullSyncApplyAcknowledgement(
                        succeeded: true,
                        error: nil,
                        to: message.fromDeviceId,
                        using: sendApplyAcknowledgement
                    ) else {
                        throw MultipeerPairingError.sendFailed
                    }
                    receivedSnapshotTokens.removeValue(forKey: message.fromDeviceId)
                }
                pendingSnapshotChanges.removeValue(forKey: message.fromDeviceId)
                failedSnapshotPeers.remove(message.fromDeviceId)
                handleFullSyncComplete(from: message.fromDeviceId)
                return .fullSyncCompleted
            case "fullSyncApplied":
                let acknowledgement = try JSONDecoder().decode(
                    FullSyncApplyAcknowledgement.self,
                    from: env.payload
                )
                handleFullSyncApplyAcknowledgement(
                    acknowledgement,
                    from: message.fromDeviceId
                )
                return .ignored
            default:
                return .ignored
            }
        }

        // Legacy senders used a bare [IncomingChange] JSON array. Same trust
        // gate as the enveloped path above — this is a write path.
        guard isTrustedWritePeer(message.fromDeviceId) else {
            logger.error("[PeerManager] Rejected legacy changes payload from untrusted peer \(String(message.fromDeviceId.prefix(8)), privacy: .public)")
            return .ignored
        }
        guard !failedSnapshotPeers.contains(message.fromDeviceId) else { return .ignored }
        let changes = try decodeIncomingChanges(message.data)
        let count: Int
        if pendingSnapshotChanges[message.fromDeviceId] != nil {
            pendingSnapshotChanges[message.fromDeviceId, default: []]
                .append(contentsOf: changes)
            count = changes.count
        } else {
            count = try applyIncomingChanges(changes)
        }
        return .changesApplied(count)
    }

    /// Host side: a freshly-paired joiner asked for the whole company.
    ///
    /// Streams a **full snapshot of every synced business table** — not the change
    /// log. Change-tracking here is explicit, and the foundational records
    /// (admin user from `seedFirstAdmin`, business profile, company settings) are
    /// written WITHOUT change-logging, so a change-log replay left the joiner with
    /// data but no users ("No User Found"). A row snapshot is also what the Wi-Fi
    /// full-download does, so both transports now deliver the same result.
    ///
    /// Tables stream in creation (migration) order, which approximates dependency
    /// order for any FK constraints. Device-scoped settings rows are excluded so
    /// the host's pairing/device config never clobbers the joiner's.
    private func handleFullSyncRequest(
        from peerDeviceId: String,
        authorizationToken: String
    ) async {
        guard let mpManager = multipeerManager, let sState = serverState else { return }
        let hostDeviceId = sState.deviceId
        let fallbackTimestamp = CoreFormatters.nowISO()
        let peerName = state.peers.first(where: { $0.deviceId == peerDeviceId })?.deviceName ?? "New device"

        // Cross-company discovery is deliberately open while hosting a pairing
        // code, but company data is not. Only a device that completed pairing and
        // remains trusted/non-deactivated may request the initial snapshot.
        let isTrusted = (try? isTrustedBluetoothPeer(peerDeviceId)) ?? false
        let expectedToken = hostedSnapshotTokens[peerDeviceId]
        if hasHostedSnapshotReservation(
            for: peerDeviceId,
            requestToken: authorizationToken
        ) {
            // Any second request while this peer's transfer is reserved is duplicate
            // traffic. In particular, a mismatched token must not inject a failure
            // completion into the joiner's valid in-flight continuation.
            logger.info("[PeerManager] Ignored duplicate in-flight snapshot request from \(String(peerDeviceId.prefix(8)), privacy: .public)")
            return
        }
        guard BluetoothSnapshotAuthorization.isAuthorized(
            trustedDevice: isTrusted,
            providedToken: authorizationToken,
            expectedToken: expectedToken
        ) else {
            let error = MultipeerSnapshotError.unauthorizedPeer
            _ = try? sendFullSyncCompletion(.failure(error), to: peerDeviceId, using: mpManager)
            state.lastPeerSyncs[peerDeviceId] = PeerSyncResult(
                peerDeviceId: peerDeviceId,
                peerName: peerName,
                success: false,
                error: error.localizedDescription
            )
            logger.error("[PeerManager] Rejected full Bluetooth snapshot request from untrusted peer \(String(peerDeviceId.prefix(8)), privacy: .public)")
            return
        }
        // Reserve the one-time capability before the first suspension. It is not
        // consumed until the joiner acknowledges durable database application.
        guard reserveHostedSnapshot(
            peerDeviceId: peerDeviceId,
            peerName: peerName,
            authorizationToken: authorizationToken
        ) else { return }

        // Host-side feedback: surface "syncing with <peer>" to the UI.
        state.syncingWith = peerDeviceId
        notifyStateChanged()
        defer {
            state.syncingWith = nil
            notifyStateChanged()
        }

        do {
            let totalSent = try await BluetoothSnapshotTransfer.run(
                listTables: { [db] in
                    try await db.writer.read { dbConn in
                        try String.fetchAll(
                            dbConn,
                            sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY rowid"
                        )
                    }
                },
                readPage: { [db] table, limit, offset in
                    try await Self.hostedSnapshotPage(
                        db: db, table: table, limit: limit, offset: offset,
                        hostDeviceId: hostDeviceId, fallbackTimestamp: fallbackTimestamp
                    )
                },
                encode: { changes in
                    let changesData = try JSONEncoder().encode(changes)
                    return try JSONEncoder().encode(MPEnvelope(type: "changes", payload: changesData))
                },
                send: { data in mpManager.send(data: data, toPeer: peerDeviceId) }
            )

            guard try sendFullSyncCompletion(.success, to: peerDeviceId, using: mpManager) else {
                hostedSnapshotReservations.removeValue(forKey: peerDeviceId)
                throw BluetoothSnapshotTransferError.completionSendFailed
            }
            hostedSnapshotReservations[peerDeviceId]?.rowsSent = totalSent
            scheduleSnapshotAcknowledgementTimeout(
                peerDeviceId: peerDeviceId,
                authorizationToken: authorizationToken
            )
            logger.info("[PeerManager] Sent full Bluetooth snapshot (\(totalSent) records); awaiting durable apply acknowledgement from \(String(peerDeviceId.prefix(8)), privacy: .public)")
        } catch {
            if Self.shouldRestoreHostedSnapshot(after: error) {
                restoreHostedSnapshot(
                    peerDeviceId: peerDeviceId,
                    authorizationToken: authorizationToken
                )
            }
            _ = try? sendFullSyncCompletion(.failure(error), to: peerDeviceId, using: mpManager)
            state.lastPeerSyncs[peerDeviceId] = PeerSyncResult(
                peerDeviceId: peerDeviceId,
                peerName: peerName,
                success: false,
                error: error.localizedDescription
            )
            logger.error("[PeerManager] Full Bluetooth snapshot failed for peer \(String(peerDeviceId.prefix(8)), privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// One page of the hosted initial snapshot. Internal + static so the
    /// id-less-table guard is directly testable.
    ///
    /// Field P0 (owner, 2026-08-02, build 44): the snapshot died 5-8s into
    /// every attempt — warehouse_user_positions is in allowedSyncTables but
    /// has NO id column, and the row loop threw missingRecordID for it,
    /// aborting the WHOLE company transfer. Migration 112's trigger installer
    /// skips id-less tables; the snapshot must too (they cannot participate
    /// in id-based sync at all). Checked once per table at offset 0.
    static func hostedSnapshotPage(
        db: AppDatabase,
        table: String,
        limit: Int,
        offset: Int,
        hostDeviceId: String,
        fallbackTimestamp: String
    ) async throws -> BluetoothSnapshotPage {
        if offset == 0 {
            let columns = try await db.writer.read { dbConn in
                try String.fetchAll(
                    dbConn, sql: "SELECT name FROM pragma_table_info(?)", arguments: [table]
                )
            }
            guard columns.contains("id") else {
                return BluetoothSnapshotPage(changes: [], sourceRowCount: 0)
            }
        }
        let rows = try await db.writer.read { dbConn in
            try Row.fetchAll(
                dbConn,
                sql: "SELECT * FROM [\(table)] ORDER BY rowid LIMIT ? OFFSET ?",
                arguments: [limit, offset]
            )
        }
        var changes: [IncomingChange] = []
        changes.reserveCapacity(rows.count)
        for row in rows {
            if table == "settings" {
                let key = (row["key"] as? String) ?? ""
                let category = row["category"] as String?
                if SettingsService.syncScope(for: key, category: category) == .device { continue }
            }

            guard let idValue = row["id"] as? Int64 else {
                throw MultipeerSnapshotError.missingRecordID(table: table)
            }
            let dict = Self.jsonRecordDict(from: row)
            guard JSONSerialization.isValidJSONObject(dict) else {
                throw MultipeerSnapshotError.rowEncodingFailed(table: table)
            }
            let jsonData = try JSONSerialization.data(withJSONObject: dict)
            guard let recordData = String(data: jsonData, encoding: .utf8) else {
                throw MultipeerSnapshotError.rowEncodingFailed(table: table)
            }
            changes.append(IncomingChange(
                deviceId: hostDeviceId,
                tableName: table,
                recordId: String(idValue),
                operation: "INSERT",
                recordData: recordData,
                timestamp: (row["updated_at"] as? String) ?? fallbackTimestamp
            ))
        }
        return BluetoothSnapshotPage(changes: changes, sourceRowCount: rows.count)
    }

    private func sendFullSyncCompletion(
        _ completion: FullSyncCompletion,
        to peerDeviceId: String,
        using manager: MultipeerManager
    ) throws -> Bool {
        let payload = try JSONEncoder().encode(completion)
        let envelope = try JSONEncoder().encode(MPEnvelope(type: "fullSyncComplete", payload: payload))
        return manager.send(data: envelope, toPeer: peerDeviceId)
    }

    internal static func shouldRestoreHostedSnapshot(after error: Error) -> Bool {
        guard let transferError = error as? BluetoothSnapshotTransferError else {
            return true
        }
        if case .completionSendFailed = transferError {
            return false
        }
        return true
    }

    @discardableResult
    private func sendFullSyncApplyAcknowledgement(
        succeeded: Bool,
        error: String?,
        to peerDeviceId: String,
        using sendOverride: ((FullSyncApplyAcknowledgement, String) -> Bool)? = nil
    ) -> Bool {
        guard pendingFullSyncContinuations[peerDeviceId] != nil,
              let authorizationToken = receivedSnapshotTokens[peerDeviceId] else {
            return false
        }
        let acknowledgement = FullSyncApplyAcknowledgement(
            authorizationToken: authorizationToken,
            succeeded: succeeded,
            error: error
        )
        if let sendOverride {
            return sendOverride(acknowledgement, peerDeviceId)
        }
        guard let manager = multipeerManager else { return false }
        guard let payload = try? JSONEncoder().encode(acknowledgement),
              let envelope = try? JSONEncoder().encode(
                MPEnvelope(type: "fullSyncApplied", payload: payload)
              ) else {
            return false
        }
        return manager.send(data: envelope, toPeer: peerDeviceId)
    }

    private func handleFullSyncApplyAcknowledgement(
        _ acknowledgement: FullSyncApplyAcknowledgement,
        from peerDeviceId: String
    ) {
        guard let reservation = hostedSnapshotReservations[peerDeviceId],
              reservation.authorizationToken == acknowledgement.authorizationToken else {
            logger.error("[PeerManager] Ignored stale or mismatched snapshot acknowledgement from \(String(peerDeviceId.prefix(8)), privacy: .public)")
            return
        }
        hostedSnapshotReservations.removeValue(forKey: peerDeviceId)

        if acknowledgement.succeeded, let rowsSent = reservation.rowsSent {
            state.lastPeerSyncs[peerDeviceId] = PeerSyncResult(
                peerDeviceId: peerDeviceId,
                peerName: reservation.peerName,
                pushed: rowsSent,
                success: true
            )
            logger.info("[PeerManager] Joiner durably applied full Bluetooth snapshot for \(String(peerDeviceId.prefix(8)), privacy: .public)")
        } else {
            state.lastPeerSyncs[peerDeviceId] = PeerSyncResult(
                peerDeviceId: peerDeviceId,
                peerName: reservation.peerName,
                success: false,
                error: acknowledgement.error ?? "The joiner did not apply the snapshot. Retry the sync."
            )
            logger.error("[PeerManager] Joiner rejected full Bluetooth snapshot; capability consumed after completion")
        }
        notifyStateChanged()
    }

    private func reserveHostedSnapshot(
        peerDeviceId: String,
        peerName: String,
        authorizationToken: String
    ) -> Bool {
        guard hostedSnapshotReservations[peerDeviceId] == nil,
              hostedSnapshotTokens[peerDeviceId] == authorizationToken else {
            return false
        }
        hostedSnapshotTokens.removeValue(forKey: peerDeviceId)
        hostedSnapshotReservations[peerDeviceId] = HostedSnapshotReservation(
            authorizationToken: authorizationToken,
            peerName: peerName,
            rowsSent: nil
        )
        return true
    }

    private func hasHostedSnapshotReservation(
        for peerDeviceId: String,
        requestToken _: String? = nil
    ) -> Bool {
        hostedSnapshotReservations[peerDeviceId] != nil
    }

    private func restoreHostedSnapshot(
        peerDeviceId: String,
        authorizationToken: String
    ) {
        guard hostedSnapshotReservations[peerDeviceId]?.authorizationToken == authorizationToken else {
            return
        }
        hostedSnapshotReservations.removeValue(forKey: peerDeviceId)
        hostedSnapshotTokens[peerDeviceId] = authorizationToken
    }

    private func scheduleSnapshotAcknowledgementTimeout(
        peerDeviceId: String,
        authorizationToken: String
    ) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            await self?.timeoutSnapshotAcknowledgement(
                peerDeviceId: peerDeviceId,
                authorizationToken: authorizationToken
            )
        }
    }

    private func timeoutSnapshotAcknowledgement(
        peerDeviceId: String,
        authorizationToken: String
    ) {
        guard let reservation = hostedSnapshotReservations[peerDeviceId],
              reservation.authorizationToken == authorizationToken else { return }
        hostedSnapshotReservations.removeValue(forKey: peerDeviceId)
        state.lastPeerSyncs[peerDeviceId] = PeerSyncResult(
            peerDeviceId: peerDeviceId,
            peerName: reservation.peerName,
            success: false,
            error: "The joiner did not acknowledge durable snapshot application. Retry the sync."
        )
        notifyStateChanged()
    }

    // State-machine probes keep capability lifecycle regressions deterministic
    // without requiring a physical two-device Multipeer session.
    func testIssueHostedSnapshotToken(_ token: String, for peerDeviceId: String) {
        hostedSnapshotTokens[peerDeviceId] = token
    }

    func testSetKeyAgreementIdentity(privateKeyB64: String, publicKeyB64: String) {
        kaPrivateKeyB64 = privateKeyB64
        kaPublicKeyB64 = publicKeyB64
    }

    func testReserveHostedSnapshot(
        token: String,
        for peerDeviceId: String,
        peerName: String = "Test peer"
    ) -> Bool {
        reserveHostedSnapshot(
            peerDeviceId: peerDeviceId,
            peerName: peerName,
            authorizationToken: token
        )
    }

    func testSetHostedSnapshotRowsSent(_ rowsSent: Int, for peerDeviceId: String) {
        hostedSnapshotReservations[peerDeviceId]?.rowsSent = rowsSent
    }

    func testAcknowledgeHostedSnapshot(
        token: String,
        for peerDeviceId: String,
        succeeded: Bool,
        error: String? = nil
    ) {
        handleFullSyncApplyAcknowledgement(
            FullSyncApplyAcknowledgement(
                authorizationToken: token,
                succeeded: succeeded,
                error: error
            ),
            from: peerDeviceId
        )
    }

    func testHostedSnapshotTokenAvailable(_ token: String, for peerDeviceId: String) -> Bool {
        hostedSnapshotTokens[peerDeviceId] == token
    }

    func testHostedSnapshotIsReserved(for peerDeviceId: String) -> Bool {
        hasHostedSnapshotReservation(for: peerDeviceId)
    }

    func testHostedSnapshotRequestIsDuplicate(
        token: String,
        for peerDeviceId: String
    ) -> Bool {
        hasHostedSnapshotReservation(for: peerDeviceId, requestToken: token)
    }

    func testBeginSnapshotBuffer(from peerDeviceId: String) {
        failedSnapshotPeers.remove(peerDeviceId)
        pendingSnapshotChanges[peerDeviceId] = []
    }

    func testAuthorizeReceivedSnapshot(_ token: String, from peerDeviceId: String) {
        receivedSnapshotTokens[peerDeviceId] = token
    }

    func testReceivedSnapshotToken(from peerDeviceId: String) -> String? {
        receivedSnapshotTokens[peerDeviceId]
    }

    func testProcessMultipeerMessagesInFIFO(
        _ messages: [ReceivedMultipeerMessage],
        sendApplyAcknowledgement: @escaping (FullSyncApplyAcknowledgement, String) -> Bool
    ) async throws -> [MultipeerMessageOutcome] {
        var outcomes: [MultipeerMessageOutcome] = []
        for message in messages {
            do {
                outcomes.append(try await processMultipeerMessage(
                    message,
                    sendApplyAcknowledgement: sendApplyAcknowledgement
                ))
            } catch {
                failPendingFullSync(from: message.fromDeviceId, with: error)
                throw error
            }
        }
        return outcomes
    }

    func testAbandonSnapshotBuffer(from peerDeviceId: String) {
        failedSnapshotPeers.insert(peerDeviceId)
        pendingSnapshotChanges.removeValue(forKey: peerDeviceId)
    }

    func testAwaitPairingTransport(
        peerDeviceId: String,
        requestNonce: String = "test-pairing-nonce"
    ) async throws {
        _ = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingPairContinuations[peerDeviceId] = PendingBluetoothPairingAttempt(
                    requestNonce: requestNonce,
                    continuation: continuation
                )
            }
        } onCancel: {
            Task {
                await self.cancelPairing(
                    with: peerDeviceId,
                    requestNonce: requestNonce
                )
            }
        }
    }

    func testResolvePairingTransport(_ response: SyncPairResponse, from peerDeviceId: String) throws {
        handlePairResponse(
            from: peerDeviceId,
            payload: try JSONEncoder().encode(response)
        )
    }

    func testTimeoutPairing(peerDeviceId: String, requestNonce: String) {
        timeoutPairing(with: peerDeviceId, requestNonce: requestNonce)
    }

    func testPendingPairingNonce(for peerDeviceId: String) -> String? {
        pendingPairContinuations[peerDeviceId]?.requestNonce
    }

    func testAwaitFullSyncTransport(peerDeviceId: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            pendingFullSyncContinuations[peerDeviceId] = continuation
        }
    }

    func testPendingTransportOperationCount() -> Int {
        pendingPairContinuations.count + pendingFullSyncContinuations.count
    }

    func testFailPendingTransportOperations() {
        failPendingMultipeerOperations(with: MultipeerPairingError.transportStopped)
    }

    func testCurrentKeyAgreementPublicKey() -> String {
        kaPublicKeyB64
    }

    /// Joiner side: the host finished replaying its data.
    private func handleFullSyncComplete(from peerDeviceId: String) {
        if let cont = pendingFullSyncContinuations.removeValue(forKey: peerDeviceId) {
            cont.resume()
        }
    }

    private func failPendingFullSync(from peerDeviceId: String, with error: Error) {
        if pendingSnapshotChanges[peerDeviceId] != nil
            || pendingFullSyncContinuations[peerDeviceId] != nil {
            failedSnapshotPeers.insert(peerDeviceId)
        }
        pendingSnapshotChanges.removeValue(forKey: peerDeviceId)
        if let cont = pendingFullSyncContinuations.removeValue(forKey: peerDeviceId) {
            cont.resume(throwing: error)
        }
    }

    private func timeoutFullSync(with peerDeviceId: String) {
        failedSnapshotPeers.insert(peerDeviceId)
        pendingSnapshotChanges.removeValue(forKey: peerDeviceId)
        if let cont = pendingFullSyncContinuations.removeValue(forKey: peerDeviceId) {
            cont.resume(throwing: MultipeerPairingError.responseTimeout)
        }
    }

    /// Wait for an MCSession to reach `connected`, re-inviting once if the
    /// first invitation lapses.
    ///
    /// FIELD P0 (owner, 2026-08-03, Bluetooth-only test): every wait here used
    /// to be **20 s while `MultipeerManager.invite` sets a 30 s invitation
    /// timeout** — the app gave up 10 s before iOS had finished trying, so a
    /// link that needed longer than 20 s could never succeed. Peer-to-peer
    /// Wi-Fi (AWDL) connects in ~1-3 s and hid this; **Bluetooth-only takes
    /// far longer**, so the owner saw "couldn't connect" on every attempt with
    /// Wi-Fi off. The wait must always exceed the invitation window, and a
    /// dropped invitation (Multipeer delivers no failure callback) must be
    /// re-sent rather than waited out.
    static let multipeerInviteTimeout: TimeInterval = 30
    static let multipeerConnectWait: TimeInterval = 75

    private func awaitMultipeerConnection(
        to deviceId: String,
        using mpManager: MultipeerManager,
        timeout: TimeInterval = PeerManager.multipeerConnectWait
    ) async -> Bool {
        if mpManager.isConnected(toPeer: deviceId) { return true }
        mpManager.invite(deviceId: deviceId)
        let started = Date()
        var reinvited = false
        while Date().timeIntervalSince(started) < timeout {
            if mpManager.isConnected(toPeer: deviceId) { return true }
            // Just past the invitation's own expiry, send exactly one more.
            if !reinvited, Date().timeIntervalSince(started) > Self.multipeerInviteTimeout + 2 {
                mpManager.invite(deviceId: deviceId)
                reinvited = true
                logger.info("[PeerManager] Re-invited \(String(deviceId.prefix(8)), privacy: .public) — first invitation lapsed without connecting")
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return mpManager.isConnected(toPeer: deviceId)
    }

    /// Joiner side: request and await the full initial company sync over Bluetooth.
    public func requestFullSyncOverMultipeer(hostDeviceId: String) async throws {
        guard let mpManager = multipeerManager else { throw MultipeerPairingError.notAvailable }
        guard inFlightFullSyncRequests.insert(hostDeviceId).inserted else {
            throw MultipeerPairingError.requestAlreadyInProgress
        }
        defer { inFlightFullSyncRequests.remove(hostDeviceId) }
        guard pendingFullSyncContinuations[hostDeviceId] == nil else {
            throw MultipeerPairingError.requestAlreadyInProgress
        }
        guard let authorizationToken = receivedSnapshotTokens[hostDeviceId] else {
            throw MultipeerPairingError.rejected
        }
        guard await awaitMultipeerConnection(to: hostDeviceId, using: mpManager) else {
            throw MultipeerPairingError.connectionTimeout
        }
        let request = try JSONEncoder().encode(
            FullSyncRequest(authorizationToken: authorizationToken)
        )
        let env = try JSONEncoder().encode(MPEnvelope(type: "fullSyncRequest", payload: request))
        failedSnapshotPeers.remove(hostDeviceId)
        pendingSnapshotChanges[hostDeviceId] = []
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // Register before sending so a fast host response cannot beat the waiter.
            pendingFullSyncContinuations[hostDeviceId] = cont
            guard mpManager.send(data: env, toPeer: hostDeviceId) else {
                pendingSnapshotChanges.removeValue(forKey: hostDeviceId)
                pendingFullSyncContinuations.removeValue(forKey: hostDeviceId)?
                    .resume(throwing: MultipeerPairingError.sendFailed)
                return
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)   // 60s cap for a full sync
                await self?.timeoutFullSync(with: hostDeviceId)
            }
        }
    }

    private func decodeIncomingChanges(_ data: Data) throws -> [IncomingChange] {
        guard let changes = try? JSONDecoder().decode([IncomingChange].self, from: data) else {
            throw MultipeerSnapshotError.malformedChanges
        }
        for change in changes {
            guard let recordData = change.recordData else { continue }
            guard let jsonData = recordData.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: jsonData),
                  object is [String: Any] else {
                throw MultipeerSnapshotError.invalidRecordData(
                    table: change.tableName,
                    recordID: change.recordId
                )
            }
        }
        return changes
    }

    /// Apply one or all buffered snapshot batches synchronously in one transaction.
    /// GRDB does not return until commit, so a following completion acknowledgement is truthful.
    private func applyIncomingChanges(_ changes: [IncomingChange]) throws -> Int {
        let did = serverState?.deviceId ?? "unknown"
        let result = try ConflictResolver.resolveAndApplyChangesAtomically(
            db: db,
            changes: changes,
            localDeviceId: did
        )
        guard result.errors == 0 else {
            throw MultipeerSnapshotError.batchApplyFailed(errorCount: result.errors)
        }
        return result.applied
    }

    /// Host side: a joiner sent a code-authenticated proof over Bluetooth. Validate
    /// it against the active pairing offer (same check as the Wi-Fi /sync/pair path),
    /// register the joiner as a trusted peer, and reply with our company id.
    private func handlePairRequest(from peerDeviceId: String, payload: Data) async {
        guard let mpManager = multipeerManager else { return }
        await processBluetoothPairRequest(from: peerDeviceId, payload: payload) { response in
            self.sendPairResponse(response, to: peerDeviceId, using: mpManager)
        }
    }

    internal func processBluetoothPairRequest(
        from peerDeviceId: String,
        payload: Data,
        injectActivationFailure: Bool = false,
        deliverResponse: (_ response: SyncPairResponse) -> Bool
    ) async {
        guard let sState = serverState,
              let request = try? JSONDecoder().decode(SyncPairRequest.self, from: payload) else { return }

        func rejectionResponse() -> SyncPairResponse {
            SyncPairResponse(
                accepted: false,
                serverDeviceId: sState.deviceId,
                companyId: "",
                pairedAt: CoreFormatters.nowISO(),
                bluetoothProtocolVersion: request.bluetoothProtocolVersion,
                bluetoothRequestNonce: request.bluetoothRequestNonce
            )
        }

        // Bind the code proof to the same advertised identity that owns this MCSession.
        let protocolIsSupported = request.bluetoothProtocolVersion == SyncCrypto.bluetoothPairingProtocolVersion
        let requestKeyIsValid = request.keyAgreementPublicKey
            .flatMap { Data(base64Encoded: $0) }?.count == 32
        let nonceIsValid = request.bluetoothRequestNonce
            .flatMap { Data(base64Encoded: $0) }?.count == 32
        guard request.deviceId == peerDeviceId,
              protocolIsSupported,
              request.bluetoothExpectedHostDeviceId == sState.deviceId,
              requestKeyIsValid,
              nonceIsValid,
              request.pairingProof != nil else {
            _ = deliverResponse(rejectionResponse())
            logger.error("[PeerManager] Bluetooth pairing rejected — invalid identity, key, or protocol version")
            return
        }

        guard let pairingCode = await sState.consumePairingProof(request) else {
            _ = deliverResponse(rejectionResponse())
            logger.error("[PeerManager] Bluetooth pairing rejected — invalid or already consumed code")
            return
        }

        let snapshotToken = UUID().uuidString
        let pairedAt = CoreFormatters.nowISO()
        let requestNonce = request.bluetoothRequestNonce ?? ""
        let requestProof = request.pairingProof ?? ""
        let clientPublicKey = request.keyAgreementPublicKey ?? ""
        var response = SyncPairResponse(
            accepted: true,
            serverDeviceId: sState.deviceId,
            companyId: sState.companyId,
            pairedAt: pairedAt,
            bluetoothProtocolVersion: SyncCrypto.bluetoothPairingProtocolVersion,
            bluetoothRequestNonce: requestNonce,
            bluetoothRequestPairingProof: requestProof,
            bluetoothClientDeviceId: request.deviceId,
            bluetoothClientKeyAgreementPublicKey: clientPublicKey,
            bluetoothSnapshotToken: snapshotToken,
            serverKeyAgreementPublicKey: kaPublicKeyB64
        )

        do {
            response.bluetoothResponseAuthenticator = try SyncCrypto.bluetoothPairingResponseAuthenticator(
                normalizedCode: pairingCode,
                ourPrivateKeyB64: kaPrivateKeyB64,
                theirPublicKeyB64: clientPublicKey,
                protocolVersion: SyncCrypto.bluetoothPairingProtocolVersion,
                requestNonce: requestNonce,
                requestPairingProof: requestProof,
                accepted: true,
                clientDeviceId: request.deviceId,
                clientPublicKeyB64: clientPublicKey,
                hostDeviceId: sState.deviceId,
                hostPublicKeyB64: kaPublicKeyB64,
                companyId: sState.companyId,
                snapshotToken: snapshotToken,
                pairedAt: pairedAt
            )
        } catch {
            try? await sState.setActivePairingCode(pairingCode)
            _ = deliverResponse(rejectionResponse())
            logger.error("[PeerManager] Bluetooth pairing rejected — response authentication failed")
            return
        }

        // Commit the host half before exposing an authenticated acceptance. This is
        // the pairing commit point: a joiner may only persist the host trust and
        // snapshot capability after it verifies this response, so sending it before
        // this transaction could create an irreversible split-brain pairing.
        let priorTrust: PeerDeviceTrustSnapshot?
        do {
            priorTrust = try ChangeTracker.capturePeerDeviceTrust(db: db, peerId: request.deviceId)
        } catch {
            try? await sState.setActivePairingCode(pairingCode)
            _ = deliverResponse(rejectionResponse())
            logger.fault("[PeerManager] Bluetooth pairing rejected — could not capture host trust state: \(error.localizedDescription, privacy: .public)")
            return
        }
        let priorSnapshotToken = hostedSnapshotTokens[request.deviceId]

        func restoreHostStateAfterUndeliveredAcceptance() {
            do {
                try ChangeTracker.restorePeerDeviceTrust(
                    db: db,
                    peerId: request.deviceId,
                    snapshot: priorTrust
                )
                if let priorSnapshotToken {
                    hostedSnapshotTokens[request.deviceId] = priorSnapshotToken
                } else {
                    hostedSnapshotTokens.removeValue(forKey: request.deviceId)
                }
            } catch {
                // A failed compensation must remain visible: proceeding would leave
                // a host authorization whose corresponding acceptance was not sent.
                logger.fault("[PeerManager] Bluetooth pairing rollback failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            try ChangeTracker.activateBluetoothPeerTrust(
                db: db,
                peerId: request.deviceId,
                peerName: request.deviceName,
                platform: request.platform,
                keyAgreementPublicKey: clientPublicKey,
                injectFailureBeforeCommit: injectActivationFailure
            )
            hostedSnapshotTokens[request.deviceId] = snapshotToken
        } catch {
            restoreHostStateAfterUndeliveredAcceptance()
            try? await sState.setActivePairingCode(pairingCode)
            _ = deliverResponse(rejectionResponse())
            logger.fault("[PeerManager] Bluetooth pairing rejected — host trust activation failed closed: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard deliverResponse(response) else {
            restoreHostStateAfterUndeliveredAcceptance()
            try? await sState.setActivePairingCode(pairingCode)
            logger.error("[PeerManager] Bluetooth pairing accepted response undelivered — host state restored and code kept for retry")
            return
        }

        // The one-time code is consumed — close the cross-company connection
        // window immediately (Copilot review on PR #1422: leaving it open
        // weakened company isolation after a successful pairing).
        setBluetoothPairingHostMode(false)
        logger.info("[PeerManager] Bluetooth pairing committed + accepted for peer \(String(request.deviceId.prefix(8)), privacy: .public)")
    }

    @discardableResult
    private func sendPairResponse(
        _ response: SyncPairResponse,
        to peerDeviceId: String,
        using manager: MultipeerManager
    ) -> Bool {
        guard let respData = try? JSONEncoder().encode(response),
              let env = try? JSONEncoder().encode(MPEnvelope(type: "pairResponse", payload: respData)) else {
            return false
        }
        return manager.send(data: env, toPeer: peerDeviceId)
    }


    /// Joiner side: a pairResponse arrived; resume the waiting continuation.
    private func handlePairResponse(from peerDeviceId: String, payload: Data) {
        guard let response = try? JSONDecoder().decode(SyncPairResponse.self, from: payload),
              let requestNonce = response.bluetoothRequestNonce,
              let attempt = takePendingPairingAttempt(
                for: peerDeviceId,
                requestNonce: requestNonce
              ) else {
            return
        }
        attempt.continuation.resume(returning: response)
    }

    /// Called by the response timeout to fail a still-pending pairing.
    private func timeoutPairing(with peerDeviceId: String, requestNonce: String) {
        takePendingPairingAttempt(for: peerDeviceId, requestNonce: requestNonce)?
            .continuation.resume(throwing: MultipeerPairingError.responseTimeout)
    }

    private func cancelPairing(with peerDeviceId: String, requestNonce: String) {
        takePendingPairingAttempt(for: peerDeviceId, requestNonce: requestNonce)?
            .continuation.resume(throwing: CancellationError())
    }

    private func takePendingPairingAttempt(
        for peerDeviceId: String,
        requestNonce: String
    ) -> PendingBluetoothPairingAttempt? {
        guard pendingPairContinuations[peerDeviceId]?.requestNonce == requestNonce else {
            return nil
        }
        return pendingPairContinuations.removeValue(forKey: peerDeviceId)
    }

    static func validateBluetoothPairingResponse(
        _ response: SyncPairResponse,
        context: BluetoothPairingAttemptContext
    ) throws -> (snapshotToken: String, hostPublicKey: String) {
        guard response.bluetoothProtocolVersion == SyncCrypto.bluetoothPairingProtocolVersion else {
            throw MultipeerPairingError.protocolUpgradeRequired
        }
        guard response.bluetoothRequestNonce == context.requestNonce,
              response.serverDeviceId == context.expectedHostDeviceId else {
            throw MultipeerPairingError.responseVerificationFailed
        }
        guard response.accepted else { throw MultipeerPairingError.rejected }
        guard context.protocolVersion == SyncCrypto.bluetoothPairingProtocolVersion,
              Data(base64Encoded: context.clientPrivateKeyB64)?.count == 32,
              Data(base64Encoded: context.clientPublicKeyB64)?.count == 32,
              let hostPublicKey = response.serverKeyAgreementPublicKey,
              Data(base64Encoded: hostPublicKey)?.count == 32,
              let snapshotToken = response.bluetoothSnapshotToken,
              !snapshotToken.isEmpty,
              !response.pairedAt.isEmpty,
              response.bluetoothRequestPairingProof == context.requestPairingProof,
              response.bluetoothClientDeviceId == context.clientDeviceId,
              response.bluetoothClientKeyAgreementPublicKey == context.clientPublicKeyB64,
              SyncCrypto.verifyBluetoothPairingResponseAuthenticator(
                response.bluetoothResponseAuthenticator,
                normalizedCode: context.normalizedPairingCode,
                ourPrivateKeyB64: context.clientPrivateKeyB64,
                theirPublicKeyB64: hostPublicKey,
                protocolVersion: SyncCrypto.bluetoothPairingProtocolVersion,
                requestNonce: context.requestNonce,
                requestPairingProof: context.requestPairingProof,
                accepted: true,
                clientDeviceId: context.clientDeviceId,
                clientPublicKeyB64: context.clientPublicKeyB64,
                hostDeviceId: context.expectedHostDeviceId,
                hostPublicKeyB64: hostPublicKey,
                companyId: response.companyId,
                snapshotToken: snapshotToken,
                pairedAt: response.pairedAt
              ) else {
            throw MultipeerPairingError.responseVerificationFailed
        }
        return (snapshotToken, hostPublicKey)
    }

    @discardableResult
    internal func acceptBluetoothPairingResponse(
        _ response: SyncPairResponse,
        context: BluetoothPairingAttemptContext,
        peerName: String
    ) throws -> SyncPairResponse {
        let verified = try Self.validateBluetoothPairingResponse(response, context: context)
        try ChangeTracker.registerPeerDevice(
            db: db,
            peerId: response.serverDeviceId,
            peerName: peerName,
            platform: "ios",
            keyAgreementPublicKey: verified.hostPublicKey
        )
        receivedSnapshotTokens[context.expectedHostDeviceId] = verified.snapshotToken
        return response
    }

    /// Joiner side: pair with a Bluetooth-discovered host by connecting the
    /// Multipeer session and exchanging a code-authenticated proof — no Wi-Fi needed.
    public func pairViaMultipeer(
        hostDeviceId: String,
        myDeviceId: String,
        myDeviceName: String,
        pairingCode: String,
        platform: String
    ) async throws -> SyncPairResponse {
        guard let mpManager = multipeerManager else { throw MultipeerPairingError.notAvailable }
        guard inFlightPairRequests.insert(hostDeviceId).inserted else {
            throw MultipeerPairingError.requestAlreadyInProgress
        }
        defer { inFlightPairRequests.remove(hostDeviceId) }
        guard pendingPairContinuations[hostDeviceId] == nil else {
            throw MultipeerPairingError.requestAlreadyInProgress
        }
        guard let normalizedCode = SyncCrypto.normalizedPairingCode(pairingCode),
              Data(base64Encoded: kaPrivateKeyB64)?.count == 32,
              Data(base64Encoded: kaPublicKeyB64)?.count == 32 else {
            throw MultipeerPairingError.responseVerificationFailed
        }

        // 1. Invite the host and wait for the MCSession to connect. The wait
        //    must outlast the invitation timeout (see awaitMultipeerConnection).
        guard await awaitMultipeerConnection(to: hostDeviceId, using: mpManager) else {
            throw MultipeerPairingError.connectionTimeout
        }

        // 2. Send a proof bound to this attempt, expected host, and durable device key.
        let requestNonce = SyncCrypto.bluetoothPairingRequestNonce()
        let requestProof = SyncCrypto.bluetoothPairingProof(
            normalizedCode: normalizedCode,
            expectedHostDeviceId: hostDeviceId,
            clientDeviceId: myDeviceId,
            clientPublicKeyB64: kaPublicKeyB64,
            requestNonce: requestNonce
        )
        let pairingContext = BluetoothPairingAttemptContext(
            protocolVersion: SyncCrypto.bluetoothPairingProtocolVersion,
            expectedHostDeviceId: hostDeviceId,
            clientDeviceId: myDeviceId,
            clientPrivateKeyB64: kaPrivateKeyB64,
            clientPublicKeyB64: kaPublicKeyB64,
            normalizedPairingCode: normalizedCode,
            requestNonce: requestNonce,
            requestPairingProof: requestProof
        )
        pendingBluetoothPairingContexts[hostDeviceId] = pairingContext
        defer {
            if pendingBluetoothPairingContexts[hostDeviceId]?.requestNonce == requestNonce {
                pendingBluetoothPairingContexts.removeValue(forKey: hostDeviceId)
            }
        }
        let request = SyncPairRequest(
            deviceId: myDeviceId,
            deviceName: myDeviceName,
            pairingProof: requestProof,
            platform: platform,
            bluetoothProtocolVersion: SyncCrypto.bluetoothPairingProtocolVersion,
            bluetoothRequestNonce: requestNonce,
            bluetoothExpectedHostDeviceId: hostDeviceId,
            keyAgreementPublicKey: kaPublicKeyB64
        )
        let payload = try JSONEncoder().encode(request)
        let env = try JSONEncoder().encode(MPEnvelope(type: "pairRequest", payload: payload))

        // 3. Await the pairResponse (resumed by handlePairResponse), with a timeout.
        let response: SyncPairResponse = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                // Register before sending so a fast response cannot beat the waiter.
                pendingPairContinuations[hostDeviceId] = PendingBluetoothPairingAttempt(
                    requestNonce: requestNonce,
                    continuation: cont
                )
                guard mpManager.send(data: env, toPeer: hostDeviceId) else {
                    takePendingPairingAttempt(for: hostDeviceId, requestNonce: requestNonce)?
                        .continuation.resume(throwing: MultipeerPairingError.sendFailed)
                    return
                }
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    await self?.timeoutPairing(
                        with: hostDeviceId,
                        requestNonce: requestNonce
                    )
                }
            }
        } onCancel: {
            Task {
                await self.cancelPairing(
                    with: hostDeviceId,
                    requestNonce: requestNonce
                )
            }
        }
        guard pendingBluetoothPairingContexts[hostDeviceId]?.requestNonce == requestNonce else {
            throw MultipeerPairingError.responseVerificationFailed
        }
        // Validation completes before either durable trust or the one-time snapshot
        // capability is exposed to downstream persistence and authorization.
        return try acceptBluetoothPairingResponse(
            response,
            context: pairingContext,
            peerName: hostDeviceId
        )
    }
    #endif

    // MARK: - Private: Enrich Changes

    /// JSON-safe dictionary from a GRDB row.
    ///
    /// `row[column] as Any` wraps SQL NULLs as Swift `Optional.none`, which
    /// `JSONSerialization` rejects — so ANY row containing a NULL column failed
    /// to serialize and was silently dropped from sync payloads. That is why the
    /// seeded admin user (email/phone NULL) never arrived on a Bluetooth-joined
    /// device ("No User Found", 2026-07-06). Map the database storage explicitly:
    /// NULL → NSNull (the receiver's parseJsonField turns it back into SQL NULL),
    /// numbers → NSNumber, text → String. Blob columns are OMITTED entirely —
    /// binary payloads travel via BinarySyncManager, not row JSON. Omitting
    /// (vs the old NSNull mapping) matters on the merge path: an explicit NULL
    /// would overwrite a real blob on the receiver (e.g. business_profiles
    /// .logo_data cleared remotely whenever any other profile field changed),
    /// while a missing key means "leave this column alone" (Copilot review on
    /// PR #1422).
    internal static func jsonRecordDict(from row: Row) -> [String: Any] {
        var dict: [String: Any] = [:]
        for (column, dbValue) in row {
            switch dbValue.storage {
            case .null:
                dict[column] = NSNull()
            case .int64(let value):
                dict[column] = NSNumber(value: value)
            case .double(let value):
                dict[column] = NSNumber(value: value)
            case .string(let value):
                dict[column] = value
            case .blob:
                continue
            }
        }
        return dict
    }

    /// Add full record data to INSERT/UPDATE changes so the receiving peer
    /// can INSERT OR REPLACE them.
    internal func enrichChangesWithData(_ entries: [ChangeLogEntry]) throws -> [IncomingChange] {
        try entries.map { entry in
            var recordData: String? = nil

            if entry.operation != "DELETE" {
                // Fetch full row from the table
                let row = try db.writer.read { dbConn in
                    try Row.fetchOne(
                        dbConn,
                        sql: "SELECT * FROM [\(entry.tableName)] WHERE id = ?",
                        arguments: [entry.recordId]
                    )
                }
                if let row = row {
                    // Never push device-scoped settings (pairing/device identity)
                    // to peers — same rule as the initial snapshot. A nil
                    // recordData makes the receiver skip the change harmlessly.
                    let isDeviceScopedSetting = entry.tableName == "settings"
                        && SettingsService.syncScope(
                            for: (row["key"] as? String) ?? "",
                            category: row["category"] as? String
                        ) == .device
                    if !isDeviceScopedSetting {
                        let dict = Self.jsonRecordDict(from: row)
                        if let jsonData = try? JSONSerialization.data(withJSONObject: dict) {
                            recordData = String(data: jsonData, encoding: .utf8)
                        }
                    }
                }
            }

            return IncomingChange(
                id: entry.sequence.map { Int64($0) },
                deviceId: entry.deviceId,
                tableName: entry.tableName,
                recordId: String(entry.recordId),
                operation: entry.operation,
                changedFields: entry.changedFields,
                oldValues: entry.oldValues,
                recordData: recordData,
                timestamp: entry.timestamp
            )
        }
    }

    // MARK: - Helpers

    /// Heuristic: is this peer likely an office/shop computer?
    public static func isOfficePeer(_ peer: DiscoveredPeer) -> Bool {
        let name = peer.deviceName.lowercased()
        return name.contains("office") ||
               name.contains("shop") ||
               name.contains("server") ||
               name.contains("main")
    }

    private func notifyStateChanged() {
        let snapshot = state
        let callback = onStateChanged
        Task { @MainActor in
            callback?(snapshot)
        }
    }
}
