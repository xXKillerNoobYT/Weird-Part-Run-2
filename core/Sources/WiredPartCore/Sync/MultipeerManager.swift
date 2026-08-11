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

    private static func currentTimestamp() -> String { CoreFormatters.iso8601Fractional.string(from: Date()) }
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
        self.receivedAt = receivedAt ?? CoreFormatters.iso8601Fractional.string(from: Date())
    }
}

// MARK: - MultipeerManager

/// Multipeer Connectivity manager for Bluetooth/WiFi P2P sync.
///
/// Ported from: `src-tauri/objc/MultipeerBridge.m`
///
/// Service type: `"wiredpart-sync"` in production (matching existing ObjC
/// bridge); a per-process `wpr2t-*` type under test so CI can never advertise
/// onto the real mesh (#1701).
/// Discovery info: `device_id`, `device_name`, `company_id`
/// Auto-invite same-company peers, auto-accept same-company invitations.
/// Join/onboarding discovery can browse any company before the local company ID
/// is known; pairing still verifies the selected shop before anything is saved.
/// Uses `MCEncryptionRequired` for all sessions.
/// @unchecked Sendable: All mutable state is guarded by `syncQueue` (serial DispatchQueue).
/// Any new mutable property MUST be accessed only from syncQueue. (Fixes #202)
public final class MultipeerManager: NSObject, @unchecked Sendable {

    /// Called when the peer list changes. GUARDED BY syncQueue
    public var onPeersChanged: (([MultipeerPeerInfo]) -> Void)?

    /// Called when data is received from a peer. GUARDED BY syncQueue
    public var onDataReceived: ((ReceivedMultipeerMessage) -> Void)?

    /// Called when the OS refuses to START advertising or browsing. (#1580)
    ///
    /// `MCNearbyServiceAdvertiserDelegate` / `MCNearbyServiceBrowserDelegate`
    /// report denied Local Network permission, a missing `NSBonjourServices`
    /// entry, and a disabled radio through these callbacks and nowhere else.
    /// Both were unimplemented, so those failures were dropped on the floor and
    /// every one of them reached the user as the same generic "couldn't
    /// connect" — undiagnosable across four builds of fixes. Emitted as a
    /// human-readable line so the caller can log or surface it.
    public var onTransportError: ((String) -> Void)?

    /// The production Bonjour service type. Every shipping device uses this.
    static let productionServiceType = "wiredpart-sync"

    /// Set this in the environment of any process that must stay off the real
    /// mesh. Required for **UI tests**, where the app under test is a separate
    /// process and therefore is *not* itself running under XCTest — the
    /// in-process detection below cannot see it. CI exports it into the
    /// simulator via `SIMCTL_CHILD_`-prefixed environment.
    static let testServiceTypeEnvVar = "WIREDPART_SYNC_TEST_SERVICE"

    /// Escape hatch for a developer who deliberately wants a Simulator to join
    /// the real mesh. Off by default and never set in CI. Documented rather
    /// than hidden so the one legitimate case does not tempt anyone into
    /// weakening the rules above it.
    static let forceProductionMeshEnvVar = "WIREDPART_SYNC_FORCE_PRODUCTION_MESH"

    /// True when this process must not advertise on the real Bluetooth mesh.
    ///
    /// Three independent conditions, because relying on any single one has
    /// already failed in the field (#1701):
    ///
    /// 1. **Simulator** — compile-time, and the load-bearing one. The peer the
    ///    owner actually saw was `WPR2-CI-iPad-<run-id>`, a CI *simulator*
    ///    running the app as its own process. That process is not itself under
    ///    XCTest, so in-process test detection cannot see it, and a per-test
    ///    opt-in would silently rot the first time someone adds a UI test file
    ///    without it. A Simulator is never an electrician's phone, so it has no
    ///    business on the production mesh.
    /// 2. **In-process test detection** — covers SwiftPM/XCTest bundles and
    ///    Xcode test hosts, including unit tests that stand up a real
    ///    `PeerManager`.
    /// 3. **Environment variable** — lets a physical-device test rig opt out
    ///    explicitly.
    static let isRunningUnderTests: Bool = {
        let env = ProcessInfo.processInfo.environment
        if env[forceProductionMeshEnvVar] == "1" { return false }

        #if targetEnvironment(simulator)
        return true
        #else
        if env[testServiceTypeEnvVar] != nil { return true }
        if env["XCTestConfigurationFilePath"] != nil { return true }
        if env["XCTestBundlePath"] != nil { return true }
        if env["XCTestSessionIdentifier"] != nil { return true }
        if NSClassFromString("XCTestCase") != nil { return true }
        if Bundle.main.bundlePath.hasSuffix(".xctest") { return true }
        return false
        #endif
    }()

