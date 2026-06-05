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

    private func sendEncrypted<T: Encodable>(
        _ payload: T,
        path: String,
        port: UInt16,
        companyId: String
    ) async throws -> (Data, HTTPURLResponse) {
        var keyRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sync/key")!)
        keyRequest.setValue(companyId, forHTTPHeaderField: "X-Company-ID")
        let (keyData, keyResponse) = try await URLSession.shared.data(for: keyRequest)
        #expect((keyResponse as! HTTPURLResponse).statusCode == 200)

        let serverKey = try JSONDecoder().decode(SyncKeyResponse.self, from: keyData).key
        let (clientPrivateKey, clientPublicKey) = SyncCrypto.generateKeyAgreementPair()
        let sharedKey = try SyncCrypto.deriveSharedKeyData(
            ourPrivateKeyB64: clientPrivateKey,
            theirPublicKeyB64: serverKey
        )

        let body = try JSONEncoder().encode(payload)
        let encryptedBody = try SyncCrypto.encryptAESGCM(data: body, keyData: sharedKey)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = "POST"
        request.httpBody = encryptedBody
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-Sync-Encrypted")
        request.setValue(clientPublicKey, forHTTPHeaderField: "X-Sync-Sender-Key")

        let (responseData, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse
        if httpResponse.statusCode == 200 {
            return (try SyncCrypto.decryptAESGCM(data: responseData, keyData: sharedKey), httpResponse)
        }
        return (responseData, httpResponse)
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
        // Fix #176: sensitive fields are redacted from the unauthenticated /sync/status endpoint.
        #expect(status.deviceId == "")
        #expect(status.deviceName == "")
        #expect(status.companyId == "")
        #expect(status.port == port)

        await server.stop()
    }

    // MARK: - POST /sync/push

    @Test("POST /sync/push accepts encrypted changes")
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

        let (data, httpResponse) = try await sendEncrypted(
            pushRequest,
            path: "/sync/push",
            port: port,
            companyId: "co-1"
        )
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

        let (_, response) = try await sendEncrypted(
            pushRequest,
            path: "/sync/push",
            port: port,
            companyId: "co-1"
        )
        #expect(response.statusCode == 200)

        // Verify inbox
        let inbox = await state.drainInbox()
        #expect(inbox.count == 2)
        #expect(inbox[0].recordId == "1")
        #expect(inbox[1].recordId == "2")

        await server.stop()
    }

    @Test("POST /sync/push rejects plaintext")
    func testPushRejectsPlaintext() async throws {
        let state = makeState(companyId: "co-1")
        let server = LanSyncServer(state: state)
        let port = try await server.start()

        let pushRequest = SyncPushRequest(
            deviceId: "remote-dev",
            companyId: "co-1",
            changes: []
        )
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sync/push")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(pushRequest)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        #expect((response as! HTTPURLResponse).statusCode == 400)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["error"] as? String == "decryption_failed")

        await server.stop()
    }

    // MARK: - POST /sync/pull

    @Test("POST /sync/pull returns encrypted outbox")
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

        let (data, httpResponse) = try await sendEncrypted(
            pullRequest,
            path: "/sync/pull",
            port: port,
            companyId: "co-1"
        )
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

        let (data, response) = try await sendEncrypted(
            pullRequest,
            path: "/sync/pull",
            port: port,
            companyId: "co-1"
        )
        #expect(response.statusCode == 200)
        let pullResponse = try JSONDecoder().decode(SyncPullResponse.self, from: data)

        // Should only get IDs 2 and 3 (not 1)
        #expect(pullResponse.changes.count == 2)

        await server.stop()
    }

    @Test("POST /sync/pull rejects plaintext")
    func testPullRejectsPlaintext() async throws {
        let state = makeState(companyId: "co-1")
        let server = LanSyncServer(state: state)
        let port = try await server.start()

        let pullRequest = SyncPullRequest(
            deviceId: "remote-dev",
            companyId: "co-1"
        )
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sync/pull")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(pullRequest)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        #expect((response as! HTTPURLResponse).statusCode == 400)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["error"] as? String == "decryption_failed")

        await server.stop()
    }

    // MARK: - Auth

    // MARK: - GET /sync/key (#191 — unauthenticated key exchange)

    @Test("GET /sync/key without X-Company-ID returns 403")
    func testKeyExchangeWithoutCompanyIdReturns403() async throws {
        let state = makeState(companyId: "co-1")
        let server = LanSyncServer(state: state)
        let port = try await server.start()
        defer { Task { await server.stop() } }

        let url = URL(string: "http://127.0.0.1:\(port)/sync/key")!
        let (_, response) = try await URLSession.shared.data(from: url)
        #expect((response as! HTTPURLResponse).statusCode == 403)
    }

    @Test("GET /sync/key with wrong X-Company-ID returns 403")
    func testKeyExchangeWithWrongCompanyIdReturns403() async throws {
        let state = makeState(companyId: "co-1")
        let server = LanSyncServer(state: state)
        let port = try await server.start()
        defer { Task { await server.stop() } }

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sync/key")!)
        req.setValue("different-company", forHTTPHeaderField: "X-Company-ID")
        let (_, response) = try await URLSession.shared.data(for: req)
        #expect((response as! HTTPURLResponse).statusCode == 403)
    }

    @Test("GET /sync/key with correct X-Company-ID returns server public key")
    func testKeyExchangeWithCorrectCompanyIdReturns200() async throws {
        let state = makeState(companyId: "co-1")
        let server = LanSyncServer(state: state)
        let port = try await server.start()
        defer { Task { await server.stop() } }

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sync/key")!)
        req.setValue("co-1", forHTTPHeaderField: "X-Company-ID")
        let (data, response) = try await URLSession.shared.data(for: req)
        #expect((response as! HTTPURLResponse).statusCode == 200)

        let keyResponse = try JSONDecoder().decode(SyncKeyResponse.self, from: data)
        #expect(!keyResponse.key.isEmpty)
        // Server's public key should be valid base64
        #expect(Data(base64Encoded: keyResponse.key) != nil)
    }

    // MARK: - Cert Rejection JSON Safety (#184 — JSON injection)

    @Test("Rejected cert produces valid JSON response body")
    func testRejectedCertProducesValidJSON() async throws {
        // Trigger a .rejected response by supplying a server with a company key
        // but sending a tampered certificate (bad signature).
        let (_, publicKey) = SyncCrypto.generateKeyPair()

        let state = SyncServerState(
            deviceId: "server-dev",
            deviceName: "Secure Server",
            companyId: "co-1",
            companyPublicKey: publicKey
        )
        let server = LanSyncServer(state: state)
        let port = try await server.start()
        defer { Task { await server.stop() } }

        // Send a cert with invalid base64 signature — verifySyncAuth will return .rejected
        let body: [String: Any] = [
            "device_id": "client-dev",
            "company_id": "co-1",
            "changes": [] as [[String: Any]],
            "auth": [
                "certificate_data": "eyJkZXZpY2VfaWQiOiJ0ZXN0In0=",  // valid b64, wrong content
                "certificate_signature": "bm90LWEtcmVhbC1zaWduYXR1cmU="   // invalid signature
            ]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let pushRequest = try JSONDecoder().decode(SyncPushRequest.self, from: bodyData)

        let (data, response) = try await sendEncrypted(
            pushRequest,
            path: "/sync/push",
            port: port,
            companyId: "co-1"
        )
        #expect(response.statusCode == 403)

        // Response must be valid JSON — not malformed by interpolated special chars in reason
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        #expect(json?["error"] as? String == "certificate_rejected")
        #expect(json?["reason"] as? String != nil)  // reason is present and is a proper string
    }

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

        let (_, response) = try await sendEncrypted(
            pushRequest,
            path: "/sync/push",
            port: port,
            companyId: "co-1"
        )
        #expect(response.statusCode == 403)

        await server.stop()
    }
}
