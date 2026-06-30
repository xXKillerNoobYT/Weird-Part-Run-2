import Testing
import Foundation
@testable import WiredPartCore

@Suite("PeerManager Tests")
struct PeerManagerTests {

    private func freshDB() throws -> AppDatabase {
        try AppDatabase.openInMemoryDatabase()
    }

    @Test("Initial state is not running with empty peers")
    func testInitialState() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)
        let state = await pm.getState()
        #expect(state.running == false)
        #expect(state.syncPort == 0)
        #expect(state.peers.isEmpty)
        #expect(state.lastPeerSyncs.isEmpty)
        #expect(state.syncingWith == nil)
    }

    @Test("isOfficePeer detects office-like names")
    func testIsOfficePeer() {
        let office = DiscoveredPeer(
            deviceId: "dev-1",
            deviceName: "Office Mac",
            companyId: "co",
            host: "10.0.0.1",
            port: 8080
        )
        #expect(PeerManager.isOfficePeer(office) == true)

        let shop = DiscoveredPeer(
            deviceId: "dev-2",
            deviceName: "Shop Computer",
            companyId: "co",
            host: "10.0.0.2",
            port: 8080
        )
        #expect(PeerManager.isOfficePeer(shop) == true)

        let server = DiscoveredPeer(
            deviceId: "dev-3",
            deviceName: "Main Server",
            companyId: "co",
            host: "10.0.0.3",
            port: 8080
        )
        #expect(PeerManager.isOfficePeer(server) == true)

        let phone = DiscoveredPeer(
            deviceId: "dev-4",
            deviceName: "John's iPhone",
            companyId: "co",
            host: "10.0.0.4",
            port: 8080
        )
        #expect(PeerManager.isOfficePeer(phone) == false)
    }

    @Test("enrichChangesWithData includes record_data for INSERT")
    func testEnrichInsert() async throws {
        let db = try freshDB()

        // Insert a user
        try await db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active)
                VALUES ('Alice', 'hash123', 1)
                """)
        }

        // Create a change log entry for that user
        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: 1,
            operation: .insert,
            deviceId: "test-device"
        )

        let pm = PeerManager(db: db)
        let pending = try ChangeTracker.getPendingChanges(db: db)
        let enriched = try await pm.testEnrichChanges(pending)

        #expect(enriched.count == 1)
        #expect(enriched[0].recordData != nil)
        #expect(enriched[0].recordData!.contains("Alice"))
        #expect(enriched[0].operation == "INSERT")
    }

    @Test("enrichChangesWithData skips record_data for DELETE")
    func testEnrichDelete() async throws {
        let db = try freshDB()

        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: 999,
            operation: .delete,
            deviceId: "test-device"
        )

        let pm = PeerManager(db: db)
        let pending = try ChangeTracker.getPendingChanges(db: db)
        let enriched = try await pm.testEnrichChanges(pending)

        #expect(enriched.count == 1)
        #expect(enriched[0].recordData == nil)
        #expect(enriched[0].operation == "DELETE")
    }

    @Test("Sync with unreachable peer returns failure")
    func testUnreachablePeer() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)

        // Start peer sync so serverState is set
        try await pm.startPeerSync(
            deviceId: "dev-001",
            deviceName: "Test Device",
            companyId: "test-company"
        )

        let peer = DiscoveredPeer(
            deviceId: "unreachable-dev",
            deviceName: "Unreachable",
            companyId: "test-company",
            host: "127.0.0.1",
            port: 1,  // Connection refused
            transport: "lan"
        )

        let result = await pm.syncWithPeer(peer)
        #expect(result.success == false)
        #expect(result.error != nil)
        #expect(result.peerDeviceId == "unreachable-dev")

        await pm.stopPeerSync()
    }

    @Test("Sync by peer device ID does not fall back to all peers")
    func testSyncByPeerDeviceIdRequiresSelectedPeer() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)

        let result = await pm.syncWithPeer(deviceId: "missing-peer")

        #expect(result.success == false)
        #expect(result.peerDeviceId == "missing-peer")
        #expect(result.error == "Peer not found: missing-peer")

        let state = await pm.getState()
        #expect(state.lastPeerSyncs["missing-peer"]?.success == false)
        #expect(state.lastPeerSyncs.count == 1)
    }

    @Test("LAN sync reports HTTP pull errors as failed peer sync")
    func testLANSyncHTTPPullErrorReturnsFailure() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)

        try await pm.startPeerSync(
            deviceId: "local-dev",
            deviceName: "Local Device",
            companyId: "local-company"
        )

        let foreignState = SyncServerState(
            deviceId: "foreign-dev",
            deviceName: "Foreign Device",
            companyId: "foreign-company"
        )
        let foreignServer = LanSyncServer(state: foreignState)
        let foreignPort = try await foreignServer.start()

        let peer = DiscoveredPeer(
            deviceId: "foreign-dev",
            deviceName: "Foreign Device",
            companyId: "foreign-company",
            host: "127.0.0.1",
            port: foreignPort,
            transport: "lan"
        )

        let result = await pm.syncWithPeer(peer)

        #expect(result.success == false)
        #expect(result.error == "LAN sync pull failed: HTTP 403")
        #expect(result.peerDeviceId == "foreign-dev")

        let state = await pm.getState()
        #expect(state.lastPeerSyncs["foreign-dev"]?.success == false)

        await foreignServer.stop()
        await pm.stopPeerSync()
    }

    @Test("LAN sync reports malformed 200 pull responses as failed peer sync")
    func testLANSyncMalformedPullResponseReturnsFailure() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)

        try await pm.startPeerSync(
            deviceId: "local-dev",
            deviceName: "Local Device",
            companyId: "local-company"
        )

        let malformedServer = try HTTPStubServer(
            statusCode: 200,
            body: #"{"not":"a-sync-pull-response"}"#
        )
        let port = try await malformedServer.start()

        let peer = DiscoveredPeer(
            deviceId: "malformed-dev",
            deviceName: "Malformed Peer",
            companyId: "local-company",
            host: "127.0.0.1",
            port: port,
            transport: "lan"
        )

        let result = await pm.syncWithPeer(peer)

        #expect(result.success == false)
        #expect(result.error != nil)
        #expect(result.peerDeviceId == "malformed-dev")

        let state = await pm.getState()
        #expect(state.lastPeerSyncs["malformed-dev"]?.success == false)

        malformedServer.stop()
        await pm.stopPeerSync()
    }

    @Test("LAN sync reports HTTP push errors as failed peer sync")
    func testLANSyncHTTPPushErrorReturnsFailure() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)

        try await db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active)
                VALUES ('Alice', 'hash123', 1)
                """)
        }
        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: 1,
            operation: .insert,
            deviceId: "local-dev"
        )

        try await pm.startPeerSync(
            deviceId: "local-dev",
            deviceName: "Local Device",
            companyId: "local-company"
        )

        let foreignState = SyncServerState(
            deviceId: "foreign-dev",
            deviceName: "Foreign Device",
            companyId: "foreign-company"
        )
        let foreignServer = LanSyncServer(state: foreignState)
        let foreignPort = try await foreignServer.start()

        let peer = DiscoveredPeer(
            deviceId: "foreign-dev",
            deviceName: "Foreign Device",
            companyId: "foreign-company",
            host: "127.0.0.1",
            port: foreignPort,
            transport: "lan"
        )

        let result = await pm.syncWithPeer(peer)

        #expect(result.success == false)
        #expect(result.error == "LAN sync push failed: HTTP 403")
        #expect(result.peerDeviceId == "foreign-dev")
        #expect(try ChangeTracker.getPendingChangeCount(db: db) == 1)

        await foreignServer.stop()
        await pm.stopPeerSync()
    }

    @Test("LAN sync base URL is built from host and discovered port")
    func testLANSyncBaseURLUsesPeerHostAndPort() throws {
        let peer = DiscoveredPeer(
            deviceId: "dev-url",
            deviceName: "Office Mac",
            companyId: "co",
            host: "192.168.1.50",
            port: 51943
        )

        let baseURL = try PeerManager.makeLANSyncBaseURL(for: peer)

        #expect(baseURL.absoluteString == "http://192.168.1.50:51943")
        #expect(baseURL.appendingPathComponent("sync/pull").absoluteString == "http://192.168.1.50:51943/sync/pull")
    }

    @Test("LAN sync base URL normalizes bracketless IPv6")
    func testLANSyncBaseURLNormalizesIPv6() throws {
        let peer = DiscoveredPeer(
            deviceId: "dev-ipv6",
            deviceName: "Office Mac",
            companyId: "co",
            host: "fe80::1",
            port: 51943
        )

        let baseURL = try PeerManager.makeLANSyncBaseURL(for: peer)

        #expect(baseURL.absoluteString == "http://[fe80::1]:51943")
    }

    @Test("LAN sync base URL rejects incomplete Bonjour endpoint data")
    func testLANSyncBaseURLRejectsMissingPort() {
        let peer = DiscoveredPeer(
            deviceId: "dev-bad",
            deviceName: "Office Mac",
            companyId: "co",
            host: "WiredPart-dev-bad",
            port: 0
        )

        #expect(throws: URLError.self) {
            _ = try PeerManager.makeLANSyncBaseURL(for: peer)
        }
    }

    @Test("LAN sync base URL rejects raw Bonjour service instance hosts")
    func testLANSyncBaseURLRejectsRawBonjourInstanceName() {
        let peer = DiscoveredPeer(
            deviceId: "dev-bonjour",
            deviceName: "Office Mac",
            companyId: "co",
            host: "WiredPart-dev-bonjour",
            port: 51943
        )

        #expect(throws: URLError.self) {
            _ = try PeerManager.makeLANSyncBaseURL(for: peer)
        }
    }

    @Test("PeerManager issued pairing code activates sync pair endpoint")
    func testIssuedPairingCodePairsThroughSyncServer() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)

        try await pm.startPeerSync(
            deviceId: "shop-dev",
            deviceName: "Shop Mac",
            companyId: "co-1"
        )
        let issuedCode = try await pm.issuePairingCode()
        #expect(SyncCrypto.normalizedPairingCode(issuedCode) != nil)

        let state = await pm.getState()
        let body = try JSONEncoder().encode(SyncPairRequest(
            deviceId: "phone-dev",
            deviceName: "Phone",
            pairingCode: issuedCode,
            platform: "iOS"
        ))
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(state.syncPort)/sync/pair")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        #expect((response as! HTTPURLResponse).statusCode == 200)
        let pairResponse = try JSONDecoder().decode(SyncPairResponse.self, from: data)
        #expect(pairResponse.accepted)
        #expect(pairResponse.serverDeviceId == "shop-dev")
        #expect(pairResponse.companyId == "co-1")

        let (_, secondResponse) = try await URLSession.shared.data(for: request)
        #expect((secondResponse as! HTTPURLResponse).statusCode == 403)

        await pm.stopPeerSync()
    }

    @Test("PeerSyncResult stores all fields correctly")
    func testPeerSyncResult() {
        let result = PeerSyncResult(
            peerDeviceId: "dev-123",
            peerName: "Test Peer",
            pushed: 5,
            pulled: 3,
            success: true
        )
        #expect(result.peerDeviceId == "dev-123")
        #expect(result.peerName == "Test Peer")
        #expect(result.pushed == 5)
        #expect(result.pulled == 3)
        #expect(result.success == true)
        #expect(result.error == nil)
        #expect(!result.syncedAt.isEmpty)
    }
}

// Test helper to expose private enrich method
extension PeerManager {
    func testEnrichChanges(_ entries: [ChangeLogEntry]) throws -> [IncomingChange] {
        try enrichChangesWithData(entries)
    }
}
