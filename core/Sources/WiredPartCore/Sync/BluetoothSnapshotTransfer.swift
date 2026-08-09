import Foundation
import CryptoKit
import GRDB

struct SnapshotBegin: Codable, Equatable, Sendable {
    let transferId: String
    let authorizationToken: String
}

struct SnapshotBatch: Codable, Sendable {
    let transferId: String
    let sequence: Int
    let changes: [IncomingChange]
}

struct SnapshotStored: Codable, Equatable, Sendable {
    let transferId: String
    let sequence: Int
}

struct SnapshotComplete: Codable, Equatable, Sendable {
    let transferId: String
    let finalSequence: Int
}

enum SnapshotStagingError: LocalizedError, Sendable {
    case invalidSequence
    case unauthorizedHost
    case unknownTransfer
    case mixedTransfer
    case mixedBatch
    case duplicateMismatch
    case sequenceGap
    case disallowedTable
    case disallowedOperation

    var errorDescription: String? {
        switch self {
        case .invalidSequence: return "Bluetooth snapshot sequence is invalid. Retry the sync."
        case .unauthorizedHost: return "Bluetooth snapshot host is not authorized. Pair it again."
        case .unknownTransfer: return "Bluetooth snapshot transfer is unknown. Retry the sync."
        case .mixedTransfer: return "Bluetooth snapshot mixed transfer identifiers. Retry the sync."
        case .mixedBatch: return "Bluetooth snapshot batch mixed business tables. Retry the sync."
        case .duplicateMismatch: return "Bluetooth snapshot duplicate data did not match. Retry the sync."
        case .sequenceGap: return "Bluetooth snapshot has a sequence gap. Retry the sync."
        case .disallowedTable: return "Bluetooth snapshot contains a disallowed table. Retry the sync."
        case .disallowedOperation: return "Bluetooth snapshot contains a disallowed operation. Retry the sync."
        }
    }
}

struct SnapshotCompletionReceipt: Sendable {
    let authorizationToken: String
    let result: MergeResult
    let wasAlreadyApplied: Bool
}

