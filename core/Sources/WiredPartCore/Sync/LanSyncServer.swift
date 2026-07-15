import Foundation
import CryptoKit
import Network
import os

// MARK: - Wire-Format Types

/// Request body for POST /sync/push.
public struct SyncPushRequest: Codable, Sendable {
    public var deviceId: String
    public var companyId: String
    public var lastSyncAt: String?
    public var changes: [IncomingChange]
    public var auth: SyncAuth?

    public init(
        deviceId: String,
        companyId: String,
        lastSyncAt: String? = nil,
        changes: [IncomingChange],
        auth: SyncAuth? = nil
    ) {
        self.deviceId = deviceId
        self.companyId = companyId
        self.lastSyncAt = lastSyncAt
        self.changes = changes
        self.auth = auth
    }

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case companyId = "company_id"
        case lastSyncAt = "last_sync_at"
        case changes
        case auth
    }
}

/// Response body for POST /sync/push.
public struct SyncPushResponse: Codable, Sendable {
    public var accepted: Int
    public var syncBatchId: String

    enum CodingKeys: String, CodingKey {
        case accepted
        case syncBatchId = "sync_batch_id"
    }
}

/// Request body for POST /sync/pull.
public struct SyncPullRequest: Codable, Sendable {
    public var deviceId: String
    public var companyId: String
    public var lastSyncAt: String?
    public var vectorClock: [String: Int64]?
    public var auth: SyncAuth?

    public init(
        deviceId: String,
        companyId: String,
        lastSyncAt: String? = nil,
        vectorClock: [String: Int64]? = nil,
        auth: SyncAuth? = nil
    ) {
        self.deviceId = deviceId
        self.companyId = companyId
        self.lastSyncAt = lastSyncAt
        self.vectorClock = vectorClock
        self.auth = auth
    }

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case companyId = "company_id"
        case lastSyncAt = "last_sync_at"
        case vectorClock = "vector_clock"
        case auth
    }
}

/// Response body for POST /sync/pull.
public struct SyncPullResponse: Codable, Sendable {
    public var changes: [IncomingChange]
    public var syncBatchId: String
    public var serverDeviceId: String

    enum CodingKeys: String, CodingKey {
        case changes
        case syncBatchId = "sync_batch_id"
        case serverDeviceId = "server_device_id"
    }
}

/// Response body for GET /sync/status.
public struct SyncStatusResponse: Codable, Sendable {
    public var deviceId: String
    public var deviceName: String
    public var companyId: String
    public var appVersion: String
    public var pendingChanges: Int
    public var lastSyncAt: String?
    public var port: UInt16

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case deviceName = "device_name"
        case companyId = "company_id"
        case appVersion = "app_version"
        case pendingChanges = "pending_changes"
        case lastSyncAt = "last_sync_at"
        case port
    }
}

// MARK: - Sync Key Response

/// Response body for GET /sync/key.
public struct SyncKeyResponse: Codable, Sendable {
    public let key: String  // base64-encoded X25519 KA public key
}

// MARK: - Pairing

/// Request body for POST /sync/pair.
public struct SyncPairRequest: Codable, Sendable {
    public var deviceId: String
    public var deviceName: String
    public var pairingCode: String?
    public var pairingProof: String?
    public var platform: String?
    /// Bluetooth pairing protocol version. Nil identifies pre-capability clients.
    public var bluetoothProtocolVersion: Int?
    /// X25519 public key bound to this device by the one-time pairing proof.
    public var keyAgreementPublicKey: String?

    public init(
        deviceId: String,
        deviceName: String,
        pairingCode: String? = nil,
        pairingProof: String? = nil,
        platform: String? = nil,
        bluetoothProtocolVersion: Int? = nil,
        keyAgreementPublicKey: String? = nil
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.pairingCode = pairingCode
        self.pairingProof = pairingProof
        self.platform = platform
        self.bluetoothProtocolVersion = bluetoothProtocolVersion
        self.keyAgreementPublicKey = keyAgreementPublicKey
    }

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case deviceName = "device_name"
        case pairingCode = "pairing_code"
        case pairingProof = "pairing_proof"
        case platform
        case bluetoothProtocolVersion = "bluetooth_protocol_version"
        case keyAgreementPublicKey = "key_agreement_public_key"
    }
}

