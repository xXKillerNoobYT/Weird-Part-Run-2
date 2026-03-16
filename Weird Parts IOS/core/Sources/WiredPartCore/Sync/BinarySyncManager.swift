import Foundation
import GRDB
import CryptoKit

/// Type alias to avoid name collision with CryptoKit.SHA256
private typealias CryptoKitSHA256 = CryptoKit.SHA256

// MARK: - Binary Sync Manager

/// Manages chunked binary data transfer between devices.
///
/// Binary data (scanned documents, part photos) is transferred separately
/// from database records to prevent blocking critical sync operations.
///
/// Protocol:
/// - 16KB frames: 32-byte header + up to 16,352 bytes payload + 4-byte CRC32
/// - `WPBT` magic bytes for frame identification
/// - Transfer-level UUID for session tracking
/// - SHA-256 dedup: skip transfer if remote already has matching hash
/// - Resume after disconnect: track chunk index, continue from last ACKed
///
/// Priority rules:
/// - Records always sync before images
/// - Image sync over BT is user-initiated ("Sync Images Now")
/// - LAN sync auto-includes images (100× faster than BT)
public actor BinarySyncManager {
    private let db: AppDatabase
    private let queue: SyncPriorityQueue

    /// Active transfers being sent or received.
    private var activeTransfers: [UUID: TransferState] = [:]

    /// Maximum chunk payload size (16KB frame - 32B header - 4B CRC = 16,352 bytes)
    public static let maxChunkPayload = 16_352

    /// Magic bytes identifying a WiredPart binary transfer frame.
    public static let magicBytes: [UInt8] = [0x57, 0x50, 0x42, 0x54] // "WPBT"

    public init(db: AppDatabase, queue: SyncPriorityQueue) {
        self.db = db
        self.queue = queue
    }

    // MARK: - Enqueue Binary for Sync

    /// Queue a binary attachment for sync to peers.
    ///
    /// - Parameters:
    ///   - data: The binary data to transfer.
    ///   - tableName: The table this attachment belongs to (e.g. "parts", "scanned_documents").
    ///   - recordId: The record ID this attachment belongs to.
    ///   - attachmentType: Type of attachment (image, document, etc.)
    ///   - priority: Queue priority (3 = thumbnail, 4 = full-size).
    public func enqueueBinary(
        data: Data,
        tableName: String,
        recordId: Int64,
        attachmentType: BinaryAttachmentType,
        priority: Int = 4
    ) async throws {
        // Compute SHA-256 hash for dedup
        let hash = sha256Hash(data)

        // Store in local DB
        try await db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: """
                    INSERT OR IGNORE INTO _binary_attachments
                        (table_name, record_id, attachment_type, data_hash,
                         data_size, sync_status, created_at)
                    VALUES (?, ?, ?, ?, ?, 'pending', datetime('now'))
                    """,
                arguments: [tableName, recordId, attachmentType.rawValue, hash, data.count]
            )
        }

        // Add to priority queue
        let item = SyncQueueItem(
            priority: priority,
            type: attachmentType == .imageThumbnail ? .imageThumbnail : .imageFullSize,
            tableName: tableName,
            recordId: recordId,
            data: data,
            metadata: ["hash": hash, "attachment_type": attachmentType.rawValue]
        )
        await queue.enqueue(item)
    }

    // MARK: - Process Queue

    /// Process pending binary transfers.
    ///
    /// Called by the sync engine after all record syncs complete.
    /// Dequeues items and chunks them for transfer.
    ///
    /// - Parameter sendChunk: Closure to send a single chunk to the peer.
    /// - Returns: Number of items transferred.
    @discardableResult
    public func processQueue(
        sendChunk: @Sendable (BinaryChunk) async throws -> Bool
    ) async throws -> Int {
        var transferCount = 0

        while let item = await queue.dequeueBinary(count: 1).first {
            guard let data = item.data else { continue }

            let transferId = item.transferId
            let totalChunks = (data.count + Self.maxChunkPayload - 1) / Self.maxChunkPayload

            activeTransfers[transferId] = TransferState(
                transferId: transferId,
                totalSize: data.count,
                totalChunks: totalChunks,
                lastAckedChunk: -1
            )

            // Send chunks
            for chunkIndex in 0..<totalChunks {
                let offset = chunkIndex * Self.maxChunkPayload
                let length = min(Self.maxChunkPayload, data.count - offset)
                let chunkData = data.subdata(in: offset..<(offset + length))

                let chunk = BinaryChunk(
                    transferId: transferId,
                    chunkIndex: chunkIndex,
                    totalChunks: totalChunks,
                    totalSize: data.count,
                    payload: chunkData,
                    crc32: Self.crc32(chunkData)
                )

                let acked = try await sendChunk(chunk)
                if acked {
                    activeTransfers[transferId]?.lastAckedChunk = chunkIndex
                } else {
                    // Transfer failed — re-enqueue for retry
                    await queue.enqueue(item)
                    break
                }
            }

            // Log transfer completion
            try logTransfer(
                transferId: transferId,
                tableName: item.tableName ?? "",
                recordId: item.recordId ?? 0,
                dataSize: data.count,
                status: activeTransfers[transferId]?.isComplete == true ? "completed" : "partial"
            )

            activeTransfers.removeValue(forKey: transferId)
            transferCount += 1
        }

        return transferCount
    }

    // MARK: - Handle Incoming Manifest

    /// Check which attachments the peer already has (dedup via hash).
    ///
    /// - Parameter hashes: SHA-256 hashes of attachments the peer wants to send.
    /// - Returns: Hashes that we don't have yet (need to receive).
    public func filterNeededHashes(_ hashes: [String]) throws -> [String] {
        try db.writer.read { dbConnection in
            let existingHashes = try String.fetchAll(
                dbConnection,
                sql: """
                    SELECT data_hash FROM _binary_attachments
                    WHERE data_hash IN (\(hashes.map { _ in "?" }.joined(separator: ",")))
                    """,
                arguments: StatementArguments(hashes)
            )
            let existingSet = Set(existingHashes)
            return hashes.filter { !existingSet.contains($0) }
        }
    }

    // MARK: - Resume Transfer

    /// Resume a partially-completed transfer from the last ACKed chunk.
    ///
    /// - Parameter transferId: The transfer session UUID.
    /// - Returns: The chunk index to resume from, or nil if transfer not found.
    public func resumeIndex(for transferId: UUID) -> Int? {
        guard let state = activeTransfers[transferId] else { return nil }
        return state.lastAckedChunk + 1
    }

    // MARK: - Transfer Status

    /// Get status of all active transfers.
    public func activeTransferStatus() -> [TransferStatusInfo] {
        activeTransfers.values.map { state in
            TransferStatusInfo(
                transferId: state.transferId,
                totalSize: state.totalSize,
                totalChunks: state.totalChunks,
                completedChunks: state.lastAckedChunk + 1,
                isComplete: state.isComplete
            )
        }
    }

    /// Get count of pending binary items.
    public func pendingCount() async -> Int {
        await queue.binaryCount
    }

    // MARK: - Private Helpers

    private func logTransfer(
        transferId: UUID,
        tableName: String,
        recordId: Int64,
        dataSize: Int,
        status: String
    ) throws {
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: """
                    INSERT INTO _sync_transfer_log
                        (transfer_id, table_name, record_id, data_size, status, created_at)
                    VALUES (?, ?, ?, ?, ?, datetime('now'))
                    """,
                arguments: [transferId.uuidString, tableName, recordId, dataSize, status]
            )
        }
    }

    private func sha256Hash(_ data: Data) -> String {
        let digest = CryptoKitSHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Compute CRC32 checksum for chunk integrity verification.
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (crc & 1 != 0 ? 0xEDB88320 : 0)
            }
        }
        return ~crc
    }

    // MARK: - Transfer State

    private struct TransferState {
        let transferId: UUID
        let totalSize: Int
        let totalChunks: Int
        var lastAckedChunk: Int

        var isComplete: Bool {
            lastAckedChunk >= totalChunks - 1
        }
    }
}

