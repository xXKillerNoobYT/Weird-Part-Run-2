import Foundation
import GRDB

/// A page read from one business table during a Bluetooth initial snapshot.
/// `sourceRowCount` drives paging even when device-scoped rows are filtered out.
struct BluetoothSnapshotPage: Sendable {
    let changes: [IncomingChange]
    let sourceRowCount: Int
}

struct BluetoothSnapshotBegin: Codable, Sendable, Equatable {
    let transferID: String
}

struct BluetoothSnapshotBatch: Codable, Sendable {
    let transferID: String
    let sequence: Int
    let changes: [IncomingChange]
}

struct BluetoothSnapshotStored: Codable, Sendable, Equatable {
    let transferID: String
    let sequence: Int
}

struct BluetoothSnapshotComplete: Codable, Sendable, Equatable {
    let transferID: String
    let batchCount: Int
}

/// Durable receiver-side journal for the staged snapshot protocol. Payload bytes
/// are retained verbatim so a repeated sequence can be distinguished from a
/// conflicting frame without relying on JSON re-encoding stability.
enum BluetoothSnapshotStaging {
    static func begin(
        db: AppDatabase,
        peerDeviceID: String,
        transferID: String,
        authorizationToken: String? = nil
    ) throws {
        guard !transferID.isEmpty else { throw MultipeerSnapshotError.malformedEnvelope }
        try db.writer.write { dbConn in
            let active = try String.fetchOne(
                dbConn,
                sql: "SELECT transfer_id FROM _bluetooth_snapshot_transfers WHERE peer_device_id = ?",
                arguments: [peerDeviceID]
            )
            if active == transferID { return }
            try dbConn.execute(
                sql: "DELETE FROM _bluetooth_snapshot_transfers WHERE peer_device_id = ?",
                arguments: [peerDeviceID]
            )
            try dbConn.execute(
                sql: "INSERT INTO _bluetooth_snapshot_transfers (peer_device_id, transfer_id, authorization_token) VALUES (?, ?, ?)",
                arguments: [peerDeviceID, transferID, authorizationToken]
            )
        }
    }

    /// Returns the pairing-issued capability only when the durable journal still
    /// belongs to this exact peer and transfer. Callers must also authenticate the
    /// peer through the normal trusted-device path before recovering a transfer.
    static func recoveryAuthorizationToken(
        db: AppDatabase,
        peerDeviceID: String,
        transferID: String
    ) throws -> String? {
        try db.writer.read { dbConn in
            try String.fetchOne(
                dbConn,
                sql: """
                    SELECT authorization_token
                    FROM _bluetooth_snapshot_transfers
                    WHERE peer_device_id = ? AND transfer_id = ?
                    """,
                arguments: [peerDeviceID, transferID]
            )
        }
    }

    /// Returns true for a newly stored frame and false for an identical retry.
    static func stage(
        db: AppDatabase,
        peerDeviceID: String,
        transferID: String,
        sequence: Int,
        payload: Data
    ) throws -> Bool {
        guard sequence >= 0 else { throw MultipeerSnapshotError.invalidSequence }
        return try db.writer.write { dbConn in
            let active = try String.fetchOne(
                dbConn,
                sql: "SELECT transfer_id FROM _bluetooth_snapshot_transfers WHERE peer_device_id = ?",
                arguments: [peerDeviceID]
            )
            guard active == transferID else { throw MultipeerSnapshotError.transferMismatch }
            if let stored = try Data.fetchOne(
                dbConn,
                sql: "SELECT payload FROM _bluetooth_snapshot_batches WHERE transfer_id = ? AND sequence = ?",
                arguments: [transferID, sequence]
            ) {
                guard stored == payload else { throw MultipeerSnapshotError.duplicateFrameMismatch }
                return false
            }
            try dbConn.execute(
                sql: "INSERT INTO _bluetooth_snapshot_batches (transfer_id, sequence, payload) VALUES (?, ?, ?)",
                arguments: [transferID, sequence, payload]
            )
            return true
        }
    }

