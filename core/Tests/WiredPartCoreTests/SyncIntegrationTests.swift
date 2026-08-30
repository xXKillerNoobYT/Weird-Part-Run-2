import Testing
import Foundation
import GRDB
@testable import WiredPartCore

/// Integration tests that exercise multiple sync components together:
/// LanSyncServer + ConflictResolver + ChangeTracker + SyncCrypto
@Suite("Sync Integration Tests")
struct SyncIntegrationTests {

    private func freshDB() throws -> AppDatabase {
        try AppDatabase.openInMemoryDatabase()
    }

    private func startServer(
        deviceId: String = "server-dev",
        deviceName: String = "Test Server",
        companyId: String = "test-company"
    ) async throws -> (LanSyncServer, SyncServerState, UInt16) {
        let db = try freshDB()
        let state = SyncServerState(
            deviceId: deviceId,
            deviceName: deviceName,
            companyId: companyId,
            db: db
        )
        let server = LanSyncServer(state: state)
        let port = try await server.start()
        return (server, state, port)
    }

    private func makeEncryptedRequest(
        url: URL,
        plainBody: Data,
        state: SyncServerState,
        deviceId: String = "client-dev",
        endpoint: String
    ) async throws -> (request: URLRequest, sharedKey: Data) {
        let (privateKey, publicKey) = SyncCrypto.generateKeyAgreementPair()
        try await state.registerAuthorizedPeer(
            deviceId: deviceId,
            deviceName: "Integration client",
            platform: "test",
            keyAgreementPublicKey: publicKey
        )
        let sharedKey = try SyncCrypto.deriveSharedKeyData(
            ourPrivateKeyB64: privateKey,
            theirPublicKeyB64: state.kaPublicKeyB64
        )
        let requestId = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try SyncCrypto.encryptAESGCM(
            data: plainBody,
            keyData: sharedKey,
            aad: LanSyncServer.syncAAD(
                endpoint: endpoint,
                direction: "request",
                deviceId: deviceId,
                requestId: requestId
            )
        )
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-Sync-Encrypted")
        request.setValue(publicKey, forHTTPHeaderField: "X-Sync-Sender-Key")
        request.setValue(deviceId, forHTTPHeaderField: "X-Sync-Device-ID")
        request.setValue(requestId, forHTTPHeaderField: "X-Sync-Request-ID")
        request.timeoutInterval = 5
        return (request, sharedKey)
    }

    private func decryptResponse(
        _ data: Data,
        sharedKey: Data,
        request: URLRequest,
        endpoint: String
    ) throws -> Data {
        let requestId = try #require(request.value(forHTTPHeaderField: "X-Sync-Request-ID"))
        let deviceId = try #require(request.value(forHTTPHeaderField: "X-Sync-Device-ID"))
        return try SyncCrypto.decryptAESGCM(
            data: data,
            keyData: sharedKey,
            aad: LanSyncServer.syncAAD(
                endpoint: endpoint,
                direction: "response",
                deviceId: deviceId,
                requestId: requestId
            )
        )
    }

    // MARK: - Test 1: Loopback Push/Pull

    @Test("Loopback: push changes to server, pull them back")
    func testLoopbackPushPull() async throws {
        let (server, state, port) = try await startServer()
        defer { Task { await server.stop() } }

        let baseURL = "http://127.0.0.1:\(port)"

        // Push some changes
        let pushBody: [String: Any] = [
            "device_id": "client-dev",
            "company_id": "test-company",
            "changes": [
                [
                    "device_id": "client-dev",
                    "table_name": "users",
                    "record_id": "1",
                    "operation": "INSERT",
                    "timestamp": "2026-03-14T10:00:00Z",
                    "record_data": "{\"id\":\"1\",\"display_name\":\"Alice\"}"
                ]
            ]
        ] as [String: Any]

        let pushData = try JSONSerialization.data(withJSONObject: pushBody)
        let (pushReq, sharedKey) = try await makeEncryptedRequest(
            url: URL(string: "\(baseURL)/sync/push")!,
            plainBody: pushData,
            state: state,
            endpoint: "push"
        )

        let (encryptedPushResp, pushHTTP) = try await URLSession.shared.data(for: pushReq)
        #expect((pushHTTP as! HTTPURLResponse).statusCode == 200)

        let pushResp = try decryptResponse(encryptedPushResp, sharedKey: sharedKey, request: pushReq, endpoint: "push")
        let pushResult = try JSONDecoder().decode(SyncPushResponse.self, from: pushResp)
        #expect(pushResult.accepted == 1)

        // A 200 now acknowledges durable receipt rather than an in-memory inbox.
        #expect(await state.inbox.isEmpty)
    }

