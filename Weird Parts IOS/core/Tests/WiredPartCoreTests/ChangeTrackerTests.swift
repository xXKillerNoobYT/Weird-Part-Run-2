import Testing
import GRDB
@testable import WiredPartCore

@Suite("ChangeTracker Tests")
struct ChangeTrackerTests {

    private func freshDB() throws -> AppDatabase {
        try AppDatabase.openInMemoryDatabase()
    }

    @Test("trackChange inserts a change log entry")
    func testTrackChangeInserts() throws {
        let db = try freshDB()

        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: 42,
            operation: .insert,
            changedFields: ["display_name": "Alice", "email": "alice@test.com"],
            deviceId: "test-device-1"
        )

        let entries = try ChangeTracker.getPendingChanges(db: db)
        #expect(entries.count == 1)
        #expect(entries[0].tableName == "users")
        #expect(entries[0].recordId == 42)
        #expect(entries[0].operation == "INSERT")
        #expect(entries[0].deviceId == "test-device-1")
        #expect(entries[0].synced == 0)
    }

    @Test("trackChange records old values for UPDATE")
    func testTrackChangeOldValues() throws {
        let db = try freshDB()

        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: 1,
            operation: .update,
            changedFields: ["email": "new@test.com"],
            oldValues: ["email": "old@test.com"],
            deviceId: "test-device-1"
        )

        let entries = try ChangeTracker.getPendingChanges(db: db)
        #expect(entries.count == 1)
        #expect(entries[0].operation == "UPDATE")
        #expect(entries[0].changedFields != nil)
        #expect(entries[0].oldValues != nil)
        #expect(entries[0].changedFields!.contains("new@test.com"))
        #expect(entries[0].oldValues!.contains("old@test.com"))
    }

    @Test("getPendingChangeCount returns correct count")
    func testPendingCount() throws {
        let db = try freshDB()

        for i in 1...3 {
            try ChangeTracker.trackChange(
                db: db,
                tableName: "parts",
                recordId: Int64(i),
                operation: .insert,
                deviceId: "test-device"
            )
        }

        let count = try ChangeTracker.getPendingChangeCount(db: db)
        #expect(count == 3)
    }

    @Test("markSynced marks entries as synced")
    func testMarkSynced() throws {
        let db = try freshDB()

        for i in 1...3 {
            try ChangeTracker.trackChange(
                db: db,
                tableName: "parts",
                recordId: Int64(i),
                operation: .insert,
                deviceId: "test-device"
            )
        }

        let entries = try ChangeTracker.getPendingChanges(db: db)
        let ids = entries.compactMap { $0.id }
        #expect(ids.count == 3)

        try ChangeTracker.markSynced(db: db, ids: Array(ids.prefix(2)), batchId: "batch-001")

        let remaining = try ChangeTracker.getPendingChangeCount(db: db)
        #expect(remaining == 1)
    }

    @Test("markSynced with empty ids is a no-op")
    func testMarkSyncedEmpty() throws {
        let db = try freshDB()
        try ChangeTracker.markSynced(db: db, ids: [], batchId: "batch-empty")
    }

    @Test("getMaxSequence returns 0 on empty log")
    func testMaxSequenceEmpty() throws {
        let db = try freshDB()
        let maxSeq = try ChangeTracker.getMaxSequence(db: db)
        #expect(maxSeq == 0)
    }

    @Test("getVectorClock returns empty dict initially")
    func testVectorClockEmpty() throws {
        let db = try freshDB()
        let vc = try ChangeTracker.getVectorClock(db: db, deviceId: "test-device")
        #expect(vc.isEmpty)
    }

    @Test("updateVectorClock stores and retrieves peer sequence")
    func testUpdateVectorClock() throws {
        let db = try freshDB()
        let deviceId = "my-device"
        let peerId = "peer-device"

        try ChangeTracker.updateVectorClock(db: db, peerId: peerId, lastSequence: 42, deviceId: deviceId)

        let vc = try ChangeTracker.getVectorClock(db: db, deviceId: deviceId)
        #expect(vc[peerId] == 42)
    }

    @Test("updateVectorClock uses MAX for existing peer")
    func testVectorClockMax() throws {
        let db = try freshDB()
        let deviceId = "my-device"
        let peerId = "peer-device"

        try ChangeTracker.updateVectorClock(db: db, peerId: peerId, lastSequence: 42, deviceId: deviceId)
        try ChangeTracker.updateVectorClock(db: db, peerId: peerId, lastSequence: 30, deviceId: deviceId)

        let vc = try ChangeTracker.getVectorClock(db: db, deviceId: deviceId)
        #expect(vc[peerId] == 42)
    }

    @Test("registerPeerDevice creates and updates device")
    func testRegisterPeerDevice() throws {
        let db = try freshDB()

        try ChangeTracker.registerPeerDevice(db: db, peerId: "peer-1", peerName: "iPad Pro", platform: "iOS")

        let device = try db.writer.read { dbConn in
            try DeviceRegistryEntry.fetchOne(
                dbConn,
                sql: "SELECT * FROM _device_registry WHERE device_id = ?",
                arguments: ["peer-1"]
            )
        }
        #expect(device != nil)
        #expect(device?.deviceName == "iPad Pro")
        #expect(device?.platform == "iOS")
        #expect(device?.isTrusted == 1)

        // Update the same device
        try ChangeTracker.registerPeerDevice(db: db, peerId: "peer-1", peerName: "iPad Pro (updated)")

        let updated = try db.writer.read { dbConn in
            try DeviceRegistryEntry.fetchOne(
                dbConn,
                sql: "SELECT * FROM _device_registry WHERE device_id = ?",
                arguments: ["peer-1"]
            )
        }
        #expect(updated?.deviceName == "iPad Pro (updated)")
    }

    @Test("updatePeerSyncTime updates timestamps")
    func testUpdatePeerSyncTime() throws {
        let db = try freshDB()

        try ChangeTracker.registerPeerDevice(db: db, peerId: "peer-1", peerName: "Test Device")
        try ChangeTracker.updatePeerSyncTime(db: db, peerId: "peer-1")

        let device = try db.writer.read { dbConn in
            try DeviceRegistryEntry.fetchOne(
                dbConn,
                sql: "SELECT * FROM _device_registry WHERE device_id = ?",
                arguments: ["peer-1"]
            )
        }
        #expect(device != nil)
        #expect(device?.lastSyncAt != nil)
    }
}
