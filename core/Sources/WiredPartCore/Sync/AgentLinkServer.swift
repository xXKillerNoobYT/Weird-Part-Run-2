import Foundation
import Network
import CryptoKit
import GRDB
import os

/// Agent Link (MCP) server — the app as a Model Context Protocol server for
/// AI desktop apps (Claude Desktop / ChatGPT desktop) on the SAME Mac.
///
/// Plan: `docs/plans/devices-add-mcp-agent-link.md`, owner decisions
/// 2026-08-01: Macs only, so this listener binds STRICTLY to 127.0.0.1 —
/// other LAN hosts must never be able to connect, regardless of firewall
/// state. Port 8471 by default (0 = OS-assigned, used by tests). Speaks MCP
/// Streamable HTTP (JSON-RPC 2.0 over POST /mcp): `initialize`, `ping`,
/// `tools/list`, `tools/call`; notifications get 202. Every request needs a
/// per-agent bearer token from `AgentLinkService`; unknown tokens are 401,
/// revoked tokens are 401 AND audited against their link.
///
/// HTTP plumbing (request accumulation, Content-Length parsing, response
/// framing) is shared with `LanSyncServer` — extend, don't duplicate.
public final class AgentLinkServer: Sendable {
    public static let defaultPort: UInt16 = 8471
    /// Version reported by `initialize`; the latest revision this server implements.
    static let mcpProtocolVersion = "2025-06-18"

    private let service: AgentLinkService
    private let registry: AgentLinkToolRegistry
    private let requestedPort: UInt16
    private let appVersion: String
    private let listenerLock = OSAllocatedUnfairLock<NWListener?>(initialState: nil)
    private let logger = Logger(subsystem: "com.wiredpart.core", category: "AgentLinkServer")

    public init(
        service: AgentLinkService,
        registry: AgentLinkToolRegistry,
        port: UInt16 = AgentLinkServer.defaultPort,
        appVersion: String = "dev"
    ) {
        self.service = service
        self.registry = registry
        self.requestedPort = port
        self.appVersion = appVersion
    }

    // MARK: - Lifecycle

