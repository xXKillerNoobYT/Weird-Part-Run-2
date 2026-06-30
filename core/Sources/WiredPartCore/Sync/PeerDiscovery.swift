import Foundation
import Network
import os.log
import Darwin

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
/// TXT records: `device_id`, `device_name`, `company_id`, `version`, `sync_port`
/// Instance name: `WiredPart-{device_id[0..<8]}`
///
/// Filtering: Only peers from the same company are reported unless bootstrap
/// onboarding discovery explicitly allows any company before this device has
/// received and persisted the verified company ID.
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
public final class PeerDiscovery: NSObject, @unchecked Sendable {

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
    private let allowAnyCompanyPeerDiscovery: Bool

    private let queue = DispatchQueue(label: "com.wiredpart.peer-discovery", qos: .utility)
    private let logger = Logger(subsystem: "com.wiredpart.core", category: "PeerDiscovery")
    private var browser: NWBrowser?
    private var advertisedService: NetService?
    private var peers: [String: DiscoveredPeer] = [:]  // keyed by device_id
    private var isRunning = false
    private var browseGeneration = 0
    private var usesDedicatedAdvertisingListener = false

    public init(
        deviceId: String,
        companyId: String,
        deviceName: String,
        port: UInt16,
        allowAnyCompanyPeerDiscovery: Bool = false
    ) {
        self.deviceId = deviceId
        self.companyId = companyId
        self.deviceName = deviceName
        self.port = port
        self.allowAnyCompanyPeerDiscovery = allowAnyCompanyPeerDiscovery
        super.init()
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
            self.advertisedService?.stop()
            self.advertisedService = nil
            self.peers.removeAll()
        }
    }

    /// Get current snapshot of discovered peers.
    public func getPeers() -> [DiscoveredPeer] {
        queue.sync {
            Array(peers.values)
        }
    }

    #if DEBUG
    /// Test hook for the LAN advertisement ownership contract.
    public func debugUsesDedicatedAdvertisingListener() -> Bool {
        queue.sync { usesDedicatedAdvertisingListener }
    }
    #endif

    // MARK: - Private: Advertising

    private func startAdvertising() {
        usesDedicatedAdvertisingListener = false
        let txtData: [String: Data] = [
            "device_id": deviceId,
            "device_name": deviceName,
            "company_id": companyId,
            "version": "1.0.0",
            "sync_port": String(port)
        ].compactMapValues { $0.data(using: .utf8) }

        // Instance name: first 8 chars of device_id
        let shortId = String(deviceId.prefix(8))
        let instanceName = "WiredPart-\(shortId)"

        let txtRecord = NetService.data(fromTXTRecord: txtData)

        // Advertise the already-running LanSyncServer port. Do not create an
        // NWListener here: binding a second listener to the sync server port
        // fails on devices and can make discovery appear offline.
        let service = NetService(
            domain: "local.",
            type: "_wiredpart._tcp.",
            name: instanceName,
            port: Int32(port)
        )
        service.delegate = self
        service.setTXTRecord(txtRecord)
        service.schedule(in: .main, forMode: .default)
        service.publish()
        self.advertisedService = service
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
        browseGeneration += 1
        let generation = browseGeneration
        var seenPeerIds: Set<String> = []

        for result in results {
            guard case .service(let name, let type, let domain, _) = result.endpoint else {
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
            let peerPort = UInt16(txtDict["sync_port"] ?? "") ?? 0

            // Filter: skip self
            guard peerDeviceId != deviceId else { continue }
            // Filter: same company only unless this is first-run onboarding.
            guard allowAnyCompanyPeerDiscovery || peerCompanyId == companyId else { continue }
            seenPeerIds.insert(peerDeviceId)

            resolveBonjourService(
                name: name,
                type: type,
                domain: domain,
                fallbackPort: peerPort,
                generation: generation
            ) { [weak self] endpoint in
                guard let self, let endpoint else { return }
                self.queue.async { [weak self] in
                    guard let self, self.isRunning, self.browseGeneration == generation else { return }
                    let peer = DiscoveredPeer(
                        deviceId: peerDeviceId,
                        deviceName: peerDeviceName,
                        companyId: peerCompanyId,
                        host: endpoint.host,
                        port: endpoint.port,
                        version: peerVersion,
                        transport: "lan"
                    )
                    self.peers[peerDeviceId] = peer
                    self.notifyPeersChangedFromQueue()
                }
            }
        }

        peers = peers.filter { seenPeerIds.contains($0.key) }
        notifyPeersChangedFromQueue()
    }

    private func notifyPeersChangedFromQueue() {
        let snapshot = Array(peers.values)
        // Fix #187: capture the callback under the lock so it can't race with a reassignment.
        let callback = callbackLock.withLock { _onPeersChanged }
        if let callback {
            DispatchQueue.main.async {
                callback(snapshot)
            }
        }
    }

    private func resolveBonjourService(
        name: String,
        type: String,
        domain: String,
        fallbackPort: UInt16,
        generation: Int,
        completion: @escaping @Sendable (ResolvedBonjourEndpoint?) -> Void
    ) {
        Task.detached(priority: .utility) {
            let resolved = BonjourServiceResolver.resolve(
                name: name,
                type: type,
                domain: domain,
                fallbackPort: fallbackPort,
                timeout: 3
            )
            completion(resolved)
        }
    }
}

private struct ResolvedBonjourEndpoint: Sendable {
    let host: String
    let port: UInt16
}

private final class BonjourServiceResolver: NSObject, NetServiceDelegate {
    private var resolvedEndpoint: ResolvedBonjourEndpoint?
    private var finished = false
    private let fallbackPort: UInt16

    private init(fallbackPort: UInt16) {
        self.fallbackPort = fallbackPort
    }

    static func resolve(
        name: String,
        type: String,
        domain: String,
        fallbackPort: UInt16,
        timeout: TimeInterval
    ) -> ResolvedBonjourEndpoint? {
        let resolver = BonjourServiceResolver(fallbackPort: fallbackPort)
        let service = NetService(
            domain: normalizeDNSLabel(domain.isEmpty ? "local" : domain),
            type: normalizeDNSLabel(type),
            name: name
        )
        service.delegate = resolver
        service.resolve(withTimeout: timeout)

        let deadline = Date().addingTimeInterval(timeout)
        while !resolver.finished && Date() < deadline {
            RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.05)))
        }

        service.stop()
        service.delegate = nil
        return resolver.resolvedEndpoint
    }

    private static func normalizeDNSLabel(_ value: String) -> String {
        value.hasSuffix(".") ? value : "\(value)."
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let resolvedPort = UInt16(exactly: sender.port) ?? fallbackPort
        guard resolvedPort > 0 else {
            finished = true
            return
        }

        if let host = sender.addresses?.compactMap(Self.host(from:)).first {
            resolvedEndpoint = ResolvedBonjourEndpoint(host: host, port: resolvedPort)
        }
        finished = true
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        finished = true
    }

    private static func host(from address: Data) -> String? {
        address.withUnsafeBytes { rawBuffer -> String? in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            let sockaddrPointer = baseAddress.assumingMemoryBound(to: sockaddr.self)
            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                sockaddrPointer,
                socklen_t(address.count),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { return nil }
            let count = hostBuffer.firstIndex(of: 0) ?? hostBuffer.count
            let bytes = hostBuffer.prefix(count).map { UInt8(bitPattern: $0) }
            return String(decoding: bytes, as: UTF8.self)
        }
    }
}

extension PeerDiscovery: NetServiceDelegate {
    public func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        logger.error("[PeerDiscovery] Bonjour publish failed: \(String(describing: errorDict))")
    }
}
