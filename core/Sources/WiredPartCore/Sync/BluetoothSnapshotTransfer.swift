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
    static func run(
        batchSize: Int = 200,
        listTables: () async throws -> [String],
        readPage: (_ table: String, _ limit: Int, _ offset: Int) async throws -> BluetoothSnapshotPage,
        encode: (_ changes: [IncomingChange]) throws -> Data,
        send: (_ data: Data) -> Bool
    ) async throws -> Int {
        precondition(batchSize > 0)

        let tables = try await listTables()
        var totalSent = 0

        for table in tables where !table.hasPrefix("_") && ConflictResolver.isAllowedTable(table) {
            var offset = 0
            while true {
                let page = try await readPage(table, batchSize, offset)
                guard page.sourceRowCount > 0 else { break }

                if !page.changes.isEmpty {
                    let payload = try encode(page.changes)
                    guard send(payload) else {
                        throw BluetoothSnapshotTransferError.batchSendFailed(table: table, offset: offset)
                    }
                    totalSent += page.changes.count
                }

                if page.sourceRowCount < batchSize { break }
                offset += batchSize
            }
        }

        return totalSent
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
