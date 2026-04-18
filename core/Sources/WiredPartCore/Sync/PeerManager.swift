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
public actor PeerManager {

    private let db: AppDatabase
    private var state = PeerManagerState()
    private let logger = Logger(subsystem: "com.wiredpart.core", category: "PeerManager")

    private var syncServer: LanSyncServer?
    private var serverState: SyncServerState?
    private var peerDiscovery: PeerDiscovery?

    #if canImport(MultipeerConnectivity)
    private var multipeerManager: MultipeerManager?
    #endif

    private var peerPollTask: Task<Void, Never>?
    private var inboxProcessTask: Task<Void, Never>?

    /// X25519 key agreement keys for this session. Generated when peer sync starts.
    private var kaPrivateKeyB64: String = ""
    private var kaPublicKeyB64: String = ""

    /// Company ID for this sync session. Sent as X-Company-ID on key-exchange requests (#191).
    private var companyId: String = ""

    /// Cached X25519 public keys from peers. keyed by peer device ID.
    /// "" means the peer was contacted but doesn't support encryption (backward compat).
    private var peerKAPublicKeys: [String: String] = [:]

    /// Called when state changes.
    public var onStateChanged: (@Sendable (PeerManagerState) -> Void)?

    /// Set the state-changed callback from outside the actor.
    public func setOnStateChanged(_ callback: (@Sendable (PeerManagerState) -> Void)?) {
        onStateChanged = callback
    }

    public init(db: AppDatabase) {
        self.db = db
    }

    /// Get current state snapshot.
    public func getState() -> PeerManagerState {
        state
    }

    // MARK: - Lifecycle

    /// Start the P2P sync system: sync server, mDNS, Multipeer, polling loops.
    public func startPeerSync(
        deviceId: String,
        deviceName: String,
        companyId: String
    ) async throws {
        guard !state.running else { return }

        // 0. Generate X25519 KA key pair for this sync session
        let (kaPriv, kaPub) = SyncCrypto.generateKeyAgreementPair()
        kaPrivateKeyB64 = kaPriv
        kaPublicKeyB64 = kaPub
        self.companyId = companyId          // Fix #191: stored for key-exchange requests
        peerKAPublicKeys.removeAll()

        // 1. Start LAN sync server
        let sState = SyncServerState(
            deviceId: deviceId,
            deviceName: deviceName,
            companyId: companyId
        )
        self.serverState = sState

        let server = LanSyncServer(state: sState)
        let port = try await server.start()
        self.syncServer = server

        state.running = true
        state.syncPort = port
        notifyStateChanged()

        // 2. Start mDNS discovery
        let discovery = PeerDiscovery(
            deviceId: deviceId,
            companyId: companyId,
            deviceName: deviceName,
            port: port
        )
        discovery.onPeersChanged = { [weak self] peers in
            guard let self else { return }
            Task { await self.handleLanPeersChanged(peers) }
        }
        discovery.start()
        self.peerDiscovery = discovery

        // 3. Start Multipeer Connectivity (Apple platforms)
        #if canImport(MultipeerConnectivity)
        let mpManager = MultipeerManager(
            deviceId: deviceId,
            deviceName: deviceName,
            companyId: companyId
        )
        mpManager.onPeersChanged = { [weak self] _ in
            guard let self else { return }
            Task { await self.mergePeerLists() }
        }
        mpManager.onDataReceived = { [weak self] message in
            guard let self else { return }
            Task { await self.handleMultipeerMessage(message) }
        }
        mpManager.start()
        self.multipeerManager = mpManager
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
        multipeerManager?.stop()
        multipeerManager = nil
        #endif

        await syncServer?.stop()
        syncServer = nil
        serverState = nil

        state = PeerManagerState()
        notifyStateChanged()
    }

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
            // Register peer in device registry
            try ChangeTracker.registerPeerDevice(
                db: db,
                peerId: peer.deviceId,
                peerName: peer.deviceName
            )

            // Get pending changes
            let pendingChanges = try ChangeTracker.getPendingChanges(db: db)
            let enrichedChanges = try enrichChangesWithData(pendingChanges)

            var pushed = 0
            var pulled = 0

            #if canImport(MultipeerConnectivity)
            if peer.transport == "multipeer" && peer.multipeerState == "connected",
               let mpManager = multipeerManager {
                // Multipeer sync path
                if !enrichedChanges.isEmpty {
                    let encoder = JSONEncoder()
                    let payload = try encoder.encode(enrichedChanges)
                    if mpManager.send(data: payload, toPeer: peer.deviceId) {
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

        let baseURL = "http://\(peer.host):\(peer.port)"
        let lastSyncAt = state.lastPeerSyncs[peer.deviceId]?.syncedAt

        // Resolve shared key for this peer (fetches /sync/key once then caches)
        let sharedKeyData = await resolveSharedKey(baseURL: baseURL, peerDeviceId: peer.deviceId)

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

            guard let pushURL = URL(string: "\(baseURL)/sync/push") else {
                throw URLError(.badURL)
            }
            var urlRequest = URLRequest(url: pushURL)
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = 30
            applyPayload(&urlRequest, plain: plainPushBody, sharedKeyData: sharedKeyData)

            let (pushData, pushResp) = try await URLSession.shared.data(for: urlRequest)
            if let httpResp = pushResp as? HTTPURLResponse, httpResp.statusCode == 200 {
                let plainPushData = decrypt(pushData, sharedKeyData: sharedKeyData)
                if let result = try? JSONDecoder().decode(SyncPushResponse.self, from: plainPushData) {
                    pushed = result.accepted
                    let syncedIds = pendingChanges.compactMap { $0.id }
                    try ChangeTracker.markSynced(db: db, ids: syncedIds, batchId: result.syncBatchId)
                }
            }
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
        guard let pullURL = URL(string: "\(baseURL)/sync/pull") else {
            throw URLError(.badURL)
        }
        var pullURLRequest = URLRequest(url: pullURL)
        pullURLRequest.httpMethod = "POST"
        pullURLRequest.timeoutInterval = 30
        applyPayload(&pullURLRequest, plain: plainPullBody, sharedKeyData: sharedKeyData)

        let (pullData, pullResp) = try await URLSession.shared.data(for: pullURLRequest)
        if let httpResp = pullResp as? HTTPURLResponse, httpResp.statusCode == 200 {
            let plainPullData = decrypt(pullData, sharedKeyData: sharedKeyData)
            if let result = try? JSONDecoder().decode(SyncPullResponse.self, from: plainPullData) {
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
            }
        }

        return (pushed, pulled)
    }

    // MARK: - Private: Payload Encryption Helpers

    /// Fetch the peer's X25519 KA public key from GET /sync/key (cached).
    /// Returns nil if the peer doesn't support encryption (old version or network error).
    private func resolveSharedKey(baseURL: String, peerDeviceId: String) async -> Data? {
        // Use cached peer KA public key if available
        let peerKAKey: String
        if let cached = peerKAPublicKeys[peerDeviceId], !cached.isEmpty {
            peerKAKey = cached
        } else if let fetched = await fetchPeerKAPublicKey(baseURL: baseURL, peerDeviceId: peerDeviceId) {
            peerKAKey = fetched
        } else {
            // Peer doesn't support encryption — sync will proceed unencrypted (logged in fetchPeerKAPublicKey)
            return nil
        }
        guard !peerKAKey.isEmpty, !kaPrivateKeyB64.isEmpty else { return nil }
        return try? SyncCrypto.deriveSharedKeyData(
            ourPrivateKeyB64: kaPrivateKeyB64,
            theirPublicKeyB64: peerKAKey
        )
    }

    /// Call GET /sync/key on the peer to get their X25519 KA public key.
    /// Returns the key if successful, nil if encryption is not supported.
    /// Fixes #197: no longer silently falls back — callers must handle nil explicitly.
    /// Fixes #191: sends X-Company-ID header so the server can reject unknown peers.
    private func fetchPeerKAPublicKey(baseURL: String, peerDeviceId: String) async -> String? {
        guard let url = URL(string: "\(baseURL)/sync/key") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        // Fix #191: identify our company so the server can gate key exchange to known peers.
        if !companyId.isEmpty {
            req.setValue(companyId, forHTTPHeaderField: "X-Company-ID")
        }
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           let httpResp = resp as? HTTPURLResponse,
           httpResp.statusCode == 200,
           let decoded = try? JSONDecoder().decode(SyncKeyResponse.self, from: data),
           !decoded.key.isEmpty {
            peerKAPublicKeys[peerDeviceId] = decoded.key
            return decoded.key
        }
        logger.warning("Peer \(String(peerDeviceId.prefix(8)), privacy: .public)... does not support encryption — sync will be unencrypted over LAN")
        peerKAPublicKeys[peerDeviceId] = ""
        return nil
    }

    /// Attach encrypted or plaintext body + headers to a URLRequest.
    /// If sharedKeyData is nil, sends plaintext JSON (backward compat).
    private func applyPayload(
        _ request: inout URLRequest,
        plain: Data,
        sharedKeyData: Data?
    ) {
        if let keyData = sharedKeyData,
           let encrypted = try? SyncCrypto.encryptAESGCM(data: plain, keyData: keyData) {
            request.httpBody = encrypted
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "X-Sync-Encrypted")
            request.setValue(kaPublicKeyB64, forHTTPHeaderField: "X-Sync-Sender-Key")
        } else {
            request.httpBody = plain
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
    }

    /// Decrypt a response body if a shared key was used for this request.
    /// Falls back to the raw data if decryption isn't needed or fails.
    private func decrypt(_ data: Data, sharedKeyData: Data?) -> Data {
        guard let keyData = sharedKeyData,
              let plain = try? SyncCrypto.decryptAESGCM(data: data, keyData: keyData) else {
            return data
        }
        return plain
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
    private func handleMultipeerMessage(_ message: ReceivedMultipeerMessage) {
        // Parse as array of IncomingChange
        guard let changes = try? JSONDecoder().decode([IncomingChange].self, from: message.data) else {
            return
        }

        let deviceId = serverState?.deviceId ?? "unknown"
        Task {
            let did = deviceId
            do {
                _ = try ConflictResolver.resolveAndApplyChanges(
                    db: self.db,
                    changes: changes,
                    localDeviceId: did
                )
            } catch {
                self.logger.error("ConflictResolver failed for peer \(String(did.prefix(8)), privacy: .public)...: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    #endif

    // MARK: - Private: Enrich Changes

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
                    var dict: [String: Any] = [:]
                    for column in row.columnNames {
                        dict[column] = row[column] as Any
                    }
                    if let jsonData = try? JSONSerialization.data(withJSONObject: dict) {
                        recordData = String(data: jsonData, encoding: .utf8)
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
