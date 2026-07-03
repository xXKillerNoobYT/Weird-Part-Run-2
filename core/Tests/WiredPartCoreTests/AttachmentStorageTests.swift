import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// Covers attachment durability (#1371): relative-path storage round-trip,
/// missing-file resolution, the `storage_relative` schema/round-trip through
/// `ChatService`, and the legacy-path reconciler.
@Suite("Attachment Storage Tests")
struct AttachmentStorageTests {

    /// A throwaway base directory under the temp dir, isolated per test.
    private func makeScratchStorage() -> (storage: AttachmentStorage, base: URL) {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("attach-storage-test-\(UUID().uuidString)", isDirectory: true)
        return (AttachmentStorage(baseDirectory: base), base)
    }

    // MARK: - Round-trip (the acceptance-criteria core test)

    @Test("store writes a relative path that resolves back to the same bytes")
    func testStoreResolveRoundTrip() throws {
        let (storage, base) = makeScratchStorage()
        defer { try? FileManager.default.removeItem(at: base) }

        let bytes = Data("hello attachment".utf8)
        let relative = try storage.store(data: bytes, preferredName: "photo.jpg")

        // Path must be RELATIVE (no leading slash) and under ChatAttachments/,
        // preserving the original extension.
        #expect(!relative.hasPrefix("/"))
        #expect(relative.hasPrefix("\(AttachmentStorage.subdirectoryName)/"))
        #expect(relative.hasSuffix(".jpg"))

        // Resolves to a real file with identical bytes.
        let resolved = try #require(storage.resolveURL(relativePath: relative))
        #expect(resolved.isFileURL)
        let readBack = try Data(contentsOf: resolved)
        #expect(readBack == bytes)
    }

    @Test("resolveURL returns nil once the underlying file is gone (tmp purge)")
    func testResolveReturnsNilWhenFileMissing() throws {
        let (storage, base) = makeScratchStorage()
        defer { try? FileManager.default.removeItem(at: base) }

        let relative = try storage.store(data: Data([1, 2, 3]), preferredName: "doc.pdf")
        let resolved = try #require(storage.resolveURL(relativePath: relative))

        // Simulate iOS purging the file out from under a stored relative path.
        try FileManager.default.removeItem(at: resolved)

        #expect(storage.resolveURL(relativePath: relative) == nil)
        #expect(storage.fileExists(relativePath: relative) == false)
    }

