import Foundation
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

    public init(
        deviceId: String,
        deviceName: String,
        companyId: String,
        companyPublicKey: String? = nil
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.companyId = companyId
        self.companyPublicKey = companyPublicKey
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

// MARK: - LAN Sync Server

/// HTTP sync server running on the local network.
///
/// Ported from: `src-tauri/src/sync_server.rs`
///
/// Endpoints:
/// - `POST /sync/push` — receive changes from peers
/// - `POST /sync/pull` — send our changes to peers
/// - `GET  /sync/status` — health check + device info (no auth)
///
/// Uses Network.framework `NWListener` for TCP connections and a
/// minimal HTTP/1.1 parser. Binds to `0.0.0.0:0` so the OS assigns
/// a random available port, which is then advertised via mDNS.
public final class LanSyncServer: Sendable {
    private let state: SyncServerState
    private let listenerLock = OSAllocatedUnfairLock<NWListener?>(initialState: nil)
    private let connectionsLock = OSAllocatedUnfairLock<[NWConnection]>(initialState: [])

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

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false

            listener.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    guard !resumed else { return }
                    resumed = true
                    if let port = listener.port?.rawValue {
                        let assignedPort = UInt16(port)
                        Task { await stateRef.setPort(assignedPort) }
                        continuation.resume(returning: assignedPort)
                    } else {
                        continuation.resume(throwing: SyncServerError.failedToBind)
                    }

                case .failed(let error):
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(throwing: error)

                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.connectionsLock.withLock { $0.append(connection) }
                self.handleConnection(connection, state: stateRef)
            }

            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Gracefully shut down the server.
    public func stop() async throws {
        let listener = listenerLock.withLock { l -> NWListener? in
            let ref = l
            l = nil
            return ref
        }
        listener?.cancel()

        let connections = connectionsLock.withLock { c -> [NWConnection] in
            let ref = c
            c = []
            return ref
        }
        for conn in connections {
            conn.cancel()
        }
    }

    // MARK: - Connection Handling

    /// Accept a single TCP connection, read the HTTP request, and respond.
    private func handleConnection(_ connection: NWConnection, state: SyncServerState) {
        connection.start(queue: .global(qos: .userInitiated))

        // Read up to 1 MB of data (covers any reasonable sync payload).
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error = error {
                os_log(.error, "[LanSyncServer] Connection receive error: %{public}@", "\(error)")
                connection.cancel()
                self.removeConnection(connection)
                return
            }

            guard let data = data, !data.isEmpty else {
                if isComplete {
                    connection.cancel()
                    self.removeConnection(connection)
                }
                return
            }

            // Parse and handle the HTTP request asynchronously.
            Task {
                let (statusCode, statusText, responseBody) = await Self.processHTTPRequest(data: data, state: state)
                let responseData = Self.buildHTTPResponse(statusCode: statusCode, statusText: statusText, body: responseBody)

                connection.send(content: responseData, completion: .contentProcessed { _ in
                    connection.cancel()
                    self.removeConnection(connection)
                })
            }
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        connectionsLock.withLock { connections in
            connections.removeAll { $0 === connection }
        }
    }

    // MARK: - HTTP Parsing

    /// Minimal HTTP/1.1 request parser. Extracts method, path, and body.
    private static func parseHTTPRequest(data: Data) -> (method: String, path: String, body: Data)? {
        // Find the end of headers (\r\n\r\n)
        let crlfcrlf = Data([0x0D, 0x0A, 0x0D, 0x0A])
        guard let headerEndRange = data.range(of: crlfcrlf) else {
            // Might be a partial read — try just \n\n as fallback
            let lflf = Data([0x0A, 0x0A])
            guard let altRange = data.range(of: lflf) else { return nil }
            let headerData = data[data.startIndex..<altRange.lowerBound]
            let body = data[altRange.upperBound...]
            return parseRequestLine(headerData: headerData, body: Data(body))
        }

        let headerData = data[data.startIndex..<headerEndRange.lowerBound]
        let body = data[headerEndRange.upperBound...]
        return parseRequestLine(headerData: headerData, body: Data(body))
    }

    private static func parseRequestLine(headerData: Data, body: Data) -> (method: String, path: String, body: Data)? {
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerString.components(separatedBy: .newlines)
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let path = String(parts[1])

        return (method, path, body)
    }

    // MARK: - Request Routing

    /// Route and handle the HTTP request. Returns (statusCode, statusText, body).
    private static func processHTTPRequest(
        data: Data,
        state: SyncServerState
    ) async -> (Int, String, Data) {
        guard let parsed = parseHTTPRequest(data: data) else {
            let json = #"{"error":"bad_request"}"#
            return (400, "Bad Request", json.data(using: .utf8)!)
        }

        switch (parsed.method, parsed.path) {
        case ("GET", "/sync/status"):
            return await handleStatus(state: state)

        case ("POST", "/sync/push"):
            return await handlePush(body: parsed.body, state: state)

        case ("POST", "/sync/pull"):
            return await handlePull(body: parsed.body, state: state)

        default:
            let json = #"{"error":"not_found"}"#
            return (404, "Not Found", json.data(using: .utf8)!)
        }
    }

    // MARK: - Endpoint Handlers

    private static func handleStatus(
        state: SyncServerState
    ) async -> (Int, String, Data) {
        let pendingCount = await state.outbox.count
        let syncAt = await state.lastSyncAt
        let serverPort = await state.port
        let response = SyncStatusResponse(
            deviceId: state.deviceId,
            deviceName: state.deviceName,
            companyId: state.companyId,
            appVersion: "1.0.0",
            pendingChanges: pendingCount,
            lastSyncAt: syncAt,
            port: serverPort
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(response)) ?? Data()
        return (200, "OK", data)
    }

    private static func handlePush(
        body: Data,
        state: SyncServerState
    ) async -> (Int, String, Data) {
        guard let request = try? JSONDecoder().decode(SyncPushRequest.self, from: body) else {
            let json = #"{"error":"invalid_json"}"#
            return (400, "Bad Request", json.data(using: .utf8)!)
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
        let data = (try? encoder.encode(response)) ?? Data()
        return (200, "OK", data)
    }

    private static func handlePull(
        body: Data,
        state: SyncServerState
    ) async -> (Int, String, Data) {
        guard let request = try? JSONDecoder().decode(SyncPullRequest.self, from: body) else {
            let json = #"{"error":"invalid_json"}"#
            return (400, "Bad Request", json.data(using: .utf8)!)
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
        let data = (try? encoder.encode(response)) ?? Data()
        return (200, "OK", data)
    }

    // MARK: - Auth

    /// Check authentication for push/pull requests.
    /// Returns nil if auth passed, or an error response tuple if it failed.
    private static func checkAuth(
        auth: SyncAuth,
        requestCompanyId: String,
        state: SyncServerState
    ) async -> (Int, String, Data)? {
        let serverCompanyId = state.companyId
        let companyPublicKey = await state.companyPublicKey

        // Company ID must match
        if requestCompanyId != serverCompanyId {
            let json = #"{"error":"company_id_mismatch"}"#
            return (403, "Forbidden", json.data(using: .utf8)!)
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
            return (401, "Unauthorized", json.data(using: .utf8)!)

        case .rejected(let reason):
            let json = "{\"error\":\"certificate_rejected\",\"reason\":\"\(reason)\"}"
            return (403, "Forbidden", json.data(using: .utf8)!)
        }
    }

    // MARK: - Response Builder

    /// Build a raw HTTP/1.1 response with JSON content type.
    private static func buildHTTPResponse(statusCode: Int, statusText: String, body: Data) -> Data {
        var response = Data()
        let header = "HTTP/1.1 \(statusCode) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        response.append(header.data(using: .utf8)!)
        response.append(body)
        return response
    }
}

public enum SyncServerError: Error {
    case failedToBind
}
