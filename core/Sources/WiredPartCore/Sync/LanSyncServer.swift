import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOFoundationCompat
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
/// Uses swift-nio for HTTP/1.1 framing. Binds to `0.0.0.0:0`
/// so the OS assigns a random available port, which is then
/// advertised via mDNS.
public final class LanSyncServer: Sendable {
    private let state: SyncServerState
    private let group: EventLoopGroup
    private let channelLock = OSAllocatedUnfairLock<Channel?>(initialState: nil)

    public init(state: SyncServerState) {
        self.state = state
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    /// Start the server. Returns the OS-assigned port number.
    public func start() async throws -> UInt16 {
        let stateRef = self.state

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 256)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(SyncHTTPHandler(state: stateRef))
                }
            }
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)

        let channel = try await bootstrap.bind(host: "0.0.0.0", port: 0).get()
        channelLock.withLock { $0 = channel }

        guard let localAddress = channel.localAddress,
              let port = localAddress.port else {
            throw SyncServerError.failedToBind
        }

        let assignedPort = UInt16(port)
        await state.setPort(assignedPort)
        return assignedPort
    }

    /// Gracefully shut down the server.
    public func stop() async throws {
        let channel = channelLock.withLock { ch -> Channel? in
            let c = ch
            ch = nil
            return c
        }
        try await channel?.close()
        try await group.shutdownGracefully()
    }
}

public enum SyncServerError: Error {
    case failedToBind
}

// MARK: - HTTP Handler

/// NIO channel handler that routes HTTP requests to sync endpoints.
private final class SyncHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let state: SyncServerState
    private var requestHead: HTTPRequestHead?
    private var bodyBuffer: ByteBuffer?

    init(state: SyncServerState) {
        self.state = state
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            requestHead = head
            bodyBuffer = context.channel.allocator.buffer(capacity: 0)

        case .body(var body):
            bodyBuffer?.writeBuffer(&body)

        case .end:
            guard let head = requestHead else { return }
            let body = bodyBuffer ?? context.channel.allocator.buffer(capacity: 0)

            let stateRef = self.state

            // Use NIO's promise pattern to bridge async actor calls back to the event loop.
            let promise = context.eventLoop.makePromise(of: (HTTPResponseStatus, Data).self)
            promise.completeWithTask {
                await Self.handleRequest(head: head, body: body, state: stateRef)
            }
            promise.futureResult.whenComplete { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let (status, responseData)):
                    self.sendResponse(context: context, status: status, body: responseData)
                case .failure:
                    let json = #"{"error":"internal_error"}"#
                    self.sendResponse(context: context, status: .internalServerError, body: json.data(using: .utf8)!)
                }
            }

            requestHead = nil
            bodyBuffer = nil
        }
    }

    /// Route and handle the request.
    private static func handleRequest(
        head: HTTPRequestHead,
        body: ByteBuffer,
        state: SyncServerState
    ) async -> (HTTPResponseStatus, Data) {
        let method = head.method
        let uri = head.uri

        switch (method, uri) {
        case (.GET, "/sync/status"):
            return await handleStatus(state: state)

        case (.POST, "/sync/push"):
            return await handlePush(body: body, state: state)

        case (.POST, "/sync/pull"):
            return await handlePull(body: body, state: state)

        default:
            let json = #"{"error":"not_found"}"#
            return (.notFound, json.data(using: .utf8)!)
        }
    }

    // MARK: - Endpoint Handlers

    private static func handleStatus(
        state: SyncServerState
    ) async -> (HTTPResponseStatus, Data) {
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
        return (.ok, data)
    }

    private static func handlePush(
        body: ByteBuffer,
        state: SyncServerState
    ) async -> (HTTPResponseStatus, Data) {
        let bodyData = Data(buffer: body)

        guard let request = try? JSONDecoder().decode(SyncPushRequest.self, from: bodyData) else {
            let json = #"{"error":"invalid_json"}"#
            return (.badRequest, json.data(using: .utf8)!)
        }

        // Auth check
        let authResult = await checkAuth(
            auth: request.auth ?? SyncAuth(),
            requestCompanyId: request.companyId,
            state: state
        )
        if let errorResponse = authResult {
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
        return (.ok, data)
    }

    private static func handlePull(
        body: ByteBuffer,
        state: SyncServerState
    ) async -> (HTTPResponseStatus, Data) {
        let bodyData = Data(buffer: body)

        guard let request = try? JSONDecoder().decode(SyncPullRequest.self, from: bodyData) else {
            let json = #"{"error":"invalid_json"}"#
            return (.badRequest, json.data(using: .utf8)!)
        }

        // Auth check
        let authResult = await checkAuth(
            auth: request.auth ?? SyncAuth(),
            requestCompanyId: request.companyId,
            state: state
        )
        if let errorResponse = authResult {
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
        return (.ok, data)
    }

    // MARK: - Auth

    /// Check authentication for push/pull requests.
    /// Returns nil if auth passed, or an error response tuple if it failed.
    private static func checkAuth(
        auth: SyncAuth,
        requestCompanyId: String,
        state: SyncServerState
    ) async -> (HTTPResponseStatus, Data)? {
        let serverCompanyId = state.companyId
        let companyPublicKey = await state.companyPublicKey

        // Company ID must match
        if requestCompanyId != serverCompanyId {
            let json = #"{"error":"company_id_mismatch"}"#
            return (.forbidden, json.data(using: .utf8)!)
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
            return (.unauthorized, json.data(using: .utf8)!)

        case .rejected(let reason):
            let json = "{\"error\":\"certificate_rejected\",\"reason\":\"\(reason)\"}"
            return (.forbidden, json.data(using: .utf8)!)
        }
    }

    // MARK: - Response Writer

    private func sendResponse(
        context: ChannelHandlerContext,
        status: HTTPResponseStatus,
        body: Data
    ) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Content-Length", value: "\(body.count)")

        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        var buffer = context.channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)

        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
}