// MARK: - Binary Chunk

/// A single chunk in a binary transfer frame.
public struct BinaryChunk: Sendable {
    public let transferId: UUID
    public let chunkIndex: Int
    public let totalChunks: Int
    public let totalSize: Int
    public let payload: Data
    public let crc32: UInt32

    /// Serialize this chunk to a wire-format frame.
    ///
    /// Frame layout (16KB max):
    /// - [0..3]   Magic bytes: "WPBT"
    /// - [4..19]  Transfer ID (UUID bytes)
    /// - [20..23] Chunk index (UInt32 big-endian)
    /// - [24..27] Total chunks (UInt32 big-endian)
    /// - [28..31] Total size (UInt32 big-endian)
    /// - [32..N]  Payload data
    /// - [N..N+3] CRC32 checksum (UInt32 big-endian)
    public func serialize() -> Data {
        var frame = Data()
        frame.append(contentsOf: BinarySyncManager.magicBytes)

        // Transfer ID as 16 bytes
        let uuid = transferId
        var uuidBytes = uuid.uuid
        frame.append(Data(bytes: &uuidBytes, count: 16))

        // Chunk index
        var idx = UInt32(chunkIndex).bigEndian
        frame.append(Data(bytes: &idx, count: 4))

        // Total chunks
        var total = UInt32(totalChunks).bigEndian
        frame.append(Data(bytes: &total, count: 4))

        // Total size
        var size = UInt32(totalSize).bigEndian
        frame.append(Data(bytes: &size, count: 4))

        // Payload
        frame.append(payload)

        // CRC32
        var checksum = crc32.bigEndian
        frame.append(Data(bytes: &checksum, count: 4))

        return frame
    }