/// Response body for POST /sync/pair.
public struct SyncPairResponse: Codable, Sendable {
    public var accepted: Bool
    public var serverDeviceId: String
    public var companyId: String
    public var pairedAt: String
    /// One-time-session capability used only by Bluetooth onboarding snapshots.
    /// LAN pairing leaves this nil.
    public var bluetoothSnapshotToken: String? = nil
    /// Server's pairing-bound X25519 identity for future encrypted LAN sync.
    public var serverKeyAgreementPublicKey: String? = nil

    enum CodingKeys: String, CodingKey {
        case accepted
        case serverDeviceId = "server_device_id"
        case companyId = "company_id"
        case pairedAt = "paired_at"
        case bluetoothSnapshotToken = "bluetooth_snapshot_token"
        case serverKeyAgreementPublicKey = "server_key_agreement_public_key"
    }
}

/// Encrypted response body for accepted POST /sync/pair.
///
/// The server public key is left in cleartext so the client can derive the
/// ephemeral ECDH key; the accepted pairing payload itself is AES-GCM encrypted.
public struct SyncPairEncryptedResponse: Codable, Sendable {
    public let serverKeyAgreementPublicKey: String
    public let encryptedPayload: String

    public init(serverKeyAgreementPublicKey: String, encryptedPayload: String) {
        self.serverKeyAgreementPublicKey = serverKeyAgreementPublicKey
        self.encryptedPayload = encryptedPayload
    }

    enum CodingKeys: String, CodingKey {
        case serverKeyAgreementPublicKey = "server_key_agreement_public_key"
        case encryptedPayload = "encrypted_payload"
    }
}

// MARK: - Server State (Actor)