    /// Discards only the active private journal for this joiner peer. Deleting
    /// the transfer row cascades its frames and never touches business tables.
    /// Call this only after `complete` has committed or rolled back; `complete`
    /// owns cleanup while its transaction is still active.
    static func discard(db: AppDatabase, peerDeviceID: String) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "DELETE FROM _bluetooth_snapshot_transfers WHERE peer_device_id = ?",
                arguments: [peerDeviceID]
            )
        }
    }

    /// Decodes and applies one durable frame at a time inside a single SQLite
    /// transaction. The cursor and per-frame decoded array are bounded by the
    /// sender's acknowledged frame size; the complete snapshot is never materialized
    /// as one `[IncomingChange]` array.
    ///
    /// `maximumDecodedChangesPerBatch` is an internal regression-test seam. A test
    /// can set it below the snapshot aggregate to prove the completion path observes
    /// only bounded frames, while production uses the frame's natural size.
    static func complete(
        db: AppDatabase,
        peerDeviceID: String,
        transferID: String,
        batchCount: Int,
        localDeviceID: String,
        maximumDecodedChangesPerBatch: Int = .max
    ) throws -> Int {
        guard batchCount >= 0, maximumDecodedChangesPerBatch > 0 else {
            throw MultipeerSnapshotError.invalidSequence
        }
        return try db.writer.write { dbConn in
            let active = try String.fetchOne(
                dbConn,
                sql: "SELECT transfer_id FROM _bluetooth_snapshot_transfers WHERE peer_device_id = ?",
                arguments: [peerDeviceID]
            )
            guard active == transferID else { throw MultipeerSnapshotError.transferMismatch }

            // The primary key is (transfer_id, sequence), so count + min/max prove
            // the exact 0...(batchCount - 1) sequence without materializing rows.
            let stagedCount = try Int.fetchOne(
                dbConn,
                sql: "SELECT COUNT(*) FROM _bluetooth_snapshot_batches WHERE transfer_id = ?",
                arguments: [transferID]
            ) ?? 0
            guard stagedCount == batchCount else {
                throw MultipeerSnapshotError.nonContiguousSequence
            }
            if batchCount > 0 {
                let bounds = try Row.fetchOne(
                    dbConn,
                    sql: "SELECT MIN(sequence) AS first_sequence, MAX(sequence) AS last_sequence FROM _bluetooth_snapshot_batches WHERE transfer_id = ?",
                    arguments: [transferID]
                )
                let first: Int? = bounds?["first_sequence"]
                let last: Int? = bounds?["last_sequence"]
                guard first == 0, last == batchCount - 1 else {
                    throw MultipeerSnapshotError.nonContiguousSequence
                }
            }

            var applied = 0
            let cursor = try Row.fetchCursor(
                dbConn,
                sql: "SELECT payload FROM _bluetooth_snapshot_batches WHERE transfer_id = ? ORDER BY sequence",
                arguments: [transferID]
            )
            while let row = try cursor.next() {
                let payload: Data = row["payload"]
                guard let batch = try? JSONDecoder().decode(BluetoothSnapshotBatch.self, from: payload),
                      batch.transferID == transferID,
                      batch.changes.count <= maximumDecodedChangesPerBatch else {
                    throw MultipeerSnapshotError.malformedChanges
                }
                let result = try ConflictResolver.resolveAndApplyChangesAtomically(
                    db: dbConn, changes: batch.changes, localDeviceId: localDeviceID
                )
                applied += result.applied
            }

            // This delete is part of the same transaction. Any decoding or apply
            // failure rolls back both business writes and this cleanup, retaining
            // the durable journal for the caller's failure/retry handling.
            try dbConn.execute(
                sql: "DELETE FROM _bluetooth_snapshot_transfers WHERE peer_device_id = ?",
                arguments: [peerDeviceID]
            )
            return applied
        }
    }
}

enum BluetoothSnapshotTransferError: LocalizedError, Sendable {
    case batchSendFailed(table: String, offset: Int)
    case completionSendFailed

    var errorDescription: String? {
        switch self {
        case .batchSendFailed(let table, let offset):
            return "Bluetooth snapshot send failed for \(table) at offset \(offset). Retry the sync."
        case .completionSendFailed:
            return "Bluetooth snapshot completion could not be delivered. Retry the sync."
        }
    }
}

