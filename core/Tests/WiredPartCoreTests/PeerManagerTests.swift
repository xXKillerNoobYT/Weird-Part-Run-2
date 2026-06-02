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