/// Thread-safe shared state for the sync server.
///
/// Manages the inbox (changes received from peers) and outbox (changes
/// ready to send), along with device identity and auth configuration.
public actor SyncServerState {
    public let deviceId: String
    public let deviceName: String
    public let companyId: String
    public private(set) var port: UInt16 = 0
    public private(set) var inbox: [IncomingChange] = []
    public private(set) var outbox: [IncomingChange] = []
    public var companyPublicKey: String?     // nil = Phase 4 compat (no cert required)
    public var lastSyncAt: String?
    private var activePairingCodeDigest: Data?
    private var activePairingCodeNormalized: String?
    private let db: AppDatabase?
    private var sessionAuthorizedPeerKeys: [String: String] = [:]

    /// X25519 key agreement public key (base64). Shared with peers via GET /sync/key.
    /// Peers use this to derive a shared AES-GCM key for payload encryption.
    /// Marked nonisolated: it's a let set at init and never changes.
    public nonisolated let kaPublicKeyB64: String
    nonisolated let kaPrivateKeyB64: String    // only used within server handlers

    public init(
        deviceId: String,
        deviceName: String,
        companyId: String,
        companyPublicKey: String? = nil,
        db: AppDatabase? = nil,
        identity: SyncDeviceIdentity? = nil
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.companyId = companyId
        self.companyPublicKey = companyPublicKey
        self.db = db
        if let identity {
            self.kaPrivateKeyB64 = identity.privateKeyB64
            self.kaPublicKeyB64 = identity.publicKeyB64
        } else {
            let (priv, pub) = SyncCrypto.generateKeyAgreementPair()
            self.kaPrivateKeyB64 = priv
            self.kaPublicKeyB64 = pub
        }
    }

    public func appendToInbox(_ changes: [IncomingChange]) {
        var mutableInbox = inbox
        mutableInbox.append(contentsOf: changes)
        inbox = mutableInbox
    }

    public func drainInbox() -> [IncomingChange] {
        let drained = inbox
        inbox = []
        return drained
    }

    public func setOutbox(_ changes: [IncomingChange]) {
        outbox = changes
    }

    public func setPort(_ port: UInt16) {
        self.port = port
    }

    /// Configure the current one-time pairing code issued by the shop.
    public func setActivePairingCode(_ code: String) throws {
        guard let normalized = SyncCrypto.normalizedPairingCode(code) else {
            throw SyncServerError.invalidPairingCode
        }
        activePairingCodeDigest = SyncCrypto.pairingCodeDigest(normalized)
        activePairingCodeNormalized = normalized
    }

    /// Issue and activate a new one-time pairing code for shop-side display.
    public func issueActivePairingCode() throws -> String {
        let code = SyncCrypto.generatePairingCode()
        try setActivePairingCode(code)
        return SyncCrypto.formattedPairingCode(code) ?? code
    }

    /// Clear the active pairing code after it is used or expires.
    public func clearActivePairingCode() {
        activePairingCodeDigest = nil
        activePairingCodeNormalized = nil
    }

    public func verifyPairingCode(_ code: String) -> Bool {
        guard let digest = activePairingCodeDigest else { return false }
        return SyncCrypto.verifyPairingCode(code, expectedDigest: digest)
    }

    public func consumePairingCode(_ code: String) -> Bool {
        guard let digest = activePairingCodeDigest,
              SyncCrypto.verifyPairingCode(code, expectedDigest: digest) else {
            return false
        }
        activePairingCodeDigest = nil
        activePairingCodeNormalized = nil
        return true
    }

    /// Atomically bind a peer's X25519 identity to a valid one-time pairing code.
    public func consumePairingCodeAndRegisterPeer(_ request: SyncPairRequest) throws -> Bool {
        guard activePairingCodeDigest != nil,
              let normalized = activePairingCodeNormalized,
              let key = Self.validKeyAgreementPublicKey(request.keyAgreementPublicKey),
              SyncCrypto.verifyPairingProof(
                request.pairingProof,
                normalizedCode: normalized,
                deviceId: request.deviceId,
                clientPublicKeyB64: key
              ) else {
            return false
        }
        try registerAuthorizedPeer(
            deviceId: request.deviceId,
            deviceName: request.deviceName,
            platform: request.platform,
            keyAgreementPublicKey: key
        )
        activePairingCodeDigest = nil
        activePairingCodeNormalized = nil
        return true
    }

    public func normalizedActivePairingCodeForProof(_ request: SyncPairRequest) -> String? {
        guard activePairingCodeDigest != nil,
              let normalized = activePairingCodeNormalized,
              let key = Self.validKeyAgreementPublicKey(request.keyAgreementPublicKey),
              SyncCrypto.verifyPairingProof(
                request.pairingProof,
                normalizedCode: normalized,
                deviceId: request.deviceId,
                clientPublicKeyB64: key
              ) else {
            return nil
        }
        return normalized
    }

    /// Atomically verify and consume a code-authenticated pairing proof without
    /// transmitting the one-time code. The normalized code is returned only to
    /// the host so it can restore the offer if the trusted response is undelivered.
    public func consumePairingProof(_ request: SyncPairRequest) -> String? {
        guard let normalized = normalizedActivePairingCodeForProof(request) else {
            return nil
        }
        activePairingCodeDigest = nil
        activePairingCodeNormalized = nil
        return normalized
    }

    public func reserveReplay(
        requestId: String,
        deviceId: String,
        endpoint: String,
        direction: String,
        bodyDigest: String
    ) throws -> Bool {
        guard let db else { return true }
        return try db.writer.write { dbConn in
            // Request ids are durable security state, not a time-limited cache.
            // Deleting an accepted id would make captured ciphertext valid again.
            // Keep the reservation for the lifetime of this database; any future
            // compaction must first introduce authenticated monotonic freshness.
            try dbConn.execute(
                sql: """
                    INSERT OR IGNORE INTO _sync_replay_guard (
                        request_id, device_id, endpoint, direction, body_digest, created_at
                    ) VALUES (?, ?, ?, ?, ?, datetime('now'))
                    """,
                arguments: [requestId, deviceId, endpoint, direction, bodyDigest]
            )
            return (try Int.fetchOne(dbConn, sql: "SELECT changes()") ?? 0) == 1
        }
    }

    public func registerAuthorizedPeer(
        deviceId: String,
        deviceName: String,
        platform: String?,
        keyAgreementPublicKey: String
    ) throws {
        guard let key = Self.validKeyAgreementPublicKey(keyAgreementPublicKey) else {
            throw SyncServerError.invalidPeerKey
        }
        if let db {
            try ChangeTracker.registerPeerDevice(
                db: db,
                peerId: deviceId,
                peerName: deviceName,
                platform: platform,
                keyAgreementPublicKey: key
            )
        }
        sessionAuthorizedPeerKeys[deviceId] = key
    }

    public func authorizedPeerKey(deviceId: String) throws -> String? {
        guard let db else { return sessionAuthorizedPeerKeys[deviceId] }
        let encoded = try db.writer.read { dbConn in
            try String.fetchOne(
                dbConn,
                sql: "SELECT certificate FROM _device_registry WHERE device_id = ? AND is_trusted = 1 AND is_deactivated = 0",
                arguments: [deviceId]
            )
        }
        guard let encoded, encoded.hasPrefix("x25519:") else { return nil }
        return Self.validKeyAgreementPublicKey(String(encoded.dropFirst("x25519:".count)))
    }

    private static func validKeyAgreementPublicKey(_ key: String?) -> String? {
        guard let key,
              let data = Data(base64Encoded: key),
              data.count == 32 else { return nil }
        return key
    }

    /// Filter outbox by vector clock (send only what the peer hasn't seen)
    /// or by timestamp (fallback), or return everything (first sync).
    public func getOutboxFiltered(
        vectorClock: [String: Int64]?,
        since: String?
    ) -> [IncomingChange] {
        if let vc = vectorClock {
            let peerLastSeen = vc[deviceId] ?? 0
            return outbox.filter { ($0.id ?? 0) > peerLastSeen }
        } else if let since = since {
            return outbox.filter { $0.timestamp > since }
        } else {
            return outbox
        }
    }
}

