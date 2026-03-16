import Testing
import Foundation
@testable import WiredPartCore

@Suite("Binary Sync Tests")
struct BinarySyncTests {

    // MARK: - CRC32 Tests

    @Test("CRC32 produces consistent checksum")
    func testCRC32Consistency() {
        let data = Data("Hello, WiredPart!".utf8)
        let crc1 = BinarySyncManager.crc32(data)
        let crc2 = BinarySyncManager.crc32(data)
        #expect(crc1 == crc2)
    }

    @Test("CRC32 differs for different data")
    func testCRC32DifferentData() {
        let data1 = Data("Hello".utf8)
        let data2 = Data("World".utf8)
        let crc1 = BinarySyncManager.crc32(data1)
        let crc2 = BinarySyncManager.crc32(data2)
        #expect(crc1 != crc2)
    }

    @Test("CRC32 of empty data")
    func testCRC32Empty() {
        let crc = BinarySyncManager.crc32(Data())
        // CRC32 of empty data is 0x00000000
        #expect(crc == 0)
    }

    // MARK: - Binary Chunk Tests

    @Test("BinaryChunk serialize/deserialize round-trip")
    func testChunkRoundTrip() {
        let payload = Data(repeating: 0xAB, count: 1000)
        let chunk = BinaryChunk(
            transferId: UUID(),
            chunkIndex: 3,
            totalChunks: 10,
            totalSize: 10000,
            payload: payload,
            crc32: BinarySyncManager.crc32(payload)
        )

        let serialized = chunk.serialize()
        guard let deserialized = BinaryChunk.deserialize(serialized) else {
            Issue.record("Deserialization returned nil")
            return
        }

        #expect(deserialized.transferId == chunk.transferId)
        #expect(deserialized.chunkIndex == chunk.chunkIndex)
        #expect(deserialized.totalChunks == chunk.totalChunks)
        #expect(deserialized.totalSize == chunk.totalSize)
        #expect(deserialized.payload == chunk.payload)
        #expect(deserialized.crc32 == chunk.crc32)
    }

    @Test("BinaryChunk rejects corrupted data")
    func testChunkCorruptionDetection() {
        let payload = Data("test data".utf8)
        let chunk = BinaryChunk(
            transferId: UUID(),
            chunkIndex: 0,
            totalChunks: 1,
            totalSize: payload.count,
            payload: payload,
            crc32: BinarySyncManager.crc32(payload)
        )

        var serialized = chunk.serialize()

        // Corrupt a byte in the payload area
        if serialized.count > 40 {
            serialized[35] ^= 0xFF
        }

        let result = BinaryChunk.deserialize(serialized)
        #expect(result == nil, "Corrupted chunk should fail CRC check")
    }

    @Test("BinaryChunk rejects too-short data")
    func testChunkTooShort() {
        let result = BinaryChunk.deserialize(Data([0x57, 0x50, 0x42, 0x54]))
        #expect(result == nil, "Too-short data should return nil")
    }

    @Test("BinaryChunk rejects wrong magic bytes")
    func testChunkWrongMagic() {
        var data = Data(repeating: 0, count: 40)
        data[0] = 0xFF // Wrong magic
        let result = BinaryChunk.deserialize(data)
        #expect(result == nil, "Wrong magic should return nil")
    }

    // MARK: - Magic Bytes

    @Test("Magic bytes are WPBT")
    func testMagicBytes() {
        let magic = BinarySyncManager.magicBytes
        #expect(magic == [0x57, 0x50, 0x42, 0x54]) // W, P, B, T
    }

    // MARK: - Transfer Status Info

    @Test("Transfer progress calculation")
    func testTransferProgress() {
        let status = TransferStatusInfo(
            transferId: UUID(),
            totalSize: 100_000,
            totalChunks: 10,
            completedChunks: 5,
            isComplete: false
        )

        #expect(status.progress == 0.5)
        #expect(!status.isComplete)
    }

    @Test("Completed transfer has progress 1.0")
    func testCompletedTransfer() {
        let status = TransferStatusInfo(
            transferId: UUID(),
            totalSize: 100_000,
            totalChunks: 10,
            completedChunks: 10,
            isComplete: true
        )

        #expect(status.progress == 1.0)
        #expect(status.isComplete)
    }

    // MARK: - Database Integration

    @Test("Migration 018 creates all required tables")
    func testMigration018Tables() async throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let tables = ["_text_history", "part_image_features", "image_match_history",
                       "_binary_attachments", "_sync_transfer_log"]

        for table in tables {
            let exists = try await db.writer.read { dbConnection in
                try dbConnection.tableExists(table)
            }
            #expect(exists, "Table \(table) should exist after migration 018")
        }
    }

    @Test("_text_history table has unique constraint")
    func testTextHistoryUniqueConstraint() async throws {
        let db = try AppDatabase.openInMemoryDatabase()

        // Insert a user
        try await db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: "INSERT INTO users (id, display_name, pin_hash) VALUES (1, 'Test', 'hash')"
            )
        }

        // Insert same entry twice — should use ON CONFLICT
        try await db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: """
                    INSERT INTO _text_history (user_id, field_type, text, frequency)
                    VALUES (1, 'notes', 'test', 1)
                    ON CONFLICT (user_id, field_type, text) DO UPDATE SET
                        frequency = frequency + 1
                    """
            )
            try dbConnection.execute(
                sql: """
                    INSERT INTO _text_history (user_id, field_type, text, frequency)
                    VALUES (1, 'notes', 'test', 1)
                    ON CONFLICT (user_id, field_type, text) DO UPDATE SET
                        frequency = frequency + 1
                    """
            )
        }

        let frequency: Int? = try await db.writer.read { dbConnection in
            try Int.fetchOne(
                dbConnection,
                sql: "SELECT frequency FROM _text_history WHERE user_id = 1 AND text = 'test'"
            )
        }

        #expect(frequency == 2)
    }

    @Test("_binary_attachments hash uniqueness")
    func testBinaryAttachmentHashUnique() async throws {
        let db = try AppDatabase.openInMemoryDatabase()

        try await db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: """
                    INSERT INTO _binary_attachments
                        (table_name, record_id, attachment_type, data_hash, data_size)
                    VALUES ('parts', 1, 'part_image', 'hash123', 1000)
                    """
            )
        }

        // Inserting same hash should fail (unique constraint)
        await #expect(throws: (any Error).self) {
            try await db.writer.write { dbConnection in
                try dbConnection.execute(
                    sql: """
                        INSERT INTO _binary_attachments
                            (table_name, record_id, attachment_type, data_hash, data_size)
                        VALUES ('parts', 2, 'part_image', 'hash123', 2000)
                        """
                )
            }
        }
    }
}
