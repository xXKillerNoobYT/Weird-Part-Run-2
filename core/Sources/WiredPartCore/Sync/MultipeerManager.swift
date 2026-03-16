#if canImport(MultipeerConnectivity)
import Foundation
@preconcurrency import MultipeerConnectivity

// MARK: - MultipeerPeerInfo

/// Info about a peer discovered via Multipeer Connectivity.
public struct MultipeerPeerInfo: Sendable {
    public let deviceId: String
    public let deviceName: String
    public let companyId: String
    public let state: MultipeerPeerState
    public let discoveredAt: String

    public init(
        deviceId: String,
        deviceName: String,
        companyId: String,
        state: MultipeerPeerState = .found,
        discoveredAt: String? = nil
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.companyId = companyId
        self.state = state
        self.discoveredAt = discoveredAt ?? Self.currentTimestamp()
    }

    private static func currentTimestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
}

public enum MultipeerPeerState: String, Sendable {
    case found
    case connecting
    case connected
}

// MARK: - ReceivedMultipeerMessage

/// A message received from a peer via Multipeer Connectivity.
public struct ReceivedMultipeerMessage: Sendable {
    public let fromDeviceId: String
    public let data: Data
    public let receivedAt: String

    public init(fromDeviceId: String, data: Data, receivedAt: String? = nil) {
        self.fromDeviceId = fromDeviceId
        self.data = data
        self.receivedAt = receivedAt ?? {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.string(from: Date())
        }()
    }
}

// MARK: - MultipeerManager

/// Multipeer Connectivity manager for Bluetooth/WiFi P2P sync.
///
/// Ported from: `src-tauri/objc/MultipeerBridge.m`
///
/// Service type: `"wiredpart-sync"` (matching existing ObjC bridge)
/// Discovery info: `device_id`, `device_name`, `company_id`
/// Auto-invite same-company peers, auto-accept same-company invitations.
/// Uses `MCEncryptionRequired` for all sessions.
public final class MultipeerManager: NSObject, @unchecked Sendable {

    /// Called when the peer list changes.
    public var onPeersChanged: (([MultipeerPeerInfo]) -> Void)?

    /// Called when data is received from a peer.
    public var onDataReceived: ((ReceivedMultipeerMessage) -> Void)?

    private static let serviceType = "wiredpart-sync"

    private let deviceId: String
    private let deviceName: String
    private let companyId: String

    private let syncQueue = DispatchQueue(label: "com.wiredpart.multipeer.sync", qos: .utility)
    private var localPeerId: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var peers: [String: PeerEntry] = [:]  // keyed by device_id
    private var receiveQueue: [ReceivedMultipeerMessage] = []
    private var isRunning = false

    /// Internal peer tracking with MCPeerID association.
    private struct PeerEntry {
        let info: MultipeerPeerInfo
        let mcPeerId: MCPeerID
    }

    public init(deviceId: String, deviceName: String, companyId: String) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.companyId = companyId
        super.init()

        // MCPeerID display name must be 1-63 chars
        let displayName = String(deviceName.prefix(63))
        self.localPeerId = MCPeerID(displayName: displayName.isEmpty ? "WiredPart" : displayName)
        self.session = MCSession(
            peer: localPeerId,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        self.session.delegate = self
    }

