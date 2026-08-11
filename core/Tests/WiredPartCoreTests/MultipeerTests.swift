#if canImport(MultipeerConnectivity)
import Testing
import Foundation
import GRDB
import MultipeerConnectivity
@testable import WiredPartCore

@Suite("MultipeerManager Tests")
struct MultipeerTests {

    // MARK: - #1701 — CI must never advertise on the real Bluetooth mesh
    //
    // The suite stands up REAL advertisers (PeerManagerTests calls
    // startPeerSync on a real PeerManager) and the gate runs on a self-hosted
    // Mac beside the owner's devices, so a shared service type put fixture
    // peers into the production picker and broke live pairing.

    @Test("test processes never advertise on the production service type (#1701)")
    func testServiceTypeIsNotProductionUnderTest() {
        // This test itself runs under the test runner, so the detection that
        // gates the whole fix must be true here. If it is not, every assertion
        // below would pass vacuously.
        #expect(
            MultipeerManager.isRunningUnderTests,
            "test-process detection failed — the production service type would be used on the real mesh"
        )
        #expect(
            MultipeerManager.activeServiceType != MultipeerManager.productionServiceType,
            "CI is advertising on the production mesh; the owner's device picker will fill with fixture peers"
        )
        #expect(MultipeerManager.activeServiceType.hasPrefix("wpr2t-"))
    }

    @Test("the service type stays stable within a process so peers still find each other (#1701)")
    func testServiceTypeIsStableWithinProcess() {
        // Two managers in one test process must share a type, or any test that
        // relies on real discovery would silently stop discovering.
        #expect(MultipeerManager.activeServiceType == MultipeerManager.activeServiceType)
    }

    @Test("each generated test service type is unique and Bonjour-legal (#1701)")
    func testGeneratedServiceTypesAreUniqueAndValid() {
        let generated = (0..<50).map { _ in MultipeerManager.testScopedServiceType() }
        #expect(Set(generated).count == generated.count, "collision — two runs could see each other")
        for value in generated {
            #expect(
                MultipeerManager.isValidBonjourServiceType(value),
                "\(value) is not a legal Bonjour type; the advertiser would fail to start"
            )
            #expect(value != MultipeerManager.productionServiceType)
        }
    }

    @Test("Bonjour service-type validation rejects what MCNearbyService would reject (#1701)")
    func testBonjourValidationRules() {
        #expect(MultipeerManager.isValidBonjourServiceType("wiredpart-sync"))
        #expect(MultipeerManager.isValidBonjourServiceType("wpr2t-0a1b2c3d"))
        #expect(!MultipeerManager.isValidBonjourServiceType(""))
        #expect(!MultipeerManager.isValidBonjourServiceType("way-too-long-service"))  // 20 chars
        #expect(!MultipeerManager.isValidBonjourServiceType("-leadinghyphen"))
        #expect(!MultipeerManager.isValidBonjourServiceType("trailinghyphen-"))
        #expect(!MultipeerManager.isValidBonjourServiceType("double--hyphen"))
        #expect(!MultipeerManager.isValidBonjourServiceType("under_score"))
        #expect(!MultipeerManager.isValidBonjourServiceType("12345"))  // no letter
    }

    @Test("MultipeerPeerInfo stores all fields")
    func testPeerInfoInit() {
        let info = MultipeerPeerInfo(
            deviceId: "dev-123",
            deviceName: "iPad Pro",
            companyId: "company-abc",
            state: .found
        )
        #expect(info.deviceId == "dev-123")
        #expect(info.deviceName == "iPad Pro")
        #expect(info.companyId == "company-abc")
        #expect(info.state == .found)
        #expect(!info.discoveredAt.isEmpty)
    }

    @Test("ReceivedMultipeerMessage stores data correctly")
    func testReceivedMessage() {
        let payload = "Hello peer".data(using: .utf8)!
        let msg = ReceivedMultipeerMessage(
            fromDeviceId: "dev-456",
            data: payload
        )
        #expect(msg.fromDeviceId == "dev-456")
        #expect(msg.data == payload)
        #expect(!msg.receivedAt.isEmpty)
    }

    @Test("MultipeerManager initializes without crashing")
    func testManagerInit() {
        let manager = MultipeerManager(
            deviceId: "dev-001",
            deviceName: "Test Mac",
            companyId: "company-abc"
        )
        let peers = manager.getPeers()
        #expect(peers.isEmpty)
        #expect(manager.receiveQueueCount == 0)
    }

    @Test("send to unknown peer returns false")
    func testSendToUnknown() {
        let manager = MultipeerManager(
            deviceId: "dev-001",
            deviceName: "Test Mac",
            companyId: "company-abc"
        )
        let result = manager.send(
            data: "test".data(using: .utf8)!,
            toPeer: "nonexistent-device"
        )
        #expect(result == false)
    }

    @Test("popReceivedMessage returns nil when empty")
    func testPopEmpty() {
        let manager = MultipeerManager(
            deviceId: "dev-001",
            deviceName: "Test Mac",
            companyId: "company-abc"
        )
        let msg = manager.popReceivedMessage()
        #expect(msg == nil)
    }

    // MARK: - #1580 — a failed connection must not erase the discovered peer

    /// The pairing bug behind "discovery works, connecting fails".
    ///
    /// `awaitMultipeerConnection` invites, waits, and re-invites once if the
    /// first invitation lapses. Both `invite(deviceId:)` and
    /// `isConnected(toPeer:)` look the peer up in `peers` by device id. The
    /// session delegate used to REMOVE that entry on `.notConnected`, which
    /// MCSession reports whenever an invitation lapses — so the re-invite found
    /// nothing, returned a discarded `false`, and the join burned its whole
    /// timeout against a host that was still advertising the entire time.
    ///
    /// Discovery lifetime belongs to the browser (`foundPeer` / `lostPeer`).
    /// A dropped connection means "not connected", never "gone".
    @Test("a failed connection keeps the discovered peer so re-invite still works (#1580)")
    func testNotConnectedKeepsDiscoveredPeer() {
        let manager = MultipeerManager(
            deviceId: "joiner-1",
            deviceName: "Joiner iPhone",
            companyId: "company-abc",
            autoInvitePeers: false        // keep the test off the radio
        )
        let hostPeerId = MCPeerID(displayName: "Shop Mac")
        let browser = MCNearbyServiceBrowser(
            peer: MCPeerID(displayName: "Joiner iPhone"),
            serviceType: "wiredpart-sync"
        )

        manager.browser(browser, foundPeer: hostPeerId, withDiscoveryInfo: [
            "device_id": "host-1",
            "device_name": "Shop Mac",
            "company_id": "company-abc"
        ])
        // `getPeers()` is syncQueue.sync, and the delegate hops are
        // syncQueue.async on the same serial queue, so this observes them.
        #expect(manager.getPeers().contains { $0.deviceId == "host-1" })

        // The invitation lapses — exactly what the joiner hits in the field.
        let session = MCSession(peer: MCPeerID(displayName: "Joiner iPhone"))
        manager.session(session, peer: hostPeerId, didChange: .notConnected)

        let after = manager.getPeers()
        #expect(
            after.contains { $0.deviceId == "host-1" },
            "peer was erased on .notConnected — re-invite can never find it again"
        )
        #expect(after.first { $0.deviceId == "host-1" }?.state == .found)
    }

    /// `lostPeer` is the one thing that legitimately removes a peer.
    @Test("lostPeer still removes the peer (#1580)")
    func testLostPeerRemoves() {
        let manager = MultipeerManager(
            deviceId: "joiner-1",
            deviceName: "Joiner iPhone",
            companyId: "company-abc",
            autoInvitePeers: false
        )
        let hostPeerId = MCPeerID(displayName: "Shop Mac")
        let browser = MCNearbyServiceBrowser(
            peer: MCPeerID(displayName: "Joiner iPhone"),
            serviceType: "wiredpart-sync"
        )
        manager.browser(browser, foundPeer: hostPeerId, withDiscoveryInfo: [
            "device_id": "host-1",
            "device_name": "Shop Mac",
            "company_id": "company-abc"
        ])
        #expect(manager.getPeers().contains { $0.deviceId == "host-1" })

        manager.browser(browser, lostPeer: hostPeerId)
        #expect(!manager.getPeers().contains { $0.deviceId == "host-1" })
    }

    // MARK: - Cross-Device Sync with Different Cipher Keys

    /// Verifies that two devices with *different* SQLCipher keys can exchange
    /// application-layer sync records without coupling their encryption keys.
    ///
    /// Sync messages are JSON-encoded change records traveling over Multipeer's
    /// own TLS-equivalent transport.  Each device decodes the JSON in memory
    /// and writes the row through its own `AppDatabase` (which uses its own key).
    /// This test simulates that flow without real Multipeer networking by directly
    /// encoding/decoding a change record and writing it into each pool.
    @Test("testCrossDeviceSyncWithDifferentKeys — data written on device A is readable on device B")
    func testCrossDeviceSyncWithDifferentKeys() throws {
        let tmpDir = NSTemporaryDirectory()
        let pathA = (tmpDir as NSString).appendingPathComponent("wp_sync_devA_\(UUID().uuidString).sqlite")
        let pathB = (tmpDir as NSString).appendingPathComponent("wp_sync_devB_\(UUID().uuidString).sqlite")
        defer {
            for p in [pathA, pathB] {
                try? FileManager.default.removeItem(atPath: p)
                try? FileManager.default.removeItem(atPath: p + "-wal")
                try? FileManager.default.removeItem(atPath: p + "-shm")
            }
        }

        // Device A and Device B have different PINs → different cipher keys.
        let saltA = Data(repeating: 0xAA, count: 32)
        let saltB = Data(repeating: 0xBB, count: 32)
        let keyA = CipherKeyManager.deriveKey(pin: "1111", salt: saltA)
        let keyB = CipherKeyManager.deriveKey(pin: "2222", salt: saltB)
        #expect(keyA != keyB, "Prerequisite: keys must differ")

        // Open two independent encrypted pools (simulating two devices).
        let poolA = try AppDatabase.makeEncryptedPool(path: pathA, keyHex: keyA)
        let poolB = try AppDatabase.makeEncryptedPool(path: pathB, keyHex: keyB)
        defer {
            try? poolA.close()
            try? poolB.close()
        }

        // Create a minimal shared table in both databases.
        for pool in [poolA, poolB] {
            try pool.write { db in
                try db.execute(sql: """
                    CREATE TABLE IF NOT EXISTS _sync_test (
                        id    TEXT PRIMARY KEY,
                        value TEXT NOT NULL
                    )
                """)
            }
        }

        // Device A writes a record.
        let recordId   = UUID().uuidString
        let recordValue = "sync_payload_from_A"
        try poolA.write { db in
            try db.execute(
                sql: "INSERT INTO _sync_test (id, value) VALUES (?, ?)",
                arguments: [recordId, recordValue]
            )
        }

        // Simulate sync: Device A reads the row and encodes it as JSON (application layer).
        let syncPayload: Data = try poolA.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT * FROM _sync_test WHERE id = ?",
                                      arguments: [recordId])!
            let dict: [String: String] = ["id": row["id"], "value": row["value"]]
            return try JSONSerialization.data(withJSONObject: dict)
        }

        // Simulate Multipeer transport: syncPayload travels as bytes.
        // Device B receives, decodes, and writes into its own (differently-keyed) DB.
        guard let decoded = try JSONSerialization.jsonObject(with: syncPayload) as? [String: String],
              let syncId = decoded["id"],
              let syncValue = decoded["value"] else {
            Issue.record("Failed to decode sync payload as [String: String]")
            return
        }
        try poolB.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO _sync_test (id, value) VALUES (?, ?)",
                arguments: [syncId, syncValue]
            )
        }

        // Device B reads back — must match what Device A wrote.
        let readBack: String? = try poolB.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT value FROM _sync_test WHERE id = ?",
                                      arguments: [recordId])
            return row?["value"]
        }

        #expect(readBack == recordValue,
                "Sync record from Device A must be readable on Device B via its own cipher key")

        // Extra safety: Device B's DB cannot be opened with Device A's key.
        var wrongKeyFailed = false
        do {
            let wrongPool = try AppDatabase.makeEncryptedPool(path: pathB, keyHex: keyA)
            try wrongPool.read { db in
                _ = try Row.fetchOne(db, sql: "SELECT 1 FROM _sync_test LIMIT 1")
            }
            try wrongPool.close()
        } catch {
            wrongKeyFailed = true
        }
        #expect(wrongKeyFailed, "Device B's DB must not open with Device A's key")
    }
}
#endif
