#if canImport(MultipeerConnectivity)
import Testing
import Foundation
import GRDB
@testable import WiredPartCore

@Suite("MultipeerManager Tests")
struct MultipeerTests {

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