/// Deterministic host-side snapshot pipeline. All fallible operations are injected so
/// table enumeration, page reads, encoding, and transport failures remain testable.
enum BluetoothSnapshotTransfer {
    /// Default pacing between batches. Multipeer's `send(_:toPeers:with:.reliable)`
    /// buffers internally and reports no backpressure, so an unpaced loop hands it
    /// batches faster than the radio drains them until the session is torn down.
    static let defaultInterBatchPause: Duration = .milliseconds(15)

    /// How many times one batch may be re-attempted while the session is briefly
    /// not connected. Multipeer flaps under load; a single transient `false` must
    /// not destroy a transfer that is otherwise progressing.
    static let defaultMaxSendAttempts = 6

    /// Sequenced variant used by the durable protocol. The next page is not
    /// read until `sendAndAwaitStored` confirms the current page is durable.
    static func runStaged(
        transferID: String,
        batchSize: Int = 200,
        listTables: () async throws -> [String],
        readPage: (_ table: String, _ limit: Int, _ offset: Int) async throws -> BluetoothSnapshotPage,
        sendAndAwaitStored: (_ batch: BluetoothSnapshotBatch) async throws -> Void
    ) async throws -> (rows: Int, batches: Int) {
        precondition(batchSize > 0)
        var rows = 0
        var sequence = 0
        for table in try await listTables() where !table.hasPrefix("_") && ConflictResolver.isAllowedTable(table) {
            var offset = 0
            while true {
                let page = try await readPage(table, batchSize, offset)
                guard page.sourceRowCount > 0 else { break }
                if !page.changes.isEmpty {
                    try await sendAndAwaitStored(BluetoothSnapshotBatch(
                        transferID: transferID, sequence: sequence, changes: page.changes
                    ))
                    rows += page.changes.count
                    sequence += 1
                }
                if page.sourceRowCount < batchSize { break }
                offset += batchSize
            }
        }
        return (rows, sequence)
    }

    /// Host-side initial snapshot, paced and retried.
    ///
    /// **Why the pacing and retry exist (#1580 field failure, build 62).**
    /// The Mac showed `iPhone connected` and then `Sync with iPhone failed`,
    /// while the joiner sat at roughly a quarter of "Downloading data over
    /// Bluetooth…". The loop used to read a page, `send`, and immediately read
    /// the next — no pacing, no acknowledgement, no backpressure — flooding
    /// MCSession as fast as SQLite could be read. The session gets torn down
    /// under that load, the peer reverts to `.found`, `MultipeerManager.send`
    /// then fails its `state == .connected` guard and returns `false`, and the
    /// whole company transfer died on the first such batch.
    ///
    /// Two changes, both aimed at that chain:
    /// 1. **Pace** — a short pause between batches lets the radio drain instead
    ///    of being handed the next payload immediately.
    /// 2. **Retry** — a batch that fails to send is re-attempted with backoff
    ///    rather than aborting, so a momentary flap costs a few hundred
    ///    milliseconds instead of the entire snapshot.
    ///
    /// Retries are bounded: a genuinely dead session still fails, and it fails
    /// with the table and offset it died on.
    static func run(
        batchSize: Int = 200,
        maxSendAttempts: Int = defaultMaxSendAttempts,
        interBatchPause: Duration = defaultInterBatchPause,
        sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        listTables: () async throws -> [String],
        readPage: (_ table: String, _ limit: Int, _ offset: Int) async throws -> BluetoothSnapshotPage,
        encode: (_ changes: [IncomingChange]) throws -> Data,
        send: (_ data: Data) -> Bool
    ) async throws -> Int {
        precondition(batchSize > 0)
        precondition(maxSendAttempts > 0)

        let tables = try await listTables()
        var totalSent = 0

        for table in tables where !table.hasPrefix("_") && ConflictResolver.isAllowedTable(table) {
            var offset = 0
            while true {
                let page = try await readPage(table, batchSize, offset)
                guard page.sourceRowCount > 0 else { break }

                if !page.changes.isEmpty {
                    let payload = try encode(page.changes)
                    try await sendWithRetry(
                        payload,
                        table: table,
                        offset: offset,
                        maxSendAttempts: maxSendAttempts,
                        sleep: sleep,
                        send: send
                    )
                    totalSent += page.changes.count

                    // Let the transport drain before queueing the next batch.
                    if interBatchPause > .zero {
                        await sleep(interBatchPause)
                    }
                }

                if page.sourceRowCount < batchSize { break }
                offset += batchSize
            }
        }

        return totalSent
    }

