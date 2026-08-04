import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// Guards for the two security findings from the 2026-08-03 sync audit:
/// unauthenticated peer writes, and revocation that never propagated.
@Suite("Sync trust and revocation")
struct SyncTrustAndRevocationTests {

    private func seedPeer(
        _ db: AppDatabase, id: String, trusted: Bool, deactivated: Bool = false
    ) throws {
        try db.writer.write { dbc in
            try dbc.execute(sql: """
                INSERT OR REPLACE INTO _device_registry
                    (device_id, device_name, platform, is_trusted, is_deactivated)
                VALUES (?, 'Peer', 'ios', ?, ?)
                """, arguments: [id, trusted ? 1 : 0, deactivated ? 1 : 0])
        }
    }

    private func registryFlags(_ db: AppDatabase, _ id: String) throws -> (trusted: Int, deactivated: Int) {
        try db.writer.read { dbc in
            let row = try Row.fetchOne(
                dbc,
                sql: "SELECT is_trusted, is_deactivated FROM _device_registry WHERE device_id = ?",
                arguments: [id]
            )
            return (row?["is_trusted"] ?? -1, row?["is_deactivated"] ?? -1)
        }
    }

    private func registryChange(deviceId: String, deactivated: Int? = nil, trusted: Int? = nil) -> IncomingChange {
        var fields: [String] = ["\"device_id\":\"\(deviceId)\""]
        if let deactivated { fields.append("\"is_deactivated\":\(deactivated)") }
        if let trusted { fields.append("\"is_trusted\":\(trusted)") }
        return IncomingChange(
            deviceId: "peer-sender",
            tableName: "_device_registry",
            recordId: "0",
            operation: "UPDATE",
            changedFields: "{\(fields.joined(separator: ","))}",
            timestamp: CoreFormatters.nowISO()
        )
    }

    @Test("Revocation propagates: an incoming deactivation applies to the right row")
    func revocationApplies() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        try seedPeer(db, id: "stolen-device", trusted: true)
        let result = try ConflictResolver.resolveAndApplyChanges(
            db: db, changes: [registryChange(deviceId: "stolen-device", deactivated: 1)]
        )
        #expect(result.errors == 0, "device_registry change must not error out")
        #expect(try registryFlags(db, "stolen-device").deactivated == 1)
    }

    @Test("Revocation is MONOTONIC: a revoked device cannot re-enable itself over sync")
    func revocationIsMonotonic() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        try seedPeer(db, id: "stolen-device", trusted: false, deactivated: true)
        // The stolen device pushes "I'm fine again".
        _ = try ConflictResolver.resolveAndApplyChanges(
            db: db, changes: [registryChange(deviceId: "stolen-device", deactivated: 0, trusted: 1)]
        )
        let flags = try registryFlags(db, "stolen-device")
        #expect(flags.deactivated == 1, "sync must never un-deactivate a device")
        #expect(flags.trusted == 0, "sync must never re-trust a device")
    }

    @Test("Admin revoke emits a replicable change-log entry")
    func adminRevokeIsReplicated() throws {
        let env = try E2ETestHelpers.setUp()
        try seedPeer(env.db, id: "kicked-device", trusted: true)
        let rowid = try env.db.writer.read { dbc in
            try Int64.fetchOne(dbc, sql: "SELECT rowid FROM _device_registry WHERE device_id = ?",
                               arguments: ["kicked-device"])
        }
        try env.auth.deactivateSession(sessionId: String(rowid ?? 0))
        let logged = try env.db.writer.read { dbc in
            try String.fetchOne(dbc, sql: """
                SELECT changed_fields FROM _change_log
                WHERE table_name = '_device_registry' ORDER BY id DESC LIMIT 1
                """)
        }
        #expect(logged?.contains("kicked-device") == true, "revocation must be logged for sync")
        #expect(logged?.contains("\"is_deactivated\":1") == true)
    }

    @Test("Untrusted peers cannot write company data; trusted peers can")
    func writeGateHoldsBothWays() async throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let pm = PeerManager(db: db)
        try seedPeer(db, id: "trusted-peer", trusted: true)
        try seedPeer(db, id: "revoked-peer", trusted: true, deactivated: true)
        #expect(await pm.isTrustedWritePeer("trusted-peer") == true)
        #expect(await pm.isTrustedWritePeer("revoked-peer") == false)
        #expect(await pm.isTrustedWritePeer("never-paired-peer") == false)
    }
}
