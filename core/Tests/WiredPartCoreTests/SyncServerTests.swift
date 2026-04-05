import Testing
import Foundation
@testable import WiredPartCore

@Suite("LAN Sync Server Tests")
struct SyncServerTests {

    private func makeState(
        deviceId: String = "test-device",
        deviceName: String = "Test Device",
        companyId: String = "test-company"
    ) -> SyncServerState {
        SyncServerState(
            deviceId: deviceId,
            deviceName: deviceName,
            companyId: companyId
        )
    }

    // MARK: - Server Lifecycle

    @Test("Server starts and reports assigned port")
    func testServerStartsAndReportsPort() async throws {
        let state = makeState()
        let server = LanSyncServer(state: state)
        let port = try await server.start()

        #expect(port > 0)
        let statePort = await state.port
        #expect(statePort == port)

        await server.stop()
    }

    @Test("Server stop shuts down cleanly")
    func testServerStopsCleanly() async throws {
        let state = makeState()
        let server = LanSyncServer(state: state)
        _ = try await server.start()
        await server.stop()
        // No crash = success
    }

    // MARK: - GET /sync/status

    @Test("GET /sync/status returns valid JSON")
    func testStatusEndpoint() async throws {
        let state = makeState(deviceId: "dev-1", deviceName: "Shop Mac", companyId: "co-1")
        let server = LanSyncServer(state: state)
        let port = try await server.start()

        let url = URL(string: "http://127.0.0.1:\(port)/sync/status")!
        let (data, response) = try await URLSession.shared.data(from: url)

        let httpResponse = response as! HTTPURLResponse
        #expect(httpResponse.statusCode == 200)

        let status = try JSONDecoder().decode(SyncStatusResponse.self, from: data)
        #expect(status.deviceId == "dev-1")
        #expect(status.deviceName == "Shop Mac")
        #expect(status.companyId == "co-1")
        #expect(status.port == port)

        await server.stop()
    }

    // MARK: - POST /sync/push

    @Test("POST /sync/push accepts changes")
    func testPushAcceptsChanges() async throws {
        let state = makeState(companyId: "co-1")
        let server = LanSyncServer(state: state)
        let port = try await server.start()

        let pushRequest = SyncPushRequest(
            deviceId: "remote-dev",
            companyId: "co-1",
            changes: [
                IncomingChange(
                    deviceId: "remote-dev",
                    tableName: "users",
                    recordId: "1",
                    operation: "INSERT",
                    recordData: "{\"id\":\"1\",\"display_name\":\"Alice\"}",
                    timestamp: "2026-03-14T10:00:00Z"
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(pushRequest)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sync/push")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse
        #expect(httpResponse.statusCode == 200)

        let pushResponse = try JSONDecoder().decode(SyncPushResponse.self, from: data)
        #expect(pushResponse.accepted == 1)
        #expect(!pushResponse.syncBatchId.isEmpty)

        await server.stop()
    }

    @Test("POST /sync/push adds to inbox")
    func testPushAddsToInbox() async throws {
        let state = makeState(companyId: "co-1")
        let server = LanSyncServer(state: state)
        let port = try await server.start()

        let pushRequest = SyncPushRequest(
            deviceId: "remote-dev",
            companyId: "co-1",
            changes: [
                IncomingChange(
                    deviceId: "remote-dev",
                    tableName: "users",
                    recordId: "1",
                    operation: "INSERT",
                    timestamp: "2026-03-14T10:00:00Z"
                ),
                IncomingChange(
                    deviceId: "remote-dev",
                    tableName: "users",
                    recordId: "2",
                    operation: "INSERT",
                    timestamp: "2026-03-14T10:01:00Z"
                )
            ]
        )

        let encoder = JSONEncoder()
        let body = try encoder.encode(pushRequest)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sync/push")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, _) = try await URLSession.shared.data(for: request)

        // Verify inbox
        let inbox = await state.drainInbox()
        #expect(inbox.count == 2)
        #expect(inbox[0].recordId == "1")
        #expect(inbox[1].recordId == "2")

        await server.stop()
    }

    // MARK: - POST /sync/pull

    @Test("POST /sync/pull returns outbox")
    func testPullReturnsOutbox() async throws {
        let state = makeState(deviceId: "server-dev", companyId: "co-1")
        let server = LanSyncServer(state: state)
        let port = try await server.start()

        // Pre-populate outbox
        await state.setOutbox([
            IncomingChange(
                id: 1,
                deviceId: "server-dev",
                tableName: "users",
                recordId: "1",
                operation: "INSERT",
                timestamp: "2026-03-14T10:00:00Z"
            ),
            IncomingChange(
                id: 2,
                deviceId: "server-dev",
                tableName: "users",
                recordId: "2",
                operation: "UPDATE",
                timestamp: "2026-03-14T11:00:00Z"
            )
        ])

        let pullRequest = SyncPullRequest(
            deviceId: "remote-dev",
            companyId: "co-1"
        )

        let encoder = JSONEncoder()
        let body = try encoder.encode(pullRequest)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sync/pull")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse
        #expect(httpResponse.statusCode == 200)

        let pullResponse = try JSONDecoder().decode(SyncPullResponse.self, from: data)
        #expect(pullResponse.changes.count == 2)
        #expect(pullResponse.serverDeviceId == "server-dev")

        await server.stop()
    }

    @Test("POST /sync/pull with vector clock filters changes")
    func testPullWithVectorClock() async throws {
        let state = makeState(deviceId: "server-dev", companyId: "co-1")
        let server = LanSyncServer(state: state)
        let port = try await server.start()

        // Pre-populate outbox with 3 changes (IDs 1, 2, 3)
        await state.setOutbox([
            IncomingChange(id: 1, deviceId: "server-dev", tableName: "users", recordId: "1", operation: "INSERT", timestamp: "2026-03-14T10:00:00Z"),
            IncomingChange(id: 2, deviceId: "server-dev", tableName: "users", recordId: "2", operation: "INSERT", timestamp: "2026-03-14T10:01:00Z"),
            IncomingChange(id: 3, deviceId: "server-dev", tableName: "users", recordId: "3", operation: "INSERT", timestamp: "2026-03-14T10:02:00Z"),
        ])

        // Peer has seen up to ID 1 from this server
        let pullRequest = SyncPullRequest(
            deviceId: "remote-dev",
            companyId: "co-1",
            vectorClock: ["server-dev": 1]
        )

        let encoder = JSONEncoder()
        let body = try encoder.encode(pullRequest)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sync/pull")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await URLSession.shared.data(for: request)
        let pullResponse = try JSONDecoder().decode(SyncPullResponse.self, from: data)

        // Should only get IDs 2 and 3 (not 1)
        #expect(pullResponse.changes.count == 2)

        await server.stop()
    }

    // MARK: - Auth

    @Test("Wrong company_id returns 403")
    func testWrongCompanyIdReturns403() async throws {
        let state = makeState(companyId: "co-1")
        let server = LanSyncServer(state: state)
        let port = try await server.start()

        let pushRequest = SyncPushRequest(
            deviceId: "remote-dev",
            companyId: "wrong-company",
            changes: []
        )

        let encoder = JSONEncoder()
        let body = try encoder.encode(pushRequest)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sync/push")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse
        #expect(httpResponse.statusCode == 403)

        await server.stop()
    }
}
