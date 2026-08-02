import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("Agent Link service")
struct AgentLinkServiceTests {

    private func makeService() throws -> (db: AppDatabase, service: AgentLinkService) {
        let db = try AppDatabase.openInMemoryDatabase()
        return (db, AgentLinkService(db: db))
    }

    @Test("Minted token verifies and is never stored raw")
    func tokenMintAndHashAtRest() throws {
        let (db, service) = try makeService()
        let (link, token) = try service.createLink(name: "Claude Desktop", scope: .read)
        #expect(token.hasPrefix("wpal_"))
        #expect(try service.verify(token: token)?.id == link.id)
        // Assert at the SQL layer: the stored value is the SHA-256 hex, and the
        // raw token appears in NO column of the row.
        let row = try #require(try db.writer.read { dbc in
            try Row.fetchOne(dbc, sql: "SELECT * FROM agent_links WHERE id = ?", arguments: [link.id])
        })
        #expect(row["token_hash"] as String? == AgentLinkService.tokenHash(token))
        for (_, value) in row {
            #expect((value.storage.value as? String) != token)
        }
    }

    @Test("Unknown token does not verify")
    func unknownToken() throws {
        let (_, service) = try makeService()
        _ = try service.createLink(name: "A", scope: .read)
        #expect(try service.verify(token: "wpal_not_a_real_token") == nil)
        #expect(try service.lookup(token: "wpal_not_a_real_token") == nil)
    }

    @Test("Revocation is immediate and lookup still resolves the link for audit")
    func revocation() throws {
        let (_, service) = try makeService()
        let (link, token) = try service.createLink(name: "hermes", scope: .readNotes)
        try service.revoke(linkId: link.id)
        #expect(try service.verify(token: token) == nil)
        let found = try #require(try service.lookup(token: token))
        #expect(found.link.id == link.id)
        #expect(found.active == false)
        // Double revoke is a no-op, unknown id throws.
        try service.revoke(linkId: link.id)
        #expect(throws: AgentLinkService.AgentLinkError.linkNotFound) {
            try service.revoke(linkId: 9999)
        }
    }

    @Test("recordCall bumps counters and audit trail reads newest-first")
    func auditTrail() throws {
        let (_, service) = try makeService()
        let (link, _) = try service.createLink(name: "Claude", scope: .read)
        try service.recordCall(linkId: link.id, tool: "system_health", argumentDigest: nil, status: "ok")
        try service.recordCall(linkId: link.id, tool: "parts_search", argumentDigest: "abcd", status: "error")
        let refreshed = try #require(try service.listLinks().first { $0.id == link.id })
        #expect(refreshed.callCount == 2)
        #expect(refreshed.lastSeenAt != nil)
        let trail = try service.auditTrail(linkId: link.id)
        #expect(trail.map(\.tool) == ["parts_search", "system_health"])
        #expect(trail.first?.status == "error")
    }

    @Test("Scopes gate the write tool only")
    func scopes() {
        #expect(AgentLinkService.Scope.read.allows(tool: "parts_search"))
        #expect(!AgentLinkService.Scope.read.allows(tool: "job_note_append"))
        #expect(AgentLinkService.Scope.readNotes.allows(tool: "job_note_append"))
        #expect(AgentLinkService.Scope.readNotes.allows(tool: "stock_levels"))
    }
}

// Serialized for the same reason SyncServerTests is (#1583): parallel tests
// each binding loopback listeners can collide on just-recycled ephemeral
// ports and answer each other's requests. A recurrence under serialization
// is a real server race, not a rerun candidate.
@Suite("Agent Link MCP server", .serialized)
struct AgentLinkServerTests {

    private struct Harness {
        let service: AgentLinkService
        let server: AgentLinkServer
        let port: UInt16
        let token: String
        let linkId: Int64
    }

    private func startServer(scope: AgentLinkService.Scope = .read) async throws -> Harness {
        let env = try E2ETestHelpers.setUp()
        let service = AgentLinkService(db: env.db)
        let (link, token) = try service.createLink(
            name: "test-agent", scope: scope, createdBy: env.adminUserId
        )
        let server = AgentLinkServer(
            service: service,
            registry: AgentLinkTools.v1(
                db: env.db, parts: env.parts, jobs: env.jobs, orders: env.orders,
                notebooks: env.notebooks, reports: env.reports, appVersion: "test"
            ),
            port: 0,
            appVersion: "test"
        )
        let port = try await server.start()
        return Harness(service: service, server: server, port: port, token: token, linkId: link.id)
    }