    /// The service type the advertiser and browser actually use. (#1701)
    ///
    /// Production and tests shared one hardcoded string, and the test suite
    /// stands up **real** `MCNearbyServiceAdvertiser`s (`PeerManagerTests`
    /// calls `startPeerSync` on a real `PeerManager`). Because the gate runs on
    /// a self-hosted Mac physically beside the owner's devices, fixture peers
    /// —`Test Device`, `Shop Mac`, `Host`, `WPR2-CI-iPad-<run-id>`— were
    /// appearing in the production "Join a Business" picker. The joiner then
    /// auto-selected a CI ghost while the real host displayed a pairing code,
    /// so pairing could not succeed and failed with no usable reason.
    ///
    /// Under test this becomes a per-process value that is unique, so two
    /// managers inside one test process still discover each other, while no
    /// real device can ever see them.
    ///
    /// Bonjour constrains the type to 1–15 characters of letters, digits and
    /// hyphens, with at least one letter and no leading/trailing hyphen —
    /// `"wpr2t-" + 8 hex` is 14, and is validated by
    /// `isValidBonjourServiceType` below.
    private static let serviceType: String = {
        guard isRunningUnderTests else { return productionServiceType }
        return testScopedServiceType()
    }()

    /// Build a per-process service type that can never collide with production.
    static func testScopedServiceType() -> String {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
        let candidate = "wpr2t-\(suffix)"
        // Defensive: a malformed type makes the advertiser fail to start, which
        // would look exactly like the transport bug this code reports on.
        return isValidBonjourServiceType(candidate) ? candidate : "wpr2t-fallback"
    }