enum BluetoothSnapshotStaging {
    static func digest(_ payload: Data) -> String {
        SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    static func authorize(
        db: AppDatabase,
        hostDeviceId: String,
        begin: SnapshotBegin,
        allowNewTransfer: Bool
    ) throws {
        guard !begin.transferId.isEmpty, !begin.authorizationToken.isEmpty else {
            throw SnapshotStagingError.unauthorizedHost
        }
        try db.writer.write { conn in
            if let row = try Row.fetchOne(
                conn,
                sql: "SELECT host_device_id, authorization_token FROM _snapshot_transfers WHERE transfer_id = ?",
                arguments: [begin.transferId]
            ) {
                let storedHost: String = row["host_device_id"]
                let storedToken: String = row["authorization_token"]
                guard storedHost == hostDeviceId, storedToken == begin.authorizationToken else {
                    throw SnapshotStagingError.unauthorizedHost
                }
                return
            }
            guard allowNewTransfer else { throw SnapshotStagingError.unknownTransfer }
            try conn.execute(
                sql: "INSERT INTO _snapshot_transfers (transfer_id, host_device_id, authorization_token, state) VALUES (?, ?, ?, 'staging')",
                arguments: [begin.transferId, hostDeviceId, begin.authorizationToken]
            )
        }
    }

    /// Commits the exact encoded changes before returning, making a subsequent
    /// `snapshotStored` acknowledgement a durable promise.
    static func stage(db: AppDatabase, hostDeviceId: String, batch: SnapshotBatch) throws {
        guard batch.sequence >= 0 else { throw SnapshotStagingError.invalidSequence }
        guard !batch.changes.isEmpty,
              Set(batch.changes.map { $0.tableName.lowercased() }).count == 1 else {
            throw SnapshotStagingError.mixedBatch
        }
        let payload = try JSONEncoder().encode(batch.changes)
        let payloadDigest = digest(payload)
        try db.writer.write { conn in
            guard let state = try String.fetchOne(
                conn,
                sql: "SELECT state FROM _snapshot_transfers WHERE transfer_id = ? AND host_device_id = ?",
                arguments: [batch.transferId, hostDeviceId]
            ) else { throw SnapshotStagingError.unknownTransfer }
            guard state == "staging" else { throw SnapshotStagingError.unknownTransfer }
            if let row = try Row.fetchOne(
                conn,
                sql: "SELECT host_device_id, digest FROM _snapshot_staging WHERE transfer_id = ? AND sequence = ?",
                arguments: [batch.transferId, batch.sequence]
            ) {
                let storedHost: String = row["host_device_id"]
                let storedDigest: String = row["digest"]
                guard storedHost == hostDeviceId else { throw SnapshotStagingError.unauthorizedHost }
                guard storedDigest == payloadDigest else { throw SnapshotStagingError.duplicateMismatch }
                return
            }
            if let existingHost = try String.fetchOne(
                conn,
                sql: "SELECT host_device_id FROM _snapshot_staging WHERE transfer_id = ? LIMIT 1",
                arguments: [batch.transferId]
            ), existingHost != hostDeviceId {
                throw SnapshotStagingError.unauthorizedHost
            }
            try conn.execute(
                sql: "INSERT INTO _snapshot_staging (transfer_id, sequence, host_device_id, payload, digest) VALUES (?, ?, ?, ?, ?)",
                arguments: [batch.transferId, batch.sequence, hostDeviceId, payload, payloadDigest]
            )
        }
    }

    /// Reads and validates the whole transfer, then applies and deletes it in
    /// the resolver's single writer transaction.
    static func complete(
        db: AppDatabase,
        hostDeviceId: String,
        completion: SnapshotComplete
    ) throws -> SnapshotCompletionReceipt {
        guard completion.finalSequence >= -1 else { throw SnapshotStagingError.invalidSequence }
        return try ConflictResolver.resolveAndApplyStagedSnapshotAtomically(
            db: db,
            transferId: completion.transferId,
            hostDeviceId: hostDeviceId,
            finalSequence: completion.finalSequence
        )
    }
}

/// A page read from one business table during a Bluetooth initial snapshot.
/// `sourceRowCount` drives paging even when device-scoped rows are filtered out.
struct BluetoothSnapshotPage: Sendable {
    let changes: [IncomingChange]
    let sourceRowCount: Int
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

    /// Staged protocol sender. Exactly one payload can be awaiting durable
    /// acknowledgement because the next page is not read until `isStored` is true.
    static func runStaged(
        transferId: String,
        batchSize: Int = 200,
        maxAttempts: Int = defaultMaxSendAttempts,
        sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        listTables: () async throws -> [String],
        readPage: (_ table: String, _ limit: Int, _ offset: Int) async throws -> BluetoothSnapshotPage,
        sendBatch: (_ batch: SnapshotBatch) throws -> Bool,
        isStored: (_ sequence: Int) async -> Bool
    ) async throws -> (rows: Int, finalSequence: Int) {
        var sequence = 0
        var rows = 0
        for table in try await listTables() where !table.hasPrefix("_") && ConflictResolver.isAllowedTable(table) {
            var offset = 0
            while true {
                let page = try await readPage(table, batchSize, offset)
                guard page.sourceRowCount > 0 else { break }
                if !page.changes.isEmpty {
                    let batch = SnapshotBatch(transferId: transferId, sequence: sequence, changes: page.changes)
                    var acknowledged = false
                    for attempt in 1...maxAttempts {
                        if try sendBatch(batch) {
                            // Deterministic tests inject a zero-cost sleep; production
                            // gets a bounded acknowledgement interval per attempt.
                            for _ in 0..<10 {
                                if await isStored(sequence) { acknowledged = true; break }
                                await sleep(.milliseconds(100))
                            }
                        }
                        if acknowledged { break }
                        if attempt < maxAttempts { await sleep(.milliseconds(100 * attempt)) }
                    }
                    guard acknowledged else {
                        throw BluetoothSnapshotTransferError.batchSendFailed(table: table, offset: offset)
                    }
                    rows += page.changes.count
                    sequence += 1
                }
                if page.sourceRowCount < batchSize { break }
                offset += batchSize
            }
        }
        return (rows, sequence - 1)
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