    private func post(
        _ harness: Harness,
        path: String = "/mcp",
        method: String = "POST",
        token: String?,
        body: [String: Any]?
    ) async throws -> (status: Int, json: [String: Any]?) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(harness.port)\(path)")!)
        request.httpMethod = method
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return (status, json)
    }

    private func rpc(_ method: String, params: [String: Any]? = nil, id: Int = 1) -> [String: Any] {
        var body: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params { body["params"] = params }
        return body
    }

    @Test("Server binds loopback and answers initialize")
    func initializeHandshake() async throws {
        let harness = try await startServer()
        defer { Task { await harness.server.stop() } }
        #expect(harness.port > 0)
        let (status, json) = try await post(harness, token: harness.token, body: rpc("initialize"))
        #expect(status == 200)
        let result = try #require(json?["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-06-18")
        let info = try #require(result["serverInfo"] as? [String: Any])
        #expect(info["name"] as? String == "WiredPart Agent Link")
        await harness.server.stop()
    }

    @Test("Missing and unknown tokens get 401")
    func authRequired() async throws {
        let harness = try await startServer()
        let noToken = try await post(harness, token: nil, body: rpc("initialize"))
        #expect(noToken.status == 401)
        let badToken = try await post(harness, token: "wpal_bogus", body: rpc("initialize"))
        #expect(badToken.status == 401)
        await harness.server.stop()
    }

    @Test("Revoked token gets 401 and the attempt is audited")
    func revokedTokenAudited() async throws {
        let harness = try await startServer()
        try harness.service.revoke(linkId: harness.linkId)
        let (status, _) = try await post(harness, token: harness.token, body: rpc("tools/list"))
        #expect(status == 401)
        let trail = try harness.service.auditTrail(linkId: harness.linkId)
        #expect(trail.contains { $0.status == "unauthorized" })
        await harness.server.stop()
    }

    @Test("tools/list shows system_health and tools/call runs it with audit")
    func systemHealthTool() async throws {
        let harness = try await startServer()
        let (listStatus, listJSON) = try await post(harness, token: harness.token, body: rpc("tools/list"))
        #expect(listStatus == 200)
        let tools = try #require(
            (listJSON?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        )
        #expect(tools.contains { $0["name"] as? String == "system_health" })

        let (callStatus, callJSON) = try await post(
            harness, token: harness.token,
            body: rpc("tools/call", params: ["name": "system_health"])
        )
        #expect(callStatus == 200)
        let result = try #require(callJSON?["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == false)
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        let payload = try #require(
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        #expect((payload["migrationsApplied"] as? Int ?? 0) > 0)
        #expect(payload["appVersion"] as? String == "test")

        let trail = try harness.service.auditTrail(linkId: harness.linkId)
        #expect(trail.contains { $0.tool == "system_health" && $0.status == "ok" })
        await harness.server.stop()
    }

    @Test("Unknown tool and unknown method return JSON-RPC errors")
    func rpcErrors() async throws {
        let harness = try await startServer()
        let unknownTool = try await post(
            harness, token: harness.token,
            body: rpc("tools/call", params: ["name": "no_such_tool"])
        )
        #expect(unknownTool.status == 200)
        let toolError = try #require(unknownTool.json?["error"] as? [String: Any])
        #expect(toolError["code"] as? Int == -32602)

        let unknownMethod = try await post(harness, token: harness.token, body: rpc("bogus/method"))
        let methodError = try #require(unknownMethod.json?["error"] as? [String: Any])
        #expect(methodError["code"] as? Int == -32601)
        await harness.server.stop()
    }

    @Test("Notifications get 202, wrong path 404, GET 405")
    func httpEdges() async throws {
        let harness = try await startServer()
        let notification = try await post(
            harness, token: harness.token,
            body: ["jsonrpc": "2.0", "method": "notifications/initialized"]
        )
        #expect(notification.status == 202)
        let wrongPath = try await post(harness, path: "/sync/status", token: harness.token, body: rpc("ping"))
        #expect(wrongPath.status == 404)
        let get = try await post(harness, method: "GET", token: harness.token, body: nil)
        #expect(get.status == 405)
        await harness.server.stop()
    }

    @Test("Read scope cannot see or call the future write tool")
    func scopeFilteringOnList() async throws {
        let harness = try await startServer(scope: .read)
        let (_, listJSON) = try await post(harness, token: harness.token, body: rpc("tools/list"))
        let tools = try #require(
            (listJSON?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        )
        let names = tools.compactMap { $0["name"] as? String }
        #expect(names.count == 7)
        #expect(!names.contains("job_note_append"))
        // Calling the hidden write tool anyway is refused.
        let denied = try await post(
            harness, token: harness.token,
            body: rpc("tools/call", params: ["name": "job_note_append", "arguments": ["job_id": 1, "note": "x"]])
        )
        let error = try #require(denied.json?["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32602)
        await harness.server.stop()
    }
}

@Suite("Agent Link tools")
struct AgentLinkToolsTests {