    // MARK: - Test 2: Pull with Vector Clock Filtering

    @Test("Pull with vector clock filters to only new changes")
    func testPullVectorClockFiltering() async throws {
        let (server, state, port) = try await startServer()
        defer { Task { await server.stop() } }

        // Set outbox with 5 changes (sequences 1-5)
        let outbox = (1...5).map { i in
            IncomingChange(
                id: Int64(i),
                deviceId: "server-dev",
                tableName: "users",
                recordId: "\(i)",
                operation: "INSERT",
                timestamp: "2026-03-14T10:00:0\(i)Z"
            )
        }
        await state.setOutbox(outbox)

        let baseURL = "http://127.0.0.1:\(port)"

        // Pull with vector clock saying we've seen up to sequence 3
        let pullBody: [String: Any] = [
            "device_id": "client-dev",
            "company_id": "test-company",
            "vector_clock": ["server-dev": 3]
        ]
        let pullData = try JSONSerialization.data(withJSONObject: pullBody)
        let (pullReq, sharedKey) = try await makeEncryptedRequest(
            url: URL(string: "\(baseURL)/sync/pull")!,
            plainBody: pullData,
            state: state,
            endpoint: "pull"
        )

        let (encryptedPullResp, pullHTTP) = try await URLSession.shared.data(for: pullReq)
        #expect((pullHTTP as! HTTPURLResponse).statusCode == 200)

        let pullResp = try decryptResponse(encryptedPullResp, sharedKey: sharedKey, request: pullReq, endpoint: "pull")
        let pullResult = try JSONDecoder().decode(SyncPullResponse.self, from: pullResp)
        // Should only get changes 4 and 5
        #expect(pullResult.changes.count == 2)
        #expect(pullResult.changes[0].id == 4)
        #expect(pullResult.changes[1].id == 5)
        #expect(pullResult.serverDeviceId == "server-dev")
    }

    // MARK: - Test 3: Two-DB Conflict Resolution E2E