// MARK: - LAN Sync Server (Network.framework)

/// HTTP sync server running on the local network using Network.framework.
///
/// Replaces the previous swift-nio implementation with Apple's built-in
/// networking stack — zero external dependencies.
///
/// Endpoints:
/// - `POST /sync/push` — receive changes from peers
/// - `POST /sync/pull` — send our changes to peers
/// - `GET  /sync/status` — health check + device info (no auth)
///
/// Binds to `0.0.0.0:0` so the OS assigns a random available port,
/// which is then advertised via mDNS.
public final class LanSyncServer: Sendable {
    static let maxHTTPRequestBodyBytes = 1_048_576
    private static let contentLengthHeaderPrefix = "content-length:"

    enum ContentLengthParseResult: Equatable {
        case missing
        case valid(Int)
        case invalid
    }

    private let state: SyncServerState
    private let listenerLock = OSAllocatedUnfairLock<NWListener?>(initialState: nil)
    private let logger = Logger(subsystem: "com.wiredpart.core", category: "LanSyncServer")

    public init(state: SyncServerState) {
        self.state = state
    }

    /// Start the server. Returns the OS-assigned port number.
    public func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params, on: .any)
        listenerLock.withLock { $0 = listener }

        let stateRef = self.state
        let loggerRef = self.logger

        return try await withCheckedThrowingContinuation { continuation in
            // Fix #190: Atomic compare-and-set for the resume guard. NWListener's
            // stateUpdateHandler can fire concurrent .ready/.failed events on
            // different queues — a plain Bool check-and-set allows a double-resume
            // window (both threads see false, both set true, both resume) which
            // crashes with a continuation-already-resumed precondition failure.
            let resumedLock = OSAllocatedUnfairLock<Bool>(initialState: false)

            // Returns true if this caller "wins" the race and should resume.
            @Sendable func claimResume() -> Bool {
                resumedLock.withLock { resumed in
                    if resumed { return false }
                    resumed = true
                    return true
                }
            }

            listener.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    guard claimResume() else { return }
                    if let port = listener.port?.rawValue {
                        let assignedPort = port
                        Task { await stateRef.setPort(assignedPort) }
                        continuation.resume(returning: assignedPort)
                    } else {
                        continuation.resume(throwing: SyncServerError.failedToBind)
                    }
                case .failed(let error):
                    guard claimResume() else { return }
                    loggerRef.error("Listener failed: \(error.localizedDescription)")
                    continuation.resume(throwing: SyncServerError.failedToBind)
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.handleConnection(connection)
            }

            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Gracefully shut down the server.
    public func stop() async {
        let listener = listenerLock.withLock { l -> NWListener? in
            let current = l
            l = nil
            return current
        }
        listener?.cancel()
    }

    // MARK: - Connection Handling

    /// Accept a new TCP connection, read the full HTTP request, route it,
    /// and send the HTTP response.
    private func handleConnection(_ connection: NWConnection) {
        let stateRef = self.state
        let loggerRef = self.logger

        connection.start(queue: .global(qos: .userInitiated))

        // Accumulate data until we have the full HTTP request (headers + body).
        // URLSession may split headers and body across TCP packets.
        readFullHTTPRequest(connection: connection, accumulated: Data()) { data in
            guard let data else {
                connection.cancel()
                return
            }

            Task {
                let (status, body) = await Self.routeHTTPRequest(data: data, state: stateRef, logger: loggerRef)
                let response = Self.buildHTTPResponse(status: status, body: body)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    /// Reads from the connection until we have the complete HTTP request
    /// (headers + full body per Content-Length). Calls completion with the
    /// accumulated data, or nil on error.
    private func readFullHTTPRequest(
        connection: NWConnection,
        accumulated: Data,
        completion: @Sendable @escaping (Data?) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let data, error == nil else {
                completion(accumulated.isEmpty ? nil : accumulated)
                return
            }

            var buffer = accumulated
            buffer.append(data)

            // Check if we have the full request
            let separator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
            if let separatorRange = buffer.range(of: separator) {
                // Parse Content-Length from headers
                let headerData = buffer[buffer.startIndex..<separatorRange.lowerBound]
                let bodyStart = separatorRange.upperBound
                let currentBodyLength = buffer.count - bodyStart

                if let headerString = String(data: headerData, encoding: .utf8) {
                    switch Self.parseContentLength(from: headerString) {
                    case .missing:
                        completion(buffer)
                        return
                    case .invalid:
                        completion(buffer)
                        return
                    case .valid(let contentLength) where currentBodyLength >= contentLength:
                        // We have the full request
                        completion(buffer)
                        return
                    case .valid:
                        break
                    }
                }
            }

            // Need more data — keep reading
            if isComplete {
                // Connection closed — use what we have
                completion(buffer)
            } else {
                self?.readFullHTTPRequest(connection: connection, accumulated: buffer, completion: completion)
            }
        }
    }

    /// Extract Content-Length value from raw HTTP header string.
    static func parseContentLength(from headers: String) -> ContentLengthParseResult {
        var parsedLength: Int?

        for line in headers.components(separatedBy: "\r\n") {
            let normalizedLine = line.trimmingCharacters(in: .whitespaces)
            let lower = normalizedLine.lowercased()
            if lower.hasPrefix(contentLengthHeaderPrefix) {
                guard parsedLength == nil else { return .invalid }

                let value = normalizedLine
                    .dropFirst(contentLengthHeaderPrefix.count)
                    .trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty,
                      value.allSatisfy(\.isNumber),
                      let contentLength = Int(value),
                      contentLength <= maxHTTPRequestBodyBytes else {
                    return .invalid
                }
                parsedLength = contentLength
            }
        }

        if let parsedLength {
            return .valid(parsedLength)
        }
        return .missing
    }

    // MARK: - HTTP Parsing & Routing

    /// Parse a raw HTTP/1.1 request and route it to the appropriate handler.
    static func routeHTTPRequest(
        data: Data,
        state: SyncServerState,
        logger: Logger
    ) async -> (Int, Data) {
        guard let request = parseHTTPRequest(data) else {
            let json = #"{"error":"bad_request"}"#
            return (400, Data(json.utf8))
        }

        switch (request.method, request.path) {
        case ("GET", "/sync/status"):
            return await handleStatus(state: state)

        case ("GET", "/sync/key"):
            return await handleKeyExchange(headers: request.headers, state: state)

        case ("POST", "/sync/pair"):
            return await handlePair(body: request.body, state: state)

        case ("POST", "/sync/push"):
            return await handlePush(body: request.body, headers: request.headers, state: state)

        case ("POST", "/sync/pull"):
            return await handlePull(body: request.body, headers: request.headers, state: state)

        default:
            let json = #"{"error":"not_found"}"#
            return (404, Data(json.utf8))
        }
    }

    /// Minimal HTTP/1.1 request parser.
    /// Extracts method, path, headers, and body from raw TCP data.
    private static func parseHTTPRequest(_ data: Data) -> HTTPRequest? {
        // Split headers from body at the \r\n\r\n boundary
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
        guard let separatorRange = data.range(of: separator) else { return nil }

        let headerData = data[data.startIndex..<separatorRange.lowerBound]
        let bodyData = data[separatorRange.upperBound...]

        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let contentLengthResult = parseContentLength(from: headerString)
        guard contentLengthResult != .invalid else { return nil }

        var lines = headerString.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }

        // Parse request line: "GET /sync/status HTTP/1.1"
        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let path = String(parts[1])

        // Parse headers
        var headers: [String: String] = [:]
        for line in lines {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        // Determine body length from Content-Length header
        var body = Data(bodyData)
        if case .valid(let contentLength) = contentLengthResult {
            guard bodyData.count >= contentLength else { return nil }
            body = Data(bodyData.prefix(contentLength))
        }

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }

    /// Build a raw HTTP/1.1 response from status code and JSON body.
    private static func buildHTTPResponse(status: Int, body: Data) -> Data {
        let statusText: String = switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 500: "Internal Server Error"
        default: "Unknown"
        }

        var response = Data()
        let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        response.append(Data(header.utf8))
        response.append(body)
        return response
    }

    // MARK: - Endpoint Handlers

    private static func handleStatus(
        state: SyncServerState
    ) async -> (Int, Data) {
        // Fix #176: This endpoint is unauthenticated (used for LAN discovery/health checks).
        // Return only non-sensitive fields. Device identity, company, pending counts, and
        // last sync time are all information-leak vectors to anyone on the LAN.
        // Full metadata lives behind the authenticated /sync/push and /sync/pull endpoints.
        let serverPort = await state.port
        let response = SyncStatusResponse(
            deviceId: "",           // redacted (was: state.deviceId)
            deviceName: "",         // redacted (was: state.deviceName)
            companyId: "",          // redacted (was: state.companyId)
            appVersion: "1.0.0",    // safe: version probing
            pendingChanges: 0,      // redacted: activity signal
            lastSyncAt: nil,        // redacted: activity signal
            port: serverPort        // safe: already known by caller
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(response)) ?? Data()
        return (200, data)
    }

    /// Return this server's X25519 key agreement public key.
    /// Peers call this before their first encrypted sync to set up the shared key.
    ///
    /// Fix #191: Requires caller to identify their company via the X-Company-ID header.
    /// A device that doesn't already know the company ID cannot initiate an encrypted
    /// session — this prevents unknown LAN peers from pre-computing shared keys.
    private static func handleKeyExchange(headers: [String: String], state: SyncServerState) async -> (Int, Data) {
        let expectedCompanyId = state.companyId
        guard let sentCompanyId = headers["x-company-id"],
              sentCompanyId == expectedCompanyId else {
            let json = #"{"error":"company_id_required"}"#
            return (403, Data(json.utf8))
        }
        guard let peerDeviceId = headers["x-sync-device-id"],
              let authorizedKey = try? await state.authorizedPeerKey(deviceId: peerDeviceId),
              !authorizedKey.isEmpty else {
            let json = #"{"error":"paired_device_required"}"#
            return (403, Data(json.utf8))
        }
        let pubKey = state.kaPublicKeyB64
        let response = SyncKeyResponse(key: pubKey)
        let encoder = JSONEncoder()
        let data = (try? encoder.encode(response)) ?? Data()
        return (200, data)
    }

    private static func handlePair(body: Data, state: SyncServerState) async -> (Int, Data) {
        guard let request = try? JSONDecoder().decode(SyncPairRequest.self, from: body),
              !request.deviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let senderKey = request.keyAgreementPublicKey,
              !senderKey.isEmpty else {
            return (400, Data(#"{"error":"invalid_json"}"#.utf8))
        }
        guard let normalizedCode = await state.normalizedActivePairingCodeForProof(request) else {
            return (403, Data(#"{"error":"invalid_pairing_code"}"#.utf8))
        }
        guard let keyData = try? SyncCrypto.derivePairingSharedKeyData(
                ourPrivateKeyB64: state.kaPrivateKeyB64,
                theirPublicKeyB64: senderKey,
                normalizedCode: normalizedCode,
                clientPublicKeyB64: senderKey,
                serverPublicKeyB64: state.kaPublicKeyB64
              ) else {
            return (400, Data(#"{"error":"invalid_json"}"#.utf8))
        }

        guard (try? await state.consumePairingCodeAndRegisterPeer(request)) == true else {
            let json = #"{"error":"invalid_pairing_code"}"#
            return (403, Data(json.utf8))
        }

        let response = SyncPairResponse(
            accepted: true,
            serverDeviceId: state.deviceId,
            companyId: state.companyId,
            pairedAt: CoreFormatters.nowISO(),
            serverKeyAgreementPublicKey: state.kaPublicKeyB64
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let plainData = try? encoder.encode(response),
              let encrypted = try? SyncCrypto.encryptAESGCM(
                data: plainData,
                keyData: keyData,
                aad: pairingAAD(
                    deviceId: request.deviceId,
                    clientPublicKey: senderKey,
                    serverPublicKey: state.kaPublicKeyB64
                )
              ) else {
            return (500, Data(#"{"error":"pairing_encryption_failed"}"#.utf8))
        }
        let wrapper = SyncPairEncryptedResponse(
            serverKeyAgreementPublicKey: state.kaPublicKeyB64,
            encryptedPayload: encrypted.base64EncodedString()
        )
        guard let data = try? encoder.encode(wrapper) else {
            return (500, Data(#"{"error":"pairing_encryption_failed"}"#.utf8))
        }
        return (200, data)
    }

    private static func pairingAAD(
        deviceId: String,
        clientPublicKey: String,
        serverPublicKey: String
    ) -> Data {
        Data(
            [
                "wiredpart-sync-pairing-response-aad-v1",
                deviceId,
                clientPublicKey,
                serverPublicKey,
            ].joined(separator: "\n").utf8
        )
    }

    private static func handlePush(
        body: Data,
        headers: [String: String],
        state: SyncServerState
    ) async -> (Int, Data) {
        let (plainBody, sharedKeyData, senderDeviceId) = await decryptIfNeeded(
            body: body,
            headers: headers,
            endpoint: "push",
            state: state
        )
        guard let plainBody, let sharedKeyData, let senderDeviceId else {
            let json = #"{"error":"decryption_failed"}"#
            return (400, Data(json.utf8))
        }
        guard (try? await reserveReplay(
            body: body,
            headers: headers,
            endpoint: "push",
            direction: "request",
            senderDeviceId: senderDeviceId,
            state: state
        )) == true else {
            return (409, Data(#"{"error":"replay_detected"}"#.utf8))
        }

        guard let request = try? JSONDecoder().decode(SyncPushRequest.self, from: plainBody) else {
            let json = #"{"error":"invalid_json"}"#
            return (400, Data(json.utf8))
        }
        guard request.deviceId == senderDeviceId else {
            let json = #"{"error":"device_identity_mismatch"}"#
            return (403, Data(json.utf8))
        }

        // Auth check
        if let errorResponse = await checkAuth(
            auth: request.auth ?? SyncAuth(),
            requestCompanyId: request.companyId,
            state: state
        ) {
            return errorResponse
        }

        // Accept changes into inbox
        await state.appendToInbox(request.changes)

        let response = SyncPushResponse(
            accepted: request.changes.count,
            syncBatchId: UUID().uuidString
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let responseData = (try? encoder.encode(response)) ?? Data()
        return encryptIfNeeded(
            responseData,
            sharedKeyData: sharedKeyData,
            aad: syncAAD(
                endpoint: "push",
                direction: "response",
                deviceId: senderDeviceId,
                requestId: headers["x-sync-request-id"] ?? ""
            )
        )
    }

    private static func handlePull(
        body: Data,
        headers: [String: String],
        state: SyncServerState
    ) async -> (Int, Data) {
        let (plainBody, sharedKeyData, senderDeviceId) = await decryptIfNeeded(
            body: body,
            headers: headers,
            endpoint: "pull",
            state: state
        )
        guard let plainBody, let sharedKeyData, let senderDeviceId else {
            let json = #"{"error":"decryption_failed"}"#
            return (400, Data(json.utf8))
        }
        guard (try? await reserveReplay(
            body: body,
            headers: headers,
            endpoint: "pull",
            direction: "request",
            senderDeviceId: senderDeviceId,
            state: state
        )) == true else {
            return (409, Data(#"{"error":"replay_detected"}"#.utf8))
        }

        guard let request = try? JSONDecoder().decode(SyncPullRequest.self, from: plainBody) else {
            let json = #"{"error":"invalid_json"}"#
            return (400, Data(json.utf8))
        }
        guard request.deviceId == senderDeviceId else {
            let json = #"{"error":"device_identity_mismatch"}"#
            return (403, Data(json.utf8))
        }

        // Auth check
        if let errorResponse = await checkAuth(
            auth: request.auth ?? SyncAuth(),
            requestCompanyId: request.companyId,
            state: state
        ) {
            return errorResponse
        }

        // Filter outbox
        let changes = await state.getOutboxFiltered(
            vectorClock: request.vectorClock,
            since: request.lastSyncAt
        )

        let response = SyncPullResponse(
            changes: changes,
            syncBatchId: UUID().uuidString,
            serverDeviceId: state.deviceId
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let responseData = (try? encoder.encode(response)) ?? Data()
        return encryptIfNeeded(
            responseData,
            sharedKeyData: sharedKeyData,
            aad: syncAAD(
                endpoint: "pull",
                direction: "response",
                deviceId: senderDeviceId,
                requestId: headers["x-sync-request-id"] ?? ""
            )
        )
    }

    /// Require an encrypted request from a pairing-bound device/key identity.
    private static func decryptIfNeeded(
        body: Data,
        headers: [String: String],
        endpoint: String,
        state: SyncServerState
    ) async -> (plainBody: Data?, sharedKeyData: Data?, senderDeviceId: String?) {
        guard headers["x-sync-encrypted"] == "1",
              let senderKAKey = headers["x-sync-sender-key"],
              !senderKAKey.isEmpty,
              let senderDeviceId = headers["x-sync-device-id"],
              let requestId = headers["x-sync-request-id"],
              !requestId.isEmpty,
              let authorizedKey = try? await state.authorizedPeerKey(deviceId: senderDeviceId),
              authorizedKey == senderKAKey else {
            return (nil, nil, nil)
        }
        let ourPrivateKey = state.kaPrivateKeyB64
        guard let keyData = try? SyncCrypto.deriveSharedKeyData(
            ourPrivateKeyB64: ourPrivateKey,
            theirPublicKeyB64: senderKAKey
        ) else { return (nil, nil, nil) }

        let aad = syncAAD(
            endpoint: endpoint,
            direction: "request",
            deviceId: senderDeviceId,
            requestId: requestId
        )
        guard let plainBody = try? SyncCrypto.decryptAESGCM(data: body, keyData: keyData, aad: aad) else {
            return (nil, nil, nil)
        }
        return (plainBody, keyData, senderDeviceId)
    }

    /// Encrypt every successful sync response; plaintext sessions are rejected above.
    private static func encryptIfNeeded(_ data: Data, sharedKeyData keyData: Data, aad: Data) -> (Int, Data) {
        guard let encrypted = try? SyncCrypto.encryptAESGCM(data: data, keyData: keyData, aad: aad) else {
            // Encryption failed despite having a key — fail closed, never send plaintext.
            let errorJson = #"{"error":"encryption_failed"}"#
            return (500, Data(errorJson.utf8))
        }
        return (200, encrypted)
    }

    static func syncAAD(endpoint: String, direction: String, deviceId: String, requestId: String) -> Data {
        Data(
            [
                "wiredpart-sync-lan-payload-aad-v1",
                endpoint,
                direction,
                deviceId,
                requestId,
            ].joined(separator: "\n").utf8
        )
    }

    private static func reserveReplay(
        body: Data,
        headers: [String: String],
        endpoint: String,
        direction: String,
        senderDeviceId: String,
        state: SyncServerState
    ) async throws -> Bool {
        guard let requestId = headers["x-sync-request-id"], !requestId.isEmpty else {
            return false
        }
        let digest = Data(SHA256.hash(data: body)).base64EncodedString()
        return try await state.reserveReplay(
            requestId: requestId,
            deviceId: senderDeviceId,
            endpoint: endpoint,
            direction: direction,
            bodyDigest: digest
        )
    }

    // MARK: - Auth

    /// Check authentication for push/pull requests.
    /// Returns nil if auth passed, or an error response tuple if it failed.
    private static func checkAuth(
        auth: SyncAuth,
        requestCompanyId: String,
        state: SyncServerState
    ) async -> (Int, Data)? {
        let serverCompanyId = state.companyId
        let companyPublicKey = await state.companyPublicKey

        // Company ID must match
        if requestCompanyId != serverCompanyId {
            let json = #"{"error":"company_id_mismatch"}"#
            return (403, Data(json.utf8))
        }

        // Verify certificate if company key is configured
        let result = SyncCrypto.verifySyncAuth(
            auth: auth,
            expectedCompanyId: serverCompanyId,
            companyPublicKeyB64: companyPublicKey
        )

        switch result {
        case .verified, .allowedNoKey:
            return nil // Auth passed

        case .required:
            let json = #"{"error":"certificate_required"}"#
            return (401, Data(json.utf8))

        case .rejected(let reason):
            // Fix #184: reason comes from an untrusted certificate — encode with JSONEncoder
            // so special characters (", \, etc.) are escaped rather than injected into the string.
            struct CertRejectedError: Encodable { let error: String; let reason: String }
            let obj = CertRejectedError(error: "certificate_rejected", reason: reason)
            let data = (try? JSONEncoder().encode(obj))
                ?? Data(#"{"error":"certificate_rejected","reason":"unknown"}"#.utf8)
            return (403, data)
        }
    }
}

public enum SyncServerError: Error {
    case failedToBind
    case invalidPairingCode
    case invalidPeerKey
    case serverNotRunning
}

// MARK: - Parsed HTTP Request

/// Simple parsed HTTP/1.1 request used internally by the sync server.
private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}
