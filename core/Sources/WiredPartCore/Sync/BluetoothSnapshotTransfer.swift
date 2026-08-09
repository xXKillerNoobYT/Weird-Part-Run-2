import Foundation

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