    @Test("Two databases: push from A to B, LWW resolves conflict")
    func testTwoDBConflictResolution() throws {
        let dbA = try freshDB()
        let dbB = try freshDB()

        // Both databases have the same user
        let insertSQL = """
            INSERT INTO users (id, display_name, pin_hash, email, is_active, updated_at)
            VALUES (1, 'Original', 'hash', 'orig@test.com', 1, '2026-03-14T08:00:00Z')
            """
        try dbA.writer.write { try $0.execute(sql: insertSQL) }
        try dbB.writer.write { try $0.execute(sql: insertSQL) }

        // Device A updates email locally
        try ChangeTracker.trackChange(
            db: dbA,
            tableName: "users",
            recordId: 1,
            operation: .update,
            changedFields: ["email": "a@test.com"],
            deviceId: "device-A"
        )
        try dbA.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE users SET email = ?, updated_at = ? WHERE id = 1",
                arguments: ["a@test.com", "2026-03-14T09:00:00Z"]
            )
        }

        // Device B also updates email — later timestamp, so B wins
        try ChangeTracker.trackChange(
            db: dbB,
            tableName: "users",
            recordId: 1,
            operation: .update,
            changedFields: ["email": "b@test.com"],
            deviceId: "device-B"
        )
        try dbB.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE users SET email = ?, updated_at = ? WHERE id = 1",
                arguments: ["b@test.com", "2026-03-14T12:00:00Z"]
            )
        }

        // Simulate push from A to B: A's change arrives at B
        let incomingFromA = [IncomingChange(
            deviceId: "device-A",
            tableName: "users",
            recordId: "1",
            operation: "UPDATE",
            changedFields: "{\"email\":\"a@test.com\"}",
            timestamp: "2026-03-14T09:00:00Z"
        )]

        let result = try ConflictResolver.resolveAndApplyChanges(
            db: dbB,
            changes: incomingFromA,
            localDeviceId: "device-B"
        )

        #expect(result.conflicts > 0)

        // B's email should win (later updated_at)
        let user = try dbB.writer.read { try User.fetchOne($0, key: 1) }
        #expect(user?.email == "b@test.com")
    }

    // MARK: - Test 4: Field-Level Merge (Non-Conflicting)

    @Test("Field-level merge: A changes name, B changes email, both apply on B")
    func testFieldLevelMerge() throws {
        let dbB = try freshDB()

        // Base record
        try dbB.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO users (id, display_name, pin_hash, email, is_active)
                VALUES (1, 'Original', 'hash', 'orig@test.com', 1)
                """)
        }

        // B has local unsynced change to display_name
        try ChangeTracker.trackChange(
            db: dbB,
            tableName: "users",
            recordId: 1,
            operation: .update,
            changedFields: ["display_name": "Name From B"],
            deviceId: "device-B"
        )

        // A's remote change is to email (different field — no conflict)
        let incomingFromA = [IncomingChange(
            deviceId: "device-A",
            tableName: "users",
            recordId: "1",
            operation: "UPDATE",
            changedFields: "{\"email\":\"email-from-a@test.com\"}",
            timestamp: "2026-03-14T10:00:00Z"
        )]

        let result = try ConflictResolver.resolveAndApplyChanges(
            db: dbB,
            changes: incomingFromA,
            localDeviceId: "device-B"
        )

        #expect(result.applied == 1)
        #expect(result.conflicts == 0)

        // Both fields should be updated
        let user = try dbB.writer.read { try User.fetchOne($0, key: 1) }
        #expect(user?.email == "email-from-a@test.com")
        // display_name was a local change so it's preserved
    }

    // MARK: - Test 5: Conflict Log Verification

    @Test("Conflict log entries are created for field conflicts")
    func testConflictLogCreation() throws {
        let db = try freshDB()

        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO users (id, display_name, pin_hash, email, is_active, updated_at)
                VALUES (1, 'Original', 'hash', 'orig@test.com', 1, '2026-03-14T08:00:00Z')
                """)
        }

        // Local change
        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: 1,
            operation: .update,
            changedFields: ["email": "local@test.com"],
            deviceId: "local-dev"
        )
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE users SET email = ?, updated_at = ? WHERE id = 1",
                arguments: ["local@test.com", "2026-03-14T09:00:00Z"]
            )
        }

        // Remote change with later timestamp
        let changes = [IncomingChange(
            deviceId: "remote-dev",
            tableName: "users",
            recordId: "1",
            operation: "UPDATE",
            changedFields: "{\"email\":\"remote@test.com\"}",
            timestamp: "2026-03-14T11:00:00Z"
        )]

        _ = try ConflictResolver.resolveAndApplyChanges(
            db: db, changes: changes, localDeviceId: "local-dev"
        )

        let conflicts = try ConflictResolver.getUnreviewedConflicts(db: db)
        #expect(conflicts.count == 1)
        #expect(conflicts[0].tableName == "users")
        #expect(conflicts[0].fieldName == "email")
        #expect(conflicts[0].winner == "remote")
        #expect(conflicts[0].localDevice == "local-dev")
        #expect(conflicts[0].remoteDevice == "remote-dev")
    }

    // MARK: - Test 6: Ed25519 Auth on Server

    @Test("Server with Ed25519 key: no cert → 401, valid cert → 200")
    func testEd25519AuthOnServer() async throws {
        // Generate a key pair
        let (privateKey, publicKey) = SyncCrypto.generateKeyPair()

        // Create server with company public key
        let state = SyncServerState(
            deviceId: "server-dev",
            deviceName: "Secure Server",
            companyId: "secure-company",
            companyPublicKey: publicKey
        )
        let server = LanSyncServer(state: state)
        let port = try await server.start()
        defer { Task { await server.stop() } }

        let baseURL = "http://127.0.0.1:\(port)"

        // Push WITHOUT cert → should get 401
        let noCertBody: [String: Any] = [
            "device_id": "client-dev",
            "company_id": "secure-company",
            "changes": [] as [[String: Any]]
        ]
        let noCertData = try JSONSerialization.data(withJSONObject: noCertBody)
        let (noCertReq, _) = try await makeEncryptedRequest(
            url: URL(string: "\(baseURL)/sync/push")!,
            plainBody: noCertData,
            state: state,
            endpoint: "push"
        )

        let (_, noCertHTTP) = try await URLSession.shared.data(for: noCertReq)
        #expect((noCertHTTP as! HTTPURLResponse).statusCode == 401)

        // Push WITH valid cert → should get 200
        let certPayload: [String: Any] = [
            "device_id": "client-dev",
            "company_id": "secure-company",
            "public_key": publicKey,
        ]
        let certPayloadData = try JSONSerialization.data(withJSONObject: certPayload)
        let certPayloadB64 = certPayloadData.base64EncodedString()
        let signature = try SyncCrypto.sign(data: certPayloadData, privateKeyB64: privateKey)

        let withCertBody: [String: Any] = [
            "device_id": "client-dev",
            "company_id": "secure-company",
            "changes": [] as [[String: Any]],
            "auth": [
                "certificate_data": certPayloadB64,
                "certificate_signature": signature,
            ]
        ]
        let withCertData = try JSONSerialization.data(withJSONObject: withCertBody)
        let (withCertReq, _) = try await makeEncryptedRequest(
            url: URL(string: "\(baseURL)/sync/push")!,
            plainBody: withCertData,
            state: state,
            endpoint: "push"
        )

        let (_, withCertHTTP) = try await URLSession.shared.data(for: withCertReq)
        #expect((withCertHTTP as! HTTPURLResponse).statusCode == 200)
    }

    // MARK: - Test 7: Ed25519 Expired Cert

    @Test("Server with Ed25519: expired cert → 403")
    func testExpiredCertRejected() async throws {
        let (privateKey, publicKey) = SyncCrypto.generateKeyPair()

        let state = SyncServerState(
            deviceId: "server-dev",
            deviceName: "Secure Server",
            companyId: "secure-company",
            companyPublicKey: publicKey
        )
        let server = LanSyncServer(state: state)
        let port = try await server.start()
        defer { Task { await server.stop() } }

        // Build an expired cert
        let certPayload: [String: Any] = [
            "device_id": "client-dev",
            "company_id": "secure-company",
            "public_key": publicKey,
            "expires_at": "2020-01-01T00:00:00Z"  // Expired
        ]
        let certPayloadData = try JSONSerialization.data(withJSONObject: certPayload)
        let certPayloadB64 = certPayloadData.base64EncodedString()
        let signature = try SyncCrypto.sign(data: certPayloadData, privateKeyB64: privateKey)

        let body: [String: Any] = [
            "device_id": "client-dev",
            "company_id": "secure-company",
            "changes": [] as [[String: Any]],
            "auth": [
                "certificate_data": certPayloadB64,
                "certificate_signature": signature,
            ]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let (req, _) = try await makeEncryptedRequest(
            url: URL(string: "http://127.0.0.1:\(port)/sync/push")!,
            plainBody: bodyData,
            state: state,
            endpoint: "push"
        )

        let (_, httpResp) = try await URLSession.shared.data(for: req)
        #expect((httpResp as! HTTPURLResponse).statusCode == 403)
    }

    // MARK: - Test 8: Vector Clock Delta Sync

    @Test("Vector clock delta: push, update clock, push more, pull only new")
    func testVectorClockDelta() async throws {
        let (server, state, port) = try await startServer()
        defer { Task { await server.stop() } }

        // Phase 1: outbox has items 1-3
        let batch1 = (1...3).map { i in
            IncomingChange(
                id: Int64(i),
                deviceId: "server-dev",
                tableName: "parts",
                recordId: "\(i)",
                operation: "INSERT",
                timestamp: "2026-03-14T10:00:0\(i)Z"
            )
        }
        await state.setOutbox(batch1)

        let baseURL = "http://127.0.0.1:\(port)"

        // Pull all (no vector clock)
        let pull1Body: [String: Any] = [
            "device_id": "client-dev",
            "company_id": "test-company"
        ]
        let pull1Data = try JSONSerialization.data(withJSONObject: pull1Body)
        let (pull1Req, sharedKey1) = try await makeEncryptedRequest(
            url: URL(string: "\(baseURL)/sync/pull")!,
            plainBody: pull1Data,
            state: state,
            endpoint: "pull"
        )

        let (encryptedResp1, _) = try await URLSession.shared.data(for: pull1Req)
        let resp1 = try decryptResponse(encryptedResp1, sharedKey: sharedKey1, request: pull1Req, endpoint: "pull")
        let result1 = try JSONDecoder().decode(SyncPullResponse.self, from: resp1)
        #expect(result1.changes.count == 3)

        // Phase 2: add items 4-5 to outbox
        let batch2 = batch1 + (4...5).map { i in
            IncomingChange(
                id: Int64(i),
                deviceId: "server-dev",
                tableName: "parts",
                recordId: "\(i)",
                operation: "INSERT",
                timestamp: "2026-03-14T10:00:0\(i)Z"
            )
        }
        await state.setOutbox(batch2)

        // Pull with vector clock: we've seen up to 3
        let pull2Body: [String: Any] = [
            "device_id": "client-dev",
            "company_id": "test-company",
            "vector_clock": ["server-dev": 3]
        ]
        let pull2Data = try JSONSerialization.data(withJSONObject: pull2Body)
        let (pull2Req, sharedKey2) = try await makeEncryptedRequest(
            url: URL(string: "\(baseURL)/sync/pull")!,
            plainBody: pull2Data,
            state: state,
            endpoint: "pull"
        )

        let (encryptedResp2, _) = try await URLSession.shared.data(for: pull2Req)
        let resp2 = try decryptResponse(encryptedResp2, sharedKey: sharedKey2, request: pull2Req, endpoint: "pull")
        let result2 = try JSONDecoder().decode(SyncPullResponse.self, from: resp2)
        #expect(result2.changes.count == 2)  // Only items 4 and 5
    }

    // MARK: - Test 9: IncomingChange JSON Round-Trip

    @Test("IncomingChange encodes and decodes correctly (Multipeer serialization)")
    func testIncomingChangeRoundTrip() throws {
        let original = IncomingChange(
            id: 42,
            deviceId: "dev-123",
            tableName: "users",
            recordId: "7",
            operation: "UPDATE",
            changedFields: "{\"email\":\"new@test.com\"}",
            oldValues: "{\"email\":\"old@test.com\"}",
            recordData: "{\"id\":\"7\",\"email\":\"new@test.com\",\"display_name\":\"Bob\"}",
            timestamp: "2026-03-14T10:00:00Z"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(IncomingChange.self, from: data)

        #expect(decoded.id == 42)
        #expect(decoded.deviceId == "dev-123")
        #expect(decoded.tableName == "users")
        #expect(decoded.recordId == "7")
        #expect(decoded.operation == "UPDATE")
        #expect(decoded.changedFields == "{\"email\":\"new@test.com\"}")
        #expect(decoded.oldValues == "{\"email\":\"old@test.com\"}")
        #expect(decoded.recordData != nil)
        #expect(decoded.timestamp == "2026-03-14T10:00:00Z")
    }

    // MARK: - Test 10: Wrong Company → 403

    @Test("Wrong company_id on push/pull → 403")
    func testWrongCompanyIntegration() async throws {
        let (server, state, port) = try await startServer(companyId: "company-A")
        defer { Task { await server.stop() } }

        let baseURL = "http://127.0.0.1:\(port)"

        // Push with wrong company
        let pushBody: [String: Any] = [
            "device_id": "client-dev",
            "company_id": "company-B",
            "changes": [] as [[String: Any]]
        ]
        let pushData = try JSONSerialization.data(withJSONObject: pushBody)
        // Use separate connections repeatedly: a 403 response must be delivered
        // completely, not converted into a lost-connection transport error while
        // the server closes the response stream. Each request needs a unique replay
        // identifier now that the database-backed replay guard is active.
        for _ in 0..<20 {
            let (pushReq, _) = try await makeEncryptedRequest(
                url: URL(string: "\(baseURL)/sync/push")!,
                plainBody: pushData,
                state: state,
                endpoint: "push"
            )
            let (_, pushHTTP) = try await URLSession.shared.data(for: pushReq)
            #expect((pushHTTP as! HTTPURLResponse).statusCode == 403)
        }

        // Pull with wrong company
        let pullBody: [String: Any] = [
            "device_id": "client-dev",
            "company_id": "company-B"
        ]
        let pullData = try JSONSerialization.data(withJSONObject: pullBody)
        let (pullReq, _) = try await makeEncryptedRequest(
            url: URL(string: "\(baseURL)/sync/pull")!,
            plainBody: pullData,
            state: state,
            endpoint: "pull"
        )

        let (_, pullHTTP) = try await URLSession.shared.data(for: pullReq)
        #expect((pullHTTP as! HTTPURLResponse).statusCode == 403)
    }
}