    /// RFC 6335 / Bonjour service-type rules, as enforced by `MCNearbyService*`.
    static func isValidBonjourServiceType(_ value: String) -> Bool {
        guard (1...15).contains(value.count) else { return false }
        guard value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return false }
        guard value.contains(where: { $0.isLetter }) else { return false }
        guard !value.hasPrefix("-"), !value.hasSuffix("-") else { return false }
        return !value.contains("--")
    }

    /// The service type in effect for this process. Exposed so a regression
    /// test can assert that a test process is never on the production mesh.
    static var activeServiceType: String { serviceType }

    private let deviceId: String
    private let deviceName: String
    private let companyId: String
    private let allowAnyCompanyPeerDiscovery: Bool
    private let autoInvitePeers: Bool
    private let advertiseSelf: Bool

    /// All mutable state below is GUARDED BY syncQueue — do not access without it.
    private let syncQueue = DispatchQueue(label: "com.wiredpart.multipeer.sync", qos: .utility)
    private var localPeerId: MCPeerID!         // GUARDED BY syncQueue
    private var session: MCSession!             // GUARDED BY syncQueue
    private var advertiser: MCNearbyServiceAdvertiser?  // GUARDED BY syncQueue
    private var browser: MCNearbyServiceBrowser?        // GUARDED BY syncQueue
    private var peers: [String: PeerEntry] = [:]        // GUARDED BY syncQueue
    private var receiveQueue: [ReceivedMultipeerMessage] = []  // GUARDED BY syncQueue
    private var isRunning = false               // GUARDED BY syncQueue
    // Host pairing mode: while a pairing code is active, accept incoming connection
    // invitations from devices in a DIFFERENT company (normally rejected). The
    // pairing code exchanged over the session is the security gate. GUARDED BY syncQueue.
    private var acceptAnyCompanyForPairing = false

    /// Internal peer tracking with MCPeerID association.
    private struct PeerEntry {
        let info: MultipeerPeerInfo
        let mcPeerId: MCPeerID
    }

    public init(
        deviceId: String,
        deviceName: String,
        companyId: String,
        allowAnyCompanyPeerDiscovery: Bool = false,
        autoInvitePeers: Bool = true,
        advertiseSelf: Bool = true
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.companyId = companyId
        self.allowAnyCompanyPeerDiscovery = allowAnyCompanyPeerDiscovery
        self.autoInvitePeers = autoInvitePeers
        self.advertiseSelf = advertiseSelf
        super.init()

        // MCPeerID display name must be 1-63 chars
        let displayName = String(deviceName.prefix(63))
        self.localPeerId = MCPeerID(displayName: displayName.isEmpty ? "WiredPart" : displayName)
        self.session = MCSession(
            peer: localPeerId,
            securityIdentity: nil,
            // #1580 — `.optional`, not `.required`.
            //
            // `.required` makes MCSession refuse to form unless both ends
            // negotiate transport encryption, and it is a well-known source of
            // connections that discover fine and then never connect — the exact
            // field symptom here, across every device combination.
            //
            // This does NOT put company data on the air in the clear. Change
            // payloads are already sealed at the APPLICATION layer with
            // AES-GCM (`SyncCrypto.encryptAESGCM` in `PeerManager`), keyed by
            // the X25519 agreement established during pairing, so transport
            // encryption was a redundant second wrapper. The pairing handshake
            // itself carries only a MAC-style proof bound to a nonce and the
            // participants' PUBLIC keys — safe in the clear by construction.
            //
            // Owner authorization 2026-08-07: "i dont minde there being publice
            // bluetooth fall back to start and encrpting it latter as long as
            // we have the sycing working."
            //
            // `.optional` still uses encryption whenever the peer asks for it,
            // so a device on an older build that still sends `.required` keeps
            // an encrypted link — mixed-build fleets stay compatible during
            // rollout.
            encryptionPreference: .optional
        )
        self.session.delegate = self
    }

    /// Start advertising and browsing for peers.
    public func start() {
        syncQueue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true
            if self.advertiseSelf {
                self.startAdvertising()
            }
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

    /// Host pairing mode. Enable while offering a pairing code (Add a Device) so a
    /// not-yet-in-company device can connect over Bluetooth to complete the code
    /// handshake; disable once pairing is done. No-op safety: defaults to false.
    public func setAcceptAnyCompanyForPairing(_ enabled: Bool) {
        syncQueue.async { [weak self] in
            self?.acceptAnyCompanyForPairing = enabled
        }
    }

    /// Explicitly invite a discovered peer to connect (used by the joiner during
    /// pairing, where auto-invite is off). Returns false if the peer isn't known yet.
    @discardableResult
    public func invite(deviceId: String) -> Bool {
        syncQueue.sync {
            guard let entry = peers[deviceId], let browser = self.browser else { return false }
            let context: [String: String] = [
                "device_id": self.deviceId,
                "device_name": self.deviceName,
                "company_id": self.companyId
            ]
            guard let contextData = try? JSONSerialization.data(withJSONObject: context) else { return false }
            browser.invitePeer(entry.mcPeerId, to: self.session, withContext: contextData, timeout: 30.0)
            return true
        }
    }

    /// Whether the given peer currently has a connected MCSession.
    public func isConnected(toPeer deviceId: String) -> Bool {
        syncQueue.sync { peers[deviceId]?.info.state == .connected }
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

    /// Surface a transport-start failure. Delivered on the main queue so a UI
    /// observer can present it directly. (#1580)
    private func reportTransportError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onTransportError?(message)
        }
    }

    #if DEBUG
    /// Exercises the same main-queue delivery path as a framework transport
    /// start callback. Internal so the Swift package test target can cover the
    /// configured callback chain without exposing a product-facing control.
    func testReportTransportError(_ message: String) {
        reportTransportError(message)
    }
    #endif

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
                        // #1580 — do NOT remove the peer here.
                        //
                        // Discovery lifetime belongs to the BROWSER (foundPeer /
                        // lostPeer). The session only owns *connection* state. A
                        // failed or dropped connection says nothing about whether
                        // the peer is still advertising — and MCSession reports
                        // `.notConnected` routinely when an invitation lapses.
                        //
                        // Removing the entry destroyed the record that
                        // `invite(deviceId:)` looks up, so
                        // `awaitMultipeerConnection`'s re-invite silently no-op'd
                        // (its `false` return is discarded) and `isConnected` could
                        // never become true again. The join then spun out the full
                        // wait and failed with `connectionTimeout` — discovery
                        // green, connection dead — on every device pairing,
                        // regardless of transport.
                        //
                        // Revert to `.found` and let `lostPeer` do the removing.
                        newState = .found
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

            // Find sender's device_id (reads self.peers, requires syncQueue)
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

            // Fix #175: Capture callback, then fire OUTSIDE syncQueue to avoid deadlock.
            // If the callback tries to call any method that uses syncQueue.sync, we would
            // deadlock because syncQueue is a serial queue already holding this block.
            let callback = self.onDataReceived
            DispatchQueue.main.async {
                callback?(message)
            }
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
            // Configured sync is company-scoped. Onboarding/join discovery can
            // show shop computers before this device has a local company ID;
            // the pairing response is still verified before settings are stored.
            guard self.allowAnyCompanyPeerDiscovery || peerCompanyId == self.companyId else { return }

            // Track the peer
            let peerInfo = MultipeerPeerInfo(
                deviceId: peerDeviceId,
                deviceName: peerDeviceName,
                companyId: peerCompanyId,
                state: .found
            )
            self.peers[peerDeviceId] = PeerEntry(info: peerInfo, mcPeerId: peerID)
            self.notifyPeersChanged()

            guard self.autoInvitePeers else { return }

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

    /// The OS refused to start browsing. Previously unimplemented, so a denied
    /// Local Network permission looked identical to "no peers nearby". (#1580)
    public func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error
    ) {
        reportTransportError("BT-SCAN-START — could not start looking for nearby devices: \(error.localizedDescription)")
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
    /// The OS refused to start advertising. Previously unimplemented, so a host
    /// that was never actually discoverable still showed the user a pairing code
    /// and simply waited forever. (#1580)
    public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        reportTransportError("BT-ADV-START — could not make this device discoverable: \(error.localizedDescription)")
    }

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

            // Parse the inviter's identity from the context it sent.
            var peerCompanyId = ""
            var peerDeviceId = ""
            var peerDeviceName = peerID.displayName
            if let contextData = context,
               let json = try? JSONSerialization.jsonObject(with: contextData) as? [String: String] {
                peerCompanyId = json["company_id"] ?? ""
                peerDeviceId = json["device_id"] ?? ""
                peerDeviceName = json["device_name"] ?? peerID.displayName
            }

            // Accept same-company peers, or any company while hosting a pairing
            // code (the code exchanged over the session is the security gate).
            guard peerCompanyId == self.companyId || self.acceptAnyCompanyForPairing else {
                handler(false, nil)
                return
            }

            // Record the inviting peer BEFORE accepting. The joiner does not
            // advertise, so the host's browser never discovers it — without this
            // entry the accepted connection has no peer record, and any reply
            // (e.g. the pairing response) can't be routed with send(toPeer:).
            // `didChange(.connected)` will find this entry by MCPeerID and flip it
            // to `.connected`, at which point send() to it works.
            if !peerDeviceId.isEmpty {
                let info = MultipeerPeerInfo(
                    deviceId: peerDeviceId,
                    deviceName: peerDeviceName,
                    companyId: peerCompanyId,
                    state: .connecting
                )
                self.peers[peerDeviceId] = PeerEntry(info: info, mcPeerId: peerID)
            }
            handler(true, self.session)
        }
    }
}

#endif // canImport(MultipeerConnectivity)