    /// Start listening on loopback. Returns the bound port.
    public func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // The loopback pin. `requiredLocalEndpoint` makes the kernel bind
        // 127.0.0.1 specifically — not INADDR_ANY — so non-loopback interfaces
        // never carry this listener at all (acceptance criterion 4).
        guard let port = NWEndpoint.Port(rawValue: requestedPort) else {
            throw SyncServerError.failedToBind
        }
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: port)

        let listener = try NWListener(using: params)
        listenerLock.withLock { $0 = listener }

        let serviceRef = service
        let registryRef = registry
        let loggerRef = logger
        let versionRef = appVersion

        return try await withCheckedThrowingContinuation { continuation in
            // Same atomic resume guard as LanSyncServer (#190): .ready/.failed
            // can race on different queues; only one caller may resume.
            let resumedLock = OSAllocatedUnfairLock<Bool>(initialState: false)
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
                    if let bound = listener.port?.rawValue {
                        continuation.resume(returning: bound)
                    } else {
                        continuation.resume(throwing: SyncServerError.failedToBind)
                    }
                case .failed(let error):
                    guard claimResume() else { return }
                    loggerRef.error("AgentLink listener failed: \(error.localizedDescription)")
                    continuation.resume(throwing: SyncServerError.failedToBind)
                default:
                    break
                }
            }

            listener.newConnectionHandler = { connection in
                connection.start(queue: .global(qos: .userInitiated))
                LanSyncServer.readFullHTTPRequest(connection: connection, accumulated: Data()) { data in
                    guard let data else {
                        connection.cancel()
                        return
                    }
                    Task {
                        let (status, body) = await Self.route(
                            data: data,
                            service: serviceRef,
                            registry: registryRef,
                            appVersion: versionRef,
                            logger: loggerRef
                        )
                        let response = LanSyncServer.buildHTTPResponse(status: status, body: body)
                        connection.send(
                            content: response,
                            contentContext: .finalMessage,
                            isComplete: true,
                            completion: .contentProcessed { _ in connection.cancel() }
                        )
                    }
                }
            }

            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    public func stop() async {
        let listener = listenerLock.withLock { l -> NWListener? in
            let current = l
            l = nil
            return current
        }
        listener?.cancel()
    }

    // MARK: - HTTP routing

    static func route(
        data: Data,
        service: AgentLinkService,
        registry: AgentLinkToolRegistry,
        appVersion: String,
        logger: Logger
    ) async -> (Int, Data) {
        guard let request = ParsedHTTPRequest(data: data) else {
            return (400, jsonError("malformed HTTP request"))
        }
        guard request.path == "/mcp" else {
            return (404, jsonError("not found"))
        }
        guard request.method == "POST" else {
            // No SSE stream in v1; the spec allows plain 405 for GET.
            return (405, jsonError("method not allowed"))
        }

        // Bearer auth on every request, initialize included.
        guard let auth = request.headers["authorization"],
              auth.lowercased().hasPrefix("bearer "),
              case let token = String(auth.dropFirst("bearer ".count))
                  .trimmingCharacters(in: .whitespaces),
              !token.isEmpty else {
            return (401, jsonError("missing bearer token"))
        }
        let lookup = (try? service.lookup(token: token)) ?? nil
        guard let lookup else {
            return (401, jsonError("unknown token"))
        }
        guard lookup.active else {
            // Revoked tokens are auditable — the link is known.
            try? service.recordCall(
                linkId: lookup.link.id, tool: "-", argumentDigest: nil, status: "unauthorized"
            )
            return (401, jsonError("token revoked"))
        }

        guard let json = try? JSONSerialization.jsonObject(with: request.body) else {
            return (400, jsonError("body is not JSON"))
        }
        guard let rpc = json as? [String: Any] else {
            // JSON-RPC batching was removed in protocol 2025-06-18.
            return (400, jsonError("expected a single JSON-RPC object"))
        }

        return await handleRPC(
            rpc, link: lookup.link, service: service, registry: registry, appVersion: appVersion
        )
    }

    // MARK: - JSON-RPC

    private static func handleRPC(
        _ rpc: [String: Any],
        link: AgentLinkService.AgentLink,
        service: AgentLinkService,
        registry: AgentLinkToolRegistry,
        appVersion: String
    ) async -> (Int, Data) {
        let method = rpc["method"] as? String ?? ""
        let id = rpc["id"]

        // Notifications (no id) are acknowledged and produce no body.
        guard let id else {
            return (202, Data())
        }

        switch method {
        case "initialize":
            return (200, rpcResult(id: id, [
                "protocolVersion": mcpProtocolVersion,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "WiredPart Agent Link", "version": appVersion],
            ]))

        case "ping":
            return (200, rpcResult(id: id, [String: Any]()))

        case "tools/list":
            // Only tools this link's scope can actually call — an agent that
            // can't see a tool won't waste turns trying it.
            let visible = registry.tools.filter { link.scope.allows(tool: $0.name) }
            return (200, rpcResult(id: id, [
                "tools": visible.map { tool -> [String: Any] in
                    [
                        "name": tool.name,
                        "description": tool.description,
                        "inputSchema": (try? JSONSerialization.jsonObject(
                            with: Data(tool.inputSchemaJSON.utf8)
                        )) ?? ["type": "object"],
                    ]
                },
            ]))

        case "tools/call":
            let params = rpc["params"] as? [String: Any]
            guard let name = params?["name"] as? String else {
                return (200, rpcError(id: id, code: -32602, message: "missing tool name"))
            }
            guard let tool = registry.tools.first(where: { $0.name == name }),
                  link.scope.allows(tool: name) else {
                return (200, rpcError(
                    id: id, code: -32602,
                    message: "tool not available for this link"
                ))
            }
            let argsData = (params?["arguments"]).flatMap {
                try? JSONSerialization.data(withJSONObject: $0)
            }
            // Audit stores a digest, never the arguments themselves.
            let digest = argsData.map {
                SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined().prefix(16)
            }.map(String.init)
            do {
                let output = try await tool.handler(link, argsData)
                try? service.recordCall(
                    linkId: link.id, tool: name, argumentDigest: digest, status: "ok"
                )
                return (200, rpcResult(id: id, [
                    "content": [["type": "text", "text": output]],
                    "isError": false,
                ]))
            } catch {
                try? service.recordCall(
                    linkId: link.id, tool: name, argumentDigest: digest, status: "error"
                )
                // Tool-level failures ride in the result per MCP, so the model
                // can read them and adjust; JSON-RPC errors are protocol-only.
                return (200, rpcResult(id: id, [
                    "content": [["type": "text", "text": "error: \(error)"]],
                    "isError": true,
                ]))
            }

        default:
            return (200, rpcError(id: id, code: -32601, message: "method not found"))
        }
    }

    // MARK: - Payload helpers

    private static func rpcResult(id: Any, _ result: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": id, "result": result,
        ])) ?? Data()
    }

    private static func rpcError(id: Any, code: Int, message: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message],
        ])) ?? Data()
    }

    private static func jsonError(_ message: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["error": message])) ?? Data()
    }

    // MARK: - Minimal HTTP request model

    struct ParsedHTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data

        init?(data: Data) {
            let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
            guard let separatorRange = data.range(of: separator),
                  let head = String(
                    data: data[data.startIndex..<separatorRange.lowerBound], encoding: .utf8
                  ) else { return nil }
            let lines = head.components(separatedBy: "\r\n")
            let requestParts = lines.first?.components(separatedBy: " ") ?? []
            guard requestParts.count >= 2 else { return nil }
            method = requestParts[0].uppercased()
            // Strip any query string; MCP routing is path-only.
            path = requestParts[1].components(separatedBy: "?")[0]
            var parsed: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                parsed[key] = value
            }
            headers = parsed
            body = Data(data[separatorRange.upperBound...])
        }
    }
}

// MARK: - Tool registry

/// One MCP tool: metadata for `tools/list` plus the handler `tools/call`
/// dispatches to. Handlers take the raw JSON `arguments` object (nil when the
/// client sent none) and return the JSON/text payload for the reply.
public struct AgentLinkTool: Sendable {
    public let name: String
    public let description: String
    /// JSON Schema for the arguments, as a JSON string.
    public let inputSchemaJSON: String
    public let handler: @Sendable (AgentLinkService.AgentLink, Data?) async throws -> String

    public init(
        name: String,
        description: String,
        inputSchemaJSON: String,
        handler: @escaping @Sendable (AgentLinkService.AgentLink, Data?) async throws -> String
    ) {
        self.name = name
        self.description = description
        self.inputSchemaJSON = inputSchemaJSON
        self.handler = handler
    }
}

public struct AgentLinkToolRegistry: Sendable {
    public let tools: [AgentLinkTool]

    public init(tools: [AgentLinkTool]) {
        self.tools = tools
    }
}
