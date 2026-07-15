import Testing
import Foundation
import os
@testable import WiredPartCore

@Suite("LAN Sync Server Tests")
struct SyncServerTests {

    private var validPeerKey: String {
        SyncCrypto.generateKeyAgreementPair().publicKey
    }

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

    private func makeEncryptedRequest(
        url: URL,
        plainBody: Data,
        state: SyncServerState,
        deviceId: String = "remote-dev"
    ) async throws -> (request: URLRequest, sharedKey: Data) {
        let (privateKey, publicKey) = SyncCrypto.generateKeyAgreementPair()
        try await state.registerAuthorizedPeer(
            deviceId: deviceId,
            deviceName: "Test peer",
            platform: "test",
            keyAgreementPublicKey: publicKey
        )
        let sharedKey = try SyncCrypto.deriveSharedKeyData(
            ourPrivateKeyB64: privateKey,
            theirPublicKeyB64: state.kaPublicKeyB64
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try SyncCrypto.encryptAESGCM(data: plainBody, keyData: sharedKey)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-Sync-Encrypted")
        request.setValue(publicKey, forHTTPHeaderField: "X-Sync-Sender-Key")
        request.setValue(deviceId, forHTTPHeaderField: "X-Sync-Device-ID")
        return (request, sharedKey)
    }

    private func decryptResponse(_ data: Data, sharedKey: Data) throws -> Data {
        try SyncCrypto.decryptAESGCM(data: data, keyData: sharedKey)
    }

    // MARK: - HTTP Framing

    @Test("Content-Length parser distinguishes missing, valid, and invalid headers")
    func testContentLengthParserStates() throws {
        #expect(LanSyncServer.parseContentLength(from: "GET /sync/status HTTP/1.1\r\nHost: localhost") == .missing)
        #expect(LanSyncServer.parseContentLength(from: "POST /sync/push HTTP/1.1\r\nContent-Length: 42") == .valid(42))
        #expect(LanSyncServer.parseContentLength(from: "POST /sync/push HTTP/1.1\r\ncontent-length: 0") == .valid(0))
        #expect(LanSyncServer.parseContentLength(from: "POST /sync/push HTTP/1.1\r\n Content-Length: 7") == .valid(7))
        #expect(LanSyncServer.parseContentLength(from: "POST /sync/push HTTP/1.1\r\nContent-Length: abc") == .invalid)
        #expect(LanSyncServer.parseContentLength(from: "POST /sync/push HTTP/1.1\r\nContent-Length: -1") == .invalid)
        #expect(LanSyncServer.parseContentLength(from: "POST /sync/push HTTP/1.1\r\nContent-Length: ") == .invalid)
        #expect(LanSyncServer.parseContentLength(from: "POST /sync/push HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2") == .invalid)
    }

    @Test("Malformed Content-Length returns bad request before routing")
    func testMalformedContentLengthReturnsBadRequest() async throws {
        let state = makeState(companyId: "co-1")
        let rawRequest = "POST /sync/push HTTP/1.1\r\n"
            + "Host: 127.0.0.1\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: abc\r\n"
            + "\r\n"
            + "{\"device_id\":\"remote-dev\",\"company_id\":\"co-1\",\"changes\":[]}"

        let (status, body) = await LanSyncServer.routeHTTPRequest(
            data: Data(rawRequest.utf8),
            state: state,
            logger: Logger(subsystem: "com.wiredpart.core.tests", category: "SyncServerTests")
        )

        #expect(status == 400)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: String]
        #expect(json?["error"] == "bad_request")
    }

    @Test("Negative Content-Length returns bad request before routing")
    func testNegativeContentLengthReturnsBadRequest() async throws {
        let state = makeState(companyId: "co-1")
        let rawRequest = "POST /sync/push HTTP/1.1\r\n"
            + "Host: 127.0.0.1\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: -1\r\n"
            + "\r\n"
            + "{\"device_id\":\"remote-dev\",\"company_id\":\"co-1\",\"changes\":[]}"

        let (status, _) = await LanSyncServer.routeHTTPRequest(
            data: Data(rawRequest.utf8),
            state: state,
            logger: Logger(subsystem: "com.wiredpart.core.tests", category: "SyncServerTests")
        )

        #expect(status == 400)
    }

    @Test("Incomplete body returns bad request before routing")
    func testIncompleteContentLengthBodyReturnsBadRequest() async throws {
        let state = makeState(companyId: "co-1")
        let rawRequest = "POST /sync/push HTTP/1.1\r\n"
            + "Host: 127.0.0.1\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: 999\r\n"
            + "\r\n"
            + "{\"device_id\":\"remote-dev\"}"

        let (status, _) = await LanSyncServer.routeHTTPRequest(
            data: Data(rawRequest.utf8),
            state: state,
            logger: Logger(subsystem: "com.wiredpart.core.tests", category: "SyncServerTests")
        )

        #expect(status == 400)
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

    // MARK: - POST /sync/pair

    @Test("POST /sync/pair rejects when no pairing code is active")
    func testPairRejectsWithoutActiveCode() async throws {
        let state = makeState(deviceId: "shop-dev", companyId: "co-1")
        let server = LanSyncServer(state: state)
        let port = try await server.start()

        let body = try JSONEncoder().encode(SyncPairRequest(
            deviceId: "phone-dev",
            deviceName: "Phone",
            pairingCode: "ABCD-1234",
            platform: "iOS",
            keyAgreementPublicKey: validPeerKey
        ))
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sync/pair")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)
        #expect((response as! HTTPURLResponse).statusCode == 403)

        await server.stop()
    }

    @Test("POST /sync/pair rejects wrong code")
    func testPairRejectsWrongCode() async throws {
        let state = makeState(deviceId: "shop-dev", companyId: "co-1")
        try await state.setActivePairingCode("ABCD-1234")
        let server = LanSyncServer(state: state)
        let port = try await server.start()

        let body = try JSONEncoder().encode(SyncPairRequest(
            deviceId: "phone-dev",
            deviceName: "Phone",
            pairingCode: "WXYZ-1234",
            platform: "iOS",
            keyAgreementPublicKey: validPeerKey
        ))
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sync/pair")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)
        #expect((response as! HTTPURLResponse).statusCode == 403)

        await server.stop()
    }

    @Test("POST /sync/pair accepts active code once")
    func testPairAcceptsActiveCodeOnce() async throws {
        let state = makeState(deviceId: "shop-dev", companyId: "co-1")
        try await state.setActivePairingCode("ABCD-1234")
        let server = LanSyncServer(state: state)
        let port = try await server.start()

        let body = try JSONEncoder().encode(SyncPairRequest(
            deviceId: "phone-dev",
            deviceName: "Phone",
            pairingCode: "abcd1234",
            platform: "iOS",
            keyAgreementPublicKey: validPeerKey
        ))
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sync/pair")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, firstResponse) = try await URLSession.shared.data(for: request)
        #expect((firstResponse as! HTTPURLResponse).statusCode == 200)
        let pairResponse = try JSONDecoder().decode(SyncPairResponse.self, from: data)
        #expect(pairResponse.accepted)
        #expect(pairResponse.serverDeviceId == "shop-dev")
        #expect(pairResponse.companyId == "co-1")
        #expect(!pairResponse.pairedAt.isEmpty)

        let (_, secondResponse) = try await URLSession.shared.data(for: request)
        #expect((secondResponse as! HTTPURLResponse).statusCode == 403)

        await server.stop()
    }

    @Test("POST /sync/pair consumes active code atomically under concurrency")
    func testPairConsumesActiveCodeAtomicallyUnderConcurrency() async throws {
        let state = makeState(deviceId: "shop-dev", companyId: "co-1")
        try await state.setActivePairingCode("ABCD-1234")
        let server = LanSyncServer(state: state)
        let port = try await server.start()

        func makeRequest(deviceId: String) throws -> URLRequest {
            let body = try JSONEncoder().encode(SyncPairRequest(
                deviceId: deviceId,
                deviceName: "Phone",
                pairingCode: "abcd1234",
                platform: "iOS",
                keyAgreementPublicKey: validPeerKey
            ))
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sync/pair")!)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            return request
        }

        async let first = URLSession.shared.data(for: makeRequest(deviceId: "phone-dev-a"))
        async let second = URLSession.shared.data(for: makeRequest(deviceId: "phone-dev-b"))

        let firstStatus = try await (first.1 as! HTTPURLResponse).statusCode
        let secondStatus = try await (second.1 as! HTTPURLResponse).statusCode
        #expect([firstStatus, secondStatus].sorted() == [200, 403])

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

        let (request, sharedKey) = try await makeEncryptedRequest(
            url: URL(string: "http://127.0.0.1:\(port)/sync/push")!,
            plainBody: body,
            state: state
        )

        let (encryptedData, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse
        #expect(httpResponse.statusCode == 200)

        let data = try decryptResponse(encryptedData, sharedKey: sharedKey)
        let pushResponse = try JSONDecoder().decode(SyncPushResponse.self, from: data)
        #expect(pushResponse.accepted == 1)
        #expect(!pushResponse.syncBatchId.isEmpty)

        await server.stop()
    }

    @Test("POST /sync/push rejects plaintext payloads")
    func testPushRejectsPlaintextPayload() async throws {
        let state = makeState(companyId: "co-1")
        let server = LanSyncServer(state: state)
        let port = try await server.start()
        defer { Task { await server.stop() } }

        let body = try JSONEncoder().encode(SyncPushRequest(
            deviceId: "remote-dev",
            companyId: "co-1",
            changes: []
        ))
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sync/push")!)
        request.httpMethod = "POST"
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        #expect((response as! HTTPURLResponse).statusCode == 400)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: String]
        #expect(json?["error"] == "decryption_failed")
    }

    @Test("POST /sync/push rejects an encrypted payload from an unpaired sender key")
    func testPushRejectsUnpairedSenderKey() async throws {
        let state = makeState(companyId: "co-1")
        let server = LanSyncServer(state: state)
        let port = try await server.start()
        defer { Task { await server.stop() } }

        let (privateKey, publicKey) = SyncCrypto.generateKeyAgreementPair()
        let sharedKey = try SyncCrypto.deriveSharedKeyData(
            ourPrivateKeyB64: privateKey,
            theirPublicKeyB64: state.kaPublicKeyB64
        )
        let plain = try JSONEncoder().encode(SyncPushRequest(
            deviceId: "attacker",
            companyId: "co-1",
            changes: []
        ))
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sync/push")!)
        request.httpMethod = "POST"
        request.httpBody = try SyncCrypto.encryptAESGCM(data: plain, keyData: sharedKey)
        request.setValue("1", forHTTPHeaderField: "X-Sync-Encrypted")
        request.setValue(publicKey, forHTTPHeaderField: "X-Sync-Sender-Key")
        request.setValue("attacker", forHTTPHeaderField: "X-Sync-Device-ID")

        let (_, response) = try await URLSession.shared.data(for: request)
        #expect((response as! HTTPURLResponse).statusCode == 400)
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
        let (request, _) = try await makeEncryptedRequest(
            url: URL(string: "http://127.0.0.1:\(port)/sync/push")!,
            plainBody: body,
            state: state
        )

        let (_, _) = try await URLSession.shared.data(for: request)

        // Verify inbox
        let inbox = await state.drainInbox()
        #expect(inbox.map(\.recordId) == ["1", "2"])

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
        let (request, sharedKey) = try await makeEncryptedRequest(
            url: URL(string: "http://127.0.0.1:\(port)/sync/pull")!,
            plainBody: body,
            state: state
        )

        let (encryptedData, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse
        #expect(httpResponse.statusCode == 200)

        let data = try decryptResponse(encryptedData, sharedKey: sharedKey)
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
        let (request, sharedKey) = try await makeEncryptedRequest(
            url: URL(string: "http://127.0.0.1:\(port)/sync/pull")!,
            plainBody: body,
            state: state
        )

        let (encryptedData, _) = try await URLSession.shared.data(for: request)
        let data = try decryptResponse(encryptedData, sharedKey: sharedKey)
        let pullResponse = try JSONDecoder().decode(SyncPullResponse.self, from: data)

        // Should only get IDs 2 and 3 (not 1)
        #expect(pullResponse.changes.count == 2)

        await server.stop()
    }

    // MARK: - Auth

    // MARK: - GET /sync/key (paired-device authorization)

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

    @Test("GET /sync/key rejects an unpaired device identity")
    func testKeyExchangeRejectsUnpairedDevice() async throws {
        let state = makeState(companyId: "co-1")
        let server = LanSyncServer(state: state)
        let port = try await server.start()
        defer { Task { await server.stop() } }

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/sync/key")!)
        req.setValue("co-1", forHTTPHeaderField: "X-Company-ID")
        req.setValue("unpaired-device", forHTTPHeaderField: "X-Sync-Device-ID")
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
        let (_, peerPublicKey) = SyncCrypto.generateKeyAgreementPair()
        try await state.registerAuthorizedPeer(
            deviceId: "remote-dev",
            deviceName: "Remote",
            platform: "test",
            keyAgreementPublicKey: peerPublicKey
        )
        req.setValue("co-1", forHTTPHeaderField: "X-Company-ID")
        req.setValue("remote-dev", forHTTPHeaderField: "X-Sync-Device-ID")
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
        var (req, _) = try await makeEncryptedRequest(
            url: URL(string: "http://127.0.0.1:\(port)/sync/push")!,
            plainBody: bodyData,
            state: state,
            deviceId: "client-dev"
        )
        req.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: req)
        #expect((response as! HTTPURLResponse).statusCode == 403)

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

        let encoder = JSONEncoder()
        let body = try encoder.encode(pushRequest)
        let (request, _) = try await makeEncryptedRequest(
            url: URL(string: "http://127.0.0.1:\(port)/sync/push")!,
            plainBody: body,
            state: state
        )

        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse
        #expect(httpResponse.statusCode == 403)

        await server.stop()
    }
}
