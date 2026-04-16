import Foundation
import Network
import os.log

// MARK: - DiscoveredPeer

/// A peer device found on the local network via mDNS (Bonjour).
public struct DiscoveredPeer: Sendable, Identifiable {
    public let id: String              // device_id (used as Identifiable ID)
    public let deviceId: String
    public let deviceName: String
    public let companyId: String
    public let host: String            // IPv4 address
    public let port: UInt16
    public let version: String
    public let discoveredAt: String    // ISO 8601 UTC
    public let transport: String       // "lan" or "multipeer"
    public var multipeerState: String? // "found", "connecting", "connected"

    public init(
        deviceId: String,
        deviceName: String,
        companyId: String,
        host: String,
        port: UInt16,
        version: String = "1.0.0",
        discoveredAt: String? = nil,
        transport: String = "lan",
        multipeerState: String? = nil
    ) {
        self.id = deviceId
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.companyId = companyId
        self.host = host
        self.port = port
        self.version = version
        self.discoveredAt = discoveredAt ?? Self.currentTimestamp()
        self.transport = transport
        self.multipeerState = multipeerState
    }

    private static func currentTimestamp() -> String { CoreFormatters.iso8601Fractional.string(from: Date()) }
}

// MARK: - PeerDiscovery

/// mDNS (Bonjour) service discovery for LAN peer sync.
///
/// Ported from: `src-tauri/src/discovery.rs`
///
/// Uses Network.framework's NWBrowser and NWListener to discover
/// and advertise WiredPart devices on the local network.
///
/// Service type: `_wiredpart._tcp`
/// TXT records: `device_id`, `device_name`, `company_id`, `version`
/// Instance name: `WiredPart-{device_id[0..<8]}`
///
/// Filtering: Only peers from the same company are reported.
/// Self-discovery is filtered out by device_id.
///
/// CONCURRENCY INVARIANT (#222 — `@unchecked Sendable` contract):
/// - `queue` is a serial DispatchQueue that serializes ALL access to the
///   mutable stored properties (`browser`, `listener`, `peers`, `isRunning`).
///   Do not access these from outside `queue.async` / `queue.sync`.
/// - `onPeersChanged` is the one exception: it's a user-settable callback
///   guarded by its own `callbackLock` (NSLock) because clients may set it
///   from any queue. See #187 for the setter protection.
/// - Any NEW mutable property MUST either go through `queue` or get its own
///   lock. Adding a bare `var` is a data race that the compiler won't catch.
public final class PeerDiscovery: @unchecked Sendable {

    /// Called when the peer list changes.
    ///
    /// Thread-safe setter (fix #187): assigning this property takes an internal
    /// lock so it can't race with the callback-firing path. The callback itself
    /// is always invoked on the main queue (safe for UI updates).
    public var onPeersChanged: (([DiscoveredPeer]) -> Void)? {
        get { callbackLock.withLock { _onPeersChanged } }
        set { callbackLock.withLock { _onPeersChanged = newValue } }
    }
    private var _onPeersChanged: (([DiscoveredPeer]) -> Void)?
    private let callbackLock = NSLock()

    private let deviceId: String
    private let companyId: String
    private let deviceName: String
    private let port: UInt16

    private let queue = DispatchQueue(label: "com.wiredpart.peer-discovery", qos: .utility)
    private let logger = Logger(subsystem: "com.wiredpart.core", category: "PeerDiscovery")
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var peers: [String: DiscoveredPeer] = [:]  // keyed by device_id
    private var isRunning = false

    public init(
        deviceId: String,
        companyId: String,
        deviceName: String,
        port: UInt16
    ) {
        self.deviceId = deviceId
        self.companyId = companyId
        self.deviceName = deviceName
        self.port = port
    }

    /// Start advertising this device and browsing for peers.
    public func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true
            self.startAdvertising()
            self.startBrowsing()
        }
    }

    /// Stop advertising and browsing.
    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.browser?.cancel()
            self.browser = nil
            self.listener?.cancel()
            self.listener = nil
            self.peers.removeAll()
        }
    }

    /// Get current snapshot of discovered peers.
    public func getPeers() -> [DiscoveredPeer] {
        queue.sync {
            Array(peers.values)
        }
    }

    // MARK: - Private: Advertising

    private func startAdvertising() {
        let txtData: [String: String] = [
            "device_id": deviceId,
            "device_name": deviceName,
            "company_id": companyId,
            "version": "1.0.0"
        ]

        // Build TXT record
        let txtRecord = NWTXTRecord(txtData)

        // Instance name: first 8 chars of device_id
        let shortId = String(deviceId.prefix(8))
        let instanceName = "WiredPart-\(shortId)"

        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port) ?? .any)
            listener.service = NWListener.Service(
                name: instanceName,
                type: "_wiredpart._tcp",
                txtRecord: txtRecord
            )
            listener.stateUpdateHandler = { [logger] state in
                switch state {
                case .ready:
                    break // Advertising active
                case .failed(let error):
                    logger.error("[PeerDiscovery] Listener failed: \(error)")
                default:
                    break
                }
            }
            // We don't actually accept connections on this listener —
            // it's only used for mDNS advertisement. The real HTTP server
            // is the LanSyncServer. Auto-reject any incoming connections.
            listener.newConnectionHandler = { connection in
                connection.cancel()
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            logger.error("[PeerDiscovery] Failed to create listener: \(error)")
        }
    }

    // MARK: - Private: Browsing

    private func startBrowsing() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_wiredpart._tcp", domain: nil)
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: descriptor, using: parameters)
        browser.stateUpdateHandler = { [logger] state in
            switch state {
            case .ready:
                break // Browsing active
            case .failed(let error):
                logger.error("[PeerDiscovery] Browser failed: \(error)")
            default:
                break
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self else { return }
            self.handleBrowseResults(results)
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        var updatedPeers: [String: DiscoveredPeer] = [:]

        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else {
                continue
            }

            // Extract TXT record from metadata
            guard case .bonjour(let txtRecord) = result.metadata else {
                continue
            }

            let txtDict = txtRecord.dictionary
            let peerDeviceId = txtDict["device_id"] ?? ""
            let peerDeviceName = txtDict["device_name"] ?? name
            let peerCompanyId = txtDict["company_id"] ?? ""
            let peerVersion = txtDict["version"] ?? "unknown"

            // Filter: skip self
            guard peerDeviceId != deviceId else { continue }
            // Filter: same company only
            guard peerCompanyId == companyId else { continue }

            // Extract host/port from the endpoint
            // NWBrowser results don't directly expose IP/port — those are
            // resolved when a connection is made. For our purposes we store
            // the service name; the peer manager will connect using the
            // NWEndpoint directly or resolve the service.
            let peer = DiscoveredPeer(
                deviceId: peerDeviceId,
                deviceName: peerDeviceName,
                companyId: peerCompanyId,
                host: name,  // Service name — resolved at connection time
                port: port,  // Advertised port from TXT
                version: peerVersion,
                transport: "lan"
            )
            updatedPeers[peerDeviceId] = peer
        }

        peers = updatedPeers
        let snapshot = Array(updatedPeers.values)
        // Fix #187: capture the callback under the lock so it can't race with a reassignment.
        let callback = callbackLock.withLock { _onPeersChanged }
        if let callback {
            DispatchQueue.main.async {
                callback(snapshot)
            }
        }
    }
}

