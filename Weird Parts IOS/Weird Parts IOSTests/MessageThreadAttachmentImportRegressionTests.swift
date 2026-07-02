import XCTest

/// Regression coverage for issue #1101: chat photo attachments must never be
/// queued after a failed temp-file write. The import path has to use explicit
/// do/catch, append the pending attachment only after `data.write(to:)`
/// succeeds, and surface failures to the user.
final class MessageThreadAttachmentImportRegressionTests: XCTestCase {
    func testPhotoImportDoesNotSwallowTempFileWriteFailures() throws {
        let source = try Self.readMessageThreadViewSource()

        XCTAssertFalse(
            source.contains("try? data.write("),
            "Attachment import must not swallow temp-file write failures with try? — a failed write queues a path that doesn't exist and silently drops the photo at send time."
        )
        XCTAssertFalse(
            source.contains("try? await item.loadTransferable"),
            "Attachment import must not swallow photo-load failures with try? — failures should be counted and surfaced to the user."
        )
        XCTAssertTrue(
            source.contains("try data.write(to: tmpURL)"),
            "Attachment import should write the temp file with explicit error propagation inside do/catch."
        )
        XCTAssertTrue(
            source.contains("attachmentError ="),
            "Attachment import failures should set a user-visible attachmentError instead of failing silently."
        )
        XCTAssertTrue(
            source.contains(".alert(\"Attachment Failed\""),
            "The thread view should present an alert when photo attachment import fails."
        )
    }

    func testPendingAttachmentAppendedOnlyAfterSuccessfulWrite() throws {
        let source = try Self.readMessageThreadViewSource()

        guard let writeRange = source.range(of: "try data.write(to: tmpURL)"),
              let appendRange = source.range(of: "ChatService.PendingAttachment(\n                                type: \"photo\"") else {
            XCTFail("Expected the explicit write and the photo PendingAttachment construction to both exist in the import path.")
            return
        }
        XCTAssertTrue(
            writeRange.lowerBound < appendRange.lowerBound,
            "The temp-file write must happen (and succeed) before the photo attachment is constructed and queued."
        )
    }

    private static func readMessageThreadViewSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Chat")
            .appendingPathComponent("IOSMessageThreadView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