    /// Start advertising and browsing for peers.
    public func start() {
        syncQueue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true
            self.startAdvertising()
            self.startBrowsing()
        }
    }

    /// Stop advertising and browsing.
    public func stop() {
        syncQueue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.advertiser?.stopAdvertisingPeer()
            self.advertiser = nil
            self.browser?.stopBrowsingForPeers()
            self.browser = nil
            self.session.disconnect()
            self.peers.removeAll()
        }
    }

    /// Get snapshot of all discovered peers.
    public func getPeers() -> [MultipeerPeerInfo] {
        syncQueue.sync {
            peers.values.map { $0.info }
        }
    }

    /// Send data to a specific peer. Returns true on success.
    public func send(data: Data, toPeer deviceId: String) -> Bool {
        syncQueue.sync {
            guard let entry = peers[deviceId],
                  entry.info.state == .connected else {
                return false
            }
            do {
                try session.send(data, toPeers: [entry.mcPeerId], with: .reliable)
                return true
            } catch {
                return false
            }
        }
    }

    /// Pop the next received message from the FIFO queue.
    public func popReceivedMessage() -> ReceivedMultipeerMessage? {
        syncQueue.sync {
            receiveQueue.isEmpty ? nil : receiveQueue.removeFirst()
        }
    }

    /// Number of messages waiting in the receive queue.
    public var receiveQueueCount: Int {
        syncQueue.sync { receiveQueue.count }
    }

    // MARK: - Private

    private func startAdvertising() {
        let discoveryInfo: [String: String] = [
            "device_id": deviceId,
            "device_name": deviceName,
            "company_id": companyId
        ]
        let advertiser = MCNearbyServiceAdvertiser(
            peer: localPeerId,
            discoveryInfo: discoveryInfo,
            serviceType: Self.serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
    }

    private func startBrowsing() {
        let browser = MCNearbyServiceBrowser(
            peer: localPeerId,
            serviceType: Self.serviceType
        )
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    private func notifyPeersChanged() {
        let snapshot = peers.values.map { $0.info }
        DispatchQueue.main.async { [weak self] in
            self?.onPeersChanged?(snapshot)
        }
    }
}

// MARK: - MCSessionDelegate

extension MultipeerManager: MCSessionDelegate {
    public func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        syncQueue.async { [weak self] in
            guard let self else { return }

            // Find the peer entry by MCPeerID
            for (key, entry) in self.peers {
                if entry.mcPeerId == peerID {
                    let newState: MultipeerPeerState
                    switch state {
                    case .notConnected:
                        self.peers.removeValue(forKey: key)
                        self.notifyPeersChanged()
                        return
                    case .connecting:
                        newState = .connecting
                    case .connected:
                        newState = .connected
                    @unknown default:
                        return
                    }

                    let updated = MultipeerPeerInfo(
                        deviceId: entry.info.deviceId,
                        deviceName: entry.info.deviceName,
                        companyId: entry.info.companyId,
                        state: newState,
                        discoveredAt: entry.info.discoveredAt
                    )
                    self.peers[key] = PeerEntry(info: updated, mcPeerId: peerID)
                    self.notifyPeersChanged()
                    return
                }
            }
        }
    }

    public func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {
        syncQueue.async { [weak self] in
            guard let self else { return }

            // Find sender's device_id
            var fromDeviceId = peerID.displayName
            for (_, entry) in self.peers {
                if entry.mcPeerId == peerID {
                    fromDeviceId = entry.info.deviceId
                    break
                }
            }

            let message = ReceivedMultipeerMessage(
                fromDeviceId: fromDeviceId,
                data: data
            )
            self.receiveQueue.append(message)
            self.onDataReceived?(message)
        }
    }

    // Required but unused delegate methods
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    public func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        syncQueue.async { [weak self] in
            guard let self else { return }

            let peerDeviceId = info?["device_id"] ?? ""
            let peerDeviceName = info?["device_name"] ?? peerID.displayName
            let peerCompanyId = info?["company_id"] ?? ""

            // Skip self
            guard peerDeviceId != self.deviceId else { return }
            // Same company only
            guard peerCompanyId == self.companyId else { return }

            // Track the peer
            let peerInfo = MultipeerPeerInfo(
                deviceId: peerDeviceId,
                deviceName: peerDeviceName,
                companyId: peerCompanyId,
                state: .found
            )
            self.peers[peerDeviceId] = PeerEntry(info: peerInfo, mcPeerId: peerID)
            self.notifyPeersChanged()

            // Auto-invite same-company peer
            let context: [String: String] = [
                "device_id": self.deviceId,
                "device_name": self.deviceName,
                "company_id": self.companyId
            ]
            if let contextData = try? JSONSerialization.data(withJSONObject: context) {
                browser.invitePeer(
                    peerID,
                    to: self.session,
                    withContext: contextData,
                    timeout: 30.0
                )
            }
        }
    }

    public func browser(
        _ browser: MCNearbyServiceBrowser,
        lostPeer peerID: MCPeerID
    ) {
        syncQueue.async { [weak self] in
            guard let self else { return }
            // Remove peer by MCPeerID
            for (key, entry) in self.peers {
                if entry.mcPeerId == peerID {
                    self.peers.removeValue(forKey: key)
                    self.notifyPeersChanged()
                    return
                }
            }
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        nonisolated(unsafe) let handler = invitationHandler
        syncQueue.async { [weak self] in
            guard let self else {
                handler(false, nil)
                return
            }

            // Parse context to check company_id
            var peerCompanyId = ""
            if let contextData = context,
               let json = try? JSONSerialization.jsonObject(with: contextData) as? [String: String] {
                peerCompanyId = json["company_id"] ?? ""
            }

            // Auto-accept same-company peers
            if peerCompanyId == self.companyId {
                handler(true, self.session)
            } else {
                handler(false, nil)
            }
        }
    }
}

#endif // canImport(MultipeerConnectivity)