    @Test("a resolved path survives a base-directory move (container change)")
    func testRelativePathSurvivesContainerMove() throws {
        // Old container.
        let old = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("attach-old-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: old) }
        let oldStorage = AttachmentStorage(baseDirectory: old)
        let relative = try oldStorage.store(data: Data("payload".utf8), preferredName: "x.bin")

        // New container: move the whole base tree, then resolve the SAME relative
        // path against the new base — this is what a sandbox-container change looks
        // like. An absolute path would dangle here; a relative one survives.
        let new = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("attach-new-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: new) }
        try FileManager.default.moveItem(at: old, to: new)

        let newStorage = AttachmentStorage(baseDirectory: new)
        let resolved = try #require(newStorage.resolveURL(relativePath: relative))
        #expect(try Data(contentsOf: resolved) == Data("payload".utf8))
    }

    @Test("store(copyingFrom:) copies an external file into storage")
    func testStoreCopyingFrom() throws {
        let (storage, base) = makeScratchStorage()
        defer { try? FileManager.default.removeItem(at: base) }

        let src = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ext-\(UUID().uuidString).txt")
        try Data("external".utf8).write(to: src)
        defer { try? FileManager.default.removeItem(at: src) }

        let relative = try storage.store(copyingFrom: src, preferredName: nil)
        #expect(relative.hasSuffix(".txt"))
        let resolved = try #require(storage.resolveURL(relativePath: relative))
        #expect(try Data(contentsOf: resolved) == Data("external".utf8))
    }

    // MARK: - Schema + ChatService round-trip

    @Test("sendMessageWithAttachments persists and returns storage_relative")
    func testStorageRelativePersistsThroughChatService() throws {
        let env = try E2ETestHelpers.setUp()
        let channelId = try env.chat.createChannel(name: "Durable Attach", createdBy: env.adminUserId)

        let relativeAtt = ChatService.PendingAttachment(
            type: "photo",
            filePath: "ChatAttachments/abc.jpg",
            fileName: "abc.jpg",
            storageRelative: true
        )
        let legacyAtt = ChatService.PendingAttachment(
            type: "file",
            filePath: "/tmp/old-file.pdf",
            fileName: "old-file.pdf",
            storageRelative: false
        )
        let msgId = try env.chat.sendMessageWithAttachments(
            channelId: channelId, content: "mixed",
            userId: env.adminUserId, attachments: [relativeAtt, legacyAtt]
        )

        let stored = try env.chat.getMessageAttachments(messageId: msgId)
        #expect(stored.count == 2)
        let photo = try #require(stored.first(where: { $0.attachmentType == "photo" }))
        let file = try #require(stored.first(where: { $0.attachmentType == "file" }))
        #expect(photo.storageRelative == true)
        #expect(photo.filePath == "ChatAttachments/abc.jpg")
        #expect(file.storageRelative == false)
        #expect(file.filePath == "/tmp/old-file.pdf")

        // Batch path must carry the flag too.
        let batched = try env.chat.getAttachmentsForMessages(messageIds: [msgId])
        #expect(batched[msgId]?.contains(where: { $0.storageRelative == true }) == true)
        #expect(batched[msgId]?.contains(where: { $0.storageRelative == false }) == true)
    }

    // MARK: - Reconciler (#1371 migration of existing rows)

    @Test("reconciler rewrites a surviving legacy absolute path to relative")
    func testReconcilerMigratesSurvivingLegacyRow() throws {
        let env = try E2ETestHelpers.setUp()
        let channelId = try env.chat.createChannel(name: "Reconcile", createdBy: env.adminUserId)

        // A real file at an absolute path stands in for a legacy tmp attachment
        // that happens to still exist.
        let legacyURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("legacy-\(UUID().uuidString).jpg")
        try Data("legacy bytes".utf8).write(to: legacyURL)
        defer { try? FileManager.default.removeItem(at: legacyURL) }

        let msgId = try env.chat.sendMessageWithAttachments(
            channelId: channelId, content: "legacy photo",
            userId: env.adminUserId,
            attachments: [ChatService.PendingAttachment(
                type: "photo", filePath: legacyURL.path,
                fileName: "legacy.jpg", storageRelative: false
            )]
        )

        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reconcile-base-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let storage = AttachmentStorage(baseDirectory: base)

        let migrated = try env.chat.reconcileLegacyAttachmentPaths(storage: storage)
        #expect(migrated == 1)

        let after = try #require(try env.chat.getMessageAttachments(messageId: msgId).first)
        #expect(after.storageRelative == true)
        let path = try #require(after.filePath)
        #expect(!path.hasPrefix("/"))
        // The rewritten relative path resolves to the copied bytes.
        let resolved = try #require(storage.resolveURL(relativePath: path))
        #expect(try Data(contentsOf: resolved) == Data("legacy bytes".utf8))
        // Original tmp file was cleaned up.
        #expect(FileManager.default.fileExists(atPath: legacyURL.path) == false)
    }

    @Test("reconciler leaves a missing legacy file for the unavailable state")
    func testReconcilerLeavesMissingLegacyRow() throws {
        let env = try E2ETestHelpers.setUp()
        let channelId = try env.chat.createChannel(name: "Reconcile Missing", createdBy: env.adminUserId)

        // Absolute path to a file that does NOT exist — the tmp-purge case.
        let goneURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gone-\(UUID().uuidString).pdf")

        let msgId = try env.chat.sendMessageWithAttachments(
            channelId: channelId, content: "purged file",
            userId: env.adminUserId,
            attachments: [ChatService.PendingAttachment(
                type: "file", filePath: goneURL.path,
                fileName: "gone.pdf", storageRelative: false
            )]
        )

        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reconcile-base-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let storage = AttachmentStorage(baseDirectory: base)

        let migrated = try env.chat.reconcileLegacyAttachmentPaths(storage: storage)
        #expect(migrated == 0)

        // Row is unchanged: still absolute, still flagged legacy — so the UI can
        // resolve it to nil and show "file unavailable" (#1372).
        let after = try #require(try env.chat.getMessageAttachments(messageId: msgId).first)
        #expect(after.storageRelative == false)
        #expect(after.filePath == goneURL.path)
    }

    @Test("reconciler is idempotent and skips already-relative rows")
    func testReconcilerIdempotent() throws {
        let env = try E2ETestHelpers.setUp()
        let channelId = try env.chat.createChannel(name: "Idempotent", createdBy: env.adminUserId)

        let legacyURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("idem-\(UUID().uuidString).png")
        try Data("bytes".utf8).write(to: legacyURL)
        defer { try? FileManager.default.removeItem(at: legacyURL) }

        _ = try env.chat.sendMessageWithAttachments(
            channelId: channelId, content: "photo",
            userId: env.adminUserId,
            attachments: [ChatService.PendingAttachment(
                type: "photo", filePath: legacyURL.path,
                fileName: "idem.png", storageRelative: false
            )]
        )

        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("idem-base-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let storage = AttachmentStorage(baseDirectory: base)

        #expect(try env.chat.reconcileLegacyAttachmentPaths(storage: storage) == 1)
        // Second pass: nothing left to migrate (row is now relative).
        #expect(try env.chat.reconcileLegacyAttachmentPaths(storage: storage) == 0)
    }
}