    private func makeRegistry() throws -> (env: E2ETestHelpers.TestEnvironment, registry: AgentLinkToolRegistry, link: AgentLinkService.AgentLink) {
        let env = try E2ETestHelpers.setUp()
        let service = AgentLinkService(db: env.db)
        let (link, _) = try service.createLink(
            name: "tools-test", scope: .readNotes, createdBy: env.adminUserId
        )
        let registry = AgentLinkTools.v1(
            db: env.db, parts: env.parts, jobs: env.jobs, orders: env.orders,
            notebooks: env.notebooks, reports: env.reports, appVersion: "test"
        )
        return (env, registry, link)
    }

    private func call(
        _ registry: AgentLinkToolRegistry, _ name: String,
        link: AgentLinkService.AgentLink, _ arguments: [String: Any]? = nil
    ) async throws -> [String: Any] {
        let tool = try #require(registry.tools.first { $0.name == name })
        let data = try arguments.map { try JSONSerialization.data(withJSONObject: $0) }
        let out = try await tool.handler(link, data)
        let json = try JSONSerialization.jsonObject(with: Data(out.utf8))
        if let dict = json as? [String: Any] { return dict }
        return ["rows": json]
    }

    @Test("v1 registry lists the plan's eight tools")
    func registryRoster() throws {
        let (_, registry, _) = try makeRegistry()
        #expect(Set(registry.tools.map(\.name)) == [
            "parts_search", "stock_levels", "jobs_list", "job_detail",
            "orders_status", "reports_summary", "system_health", "job_note_append",
        ])
    }

    @Test("parts_search finds a seeded part and requires a query")
    func partsSearch() async throws {
        let (env, registry, link) = try makeRegistry()
        let (catId, _, _) = try E2ETestHelpers.seedPartHierarchy(env)
        _ = try E2ETestHelpers.seedPart(env, name: "THHN 12 Red", categoryId: catId)
        let result = try await call(registry, "parts_search", link: link, ["query": "THHN"])
        let rows = try #require(result["rows"] as? [[String: Any]])
        #expect(rows.contains { ($0["name"] as? String) == "THHN 12 Red" })
        await #expect(throws: (any Error).self) {
            _ = try await self.call(registry, "parts_search", link: link, [:])
        }
    }

    @Test("jobs_list and job_detail round-trip a seeded job")
    func jobsTools() async throws {
        let (env, registry, link) = try makeRegistry()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-777", name: "Panel Swap")
        let list = try await call(registry, "jobs_list", link: link, ["search": "Panel Swap"])
        let rows = try #require(list["rows"] as? [[String: Any]])
        #expect(rows.contains { ($0["jobNumber"] as? String) == "J-777" })
        let detail = try await call(registry, "job_detail", link: link, ["job_id": jobId])
        #expect(detail["jobNumber"] as? String == "J-777")
        #expect(detail["jobName"] as? String == "Panel Swap")
    }

    @Test("orders_status and reports_summary return well-formed empty-state payloads")
    func ordersAndReports() async throws {
        let (_, registry, link) = try makeRegistry()
        let orders = try await call(registry, "orders_status", link: link)
        #expect((orders["rows"] as? [[String: Any]])?.isEmpty == true)
        let summary = try await call(registry, "reports_summary", link: link, ["days": 7])
        #expect(summary["days"] as? Int == 7)
        #expect(summary["poCount"] as? Int == 0)
        #expect((summary["jobsTotal"] as? Int) != nil)
    }

    @Test("job_note_append creates the notebook, attributes the entry, and needs an acting user")
    func jobNoteAppend() async throws {
        let (env, registry, link) = try makeRegistry()
        let jobId = try E2ETestHelpers.seedJob(env)
        let result = try await call(
            registry, "job_note_append", link: link,
            ["job_id": jobId, "note": "Breaker order confirmed", "title": "Order note"]
        )
        #expect(result["status"] as? String == "appended")
        let notebookId = try #require((result["notebookId"] as? NSNumber)?.int64Value)
        let detail = try env.notebooks.getNotebookDetail(id: notebookId)
        #expect(detail.jobId == jobId)
        // Second append reuses the same notebook.
        let again = try await call(
            registry, "job_note_append", link: link, ["job_id": jobId, "note": "Second"]
        )
        #expect((again["notebookId"] as? NSNumber)?.int64Value == notebookId)
        // A link with no acting user is refused with a clear message.
        let service = AgentLinkService(db: env.db)
        let (orphan, _) = try service.createLink(name: "orphan", scope: .readNotes)
        await #expect(throws: (any Error).self) {
            _ = try await self.call(
                registry, "job_note_append", link: orphan, ["job_id": jobId, "note": "x"]
            )
        }
    }
}