    /// One batch, re-attempted with linear backoff while the session recovers.
    private static func sendWithRetry(
        _ payload: Data,
        table: String,
        offset: Int,
        maxSendAttempts: Int,
        sleep: @Sendable (Duration) async -> Void,
        send: (_ data: Data) -> Bool
    ) async throws {
        for attempt in 1...maxSendAttempts {
            if send(payload) { return }
            guard attempt < maxSendAttempts else { break }
            // Linear backoff: 100ms, 200ms, 300ms… Enough for a Multipeer flap to
            // resolve, short enough that a genuinely dead session fails quickly.
            await sleep(.milliseconds(100 * attempt))
        }
        throw BluetoothSnapshotTransferError.batchSendFailed(table: table, offset: offset)
    }
}

struct FullSyncCompletion: Codable, Sendable {
    let succeeded: Bool
    let error: String?

    static let success = FullSyncCompletion(succeeded: true, error: nil)

    static func failure(_ error: Error) -> FullSyncCompletion {
        FullSyncCompletion(succeeded: false, error: error.localizedDescription)
    }
}

struct FullSyncRequest: Codable, Sendable, Equatable {
    let authorizationToken: String
}

enum BluetoothSnapshotAuthorization {
    static func isAuthorized(
        trustedDevice: Bool,
        providedToken: String,
        expectedToken: String?
    ) -> Bool {
        trustedDevice
            && !providedToken.isEmpty
            && providedToken == expectedToken
    }
}

enum MultipeerSnapshotError: LocalizedError, Sendable {
    case malformedEnvelope
    case malformedChanges
    case rowEncodingFailed(table: String)
    case missingRecordID(table: String)
    case invalidRecordData(table: String, recordID: String)
    case batchApplyFailed(errorCount: Int)
    case unauthorizedPeer
    case remoteFailure(String)
    case transferMismatch
    case invalidSequence
    case nonContiguousSequence
    case duplicateFrameMismatch

    var errorDescription: String? {
        switch self {
        case .malformedEnvelope:
            return "Received an invalid Bluetooth sync message. Retry the sync."
        case .malformedChanges:
            return "Received an invalid Bluetooth snapshot batch. Retry the sync."
        case .rowEncodingFailed(let table):
            return "Bluetooth snapshot could not encode a row from \(table). Retry the sync."
        case .missingRecordID(let table):
            return "Bluetooth snapshot found a row without a usable id in \(table). Retry the sync."
        case .invalidRecordData(let table, let recordID):
            return "Bluetooth snapshot received invalid row data for \(table) record \(recordID). Retry the sync."
        case .batchApplyFailed(let errorCount):
            return "Bluetooth snapshot could not apply \(errorCount) change(s). Retry the sync."
        case .unauthorizedPeer:
            return "The Bluetooth peer is not a trusted company device. Pair it before requesting a snapshot."
        case .remoteFailure(let message):
            return message.isEmpty ? "The host could not complete the Bluetooth snapshot. Retry the sync." : message
        case .transferMismatch: return "Bluetooth snapshot transfer identity did not match. Retry the sync."
        case .invalidSequence: return "Bluetooth snapshot batch sequence was invalid. Retry the sync."
        case .nonContiguousSequence: return "Bluetooth snapshot was incomplete. Retry the sync."
        case .duplicateFrameMismatch: return "Bluetooth snapshot repeated a batch with different data. Retry the sync."
        }
    }
}

enum MultipeerMessageOutcome: Equatable, Sendable {
    case changesApplied(Int)
    case pairRequest
    case pairResponse
    case fullSyncRequest
    case fullSyncCompleted
    case ignored
}