    /// Deserialize a frame from wire format.
    public static func deserialize(_ data: Data) -> BinaryChunk? {
        guard data.count >= 36 else { return nil } // Minimum: header + CRC, no payload

        // Copy to contiguous bytes for safe aligned reads
        let bytes = [UInt8](data)

        // Verify magic bytes
        guard Array(bytes[0..<4]) == BinarySyncManager.magicBytes else { return nil }

        // Transfer ID (16 bytes at offset 4)
        let uuidTuple: uuid_t = (
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15],
            bytes[16], bytes[17], bytes[18], bytes[19]
        )
        let transferId = UUID(uuid: uuidTuple)

        // Chunk index (4 bytes at offset 20, big-endian)
        let chunkIndex = UInt32(bytes[20]) << 24 | UInt32(bytes[21]) << 16
            | UInt32(bytes[22]) << 8 | UInt32(bytes[23])

        // Total chunks (4 bytes at offset 24, big-endian)
        let totalChunks = UInt32(bytes[24]) << 24 | UInt32(bytes[25]) << 16
            | UInt32(bytes[26]) << 8 | UInt32(bytes[27])

        // Total size (4 bytes at offset 28, big-endian)
        let totalSize = UInt32(bytes[28]) << 24 | UInt32(bytes[29]) << 16
            | UInt32(bytes[30]) << 8 | UInt32(bytes[31])

        // Payload (everything between header and CRC)
        let payloadData = Data(bytes[32..<(bytes.count - 4)])

        // CRC32 (last 4 bytes, big-endian)
        let crcOffset = bytes.count - 4
        let expectedCRC = UInt32(bytes[crcOffset]) << 24 | UInt32(bytes[crcOffset + 1]) << 16
            | UInt32(bytes[crcOffset + 2]) << 8 | UInt32(bytes[crcOffset + 3])

        // Verify CRC
        let computedCRC = BinarySyncManager.crc32(payloadData)
        guard computedCRC == expectedCRC else { return nil }

        return BinaryChunk(
            transferId: transferId,
            chunkIndex: Int(chunkIndex),
            totalChunks: Int(totalChunks),
            totalSize: Int(totalSize),
            payload: payloadData,
            crc32: expectedCRC
        )
    }
}

// MARK: - Binary Attachment Type

/// Types of binary attachments that can be synced.
public enum BinaryAttachmentType: String, Sendable {
    case partImage = "part_image"
    case imageThumbnail = "image_thumbnail"
    case scannedDocument = "scanned_document"
    case receiptPhoto = "receipt_photo"
    case jobPhoto = "job_photo"
}

// MARK: - Transfer Status Info

/// Status info for an active transfer (for UI display).
public struct TransferStatusInfo: Sendable, Identifiable {
    public var id: UUID { transferId }
    public let transferId: UUID
    public let totalSize: Int
    public let totalChunks: Int
    public let completedChunks: Int
    public let isComplete: Bool

    /// Progress from 0.0 to 1.0.
    public var progress: Double {
        guard totalChunks > 0 else { return 0 }
        return Double(completedChunks) / Double(totalChunks)
    }

    /// Human-readable size description.
    public var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }
}
