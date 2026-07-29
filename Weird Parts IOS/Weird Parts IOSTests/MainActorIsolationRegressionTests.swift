import Foundation
import WiredPartCore
import XCTest
@testable import Weird_Parts

final class MainActorIsolationRegressionTests: XCTestCase {
    private enum ProbeError: Error {
        case failed
    }

    func testExecutorSafeHelpersRunFromDetachedExecutor() async {
        let results = await Task.detached {
            var deliveryGate = QRScanDeliveryGate()
            let claimed = deliveryGate.claim("PO-42")
            deliveryGate.cancel()
            let completedAfterCancel = deliveryGate.finish(
                "PO-42",
                isFound: true,
                shouldComplete: true
            )
            let feedback = QRScanFeedback(
                isFound: true,
                entityType: nil,
                expectedType: .po,
                title: "External catalog match",
                code: "EXT-42"
            )
            let hydrationError = SettingsHydrationError(
                invalidEntries: [.init(key: "probe", value: "bad", expectedType: "number")]
            )
            return (
                settingsHydrationMessage(ProbeError.failed),
                userFriendlyError(ProbeError.failed, context: "load probe"),
                claimed,
                completedAfterCancel,
                QRScanManualSubmissionGate.code(from: " PO-42 ", isProcessing: false),
                feedback.message,
                hydrationError.localizedDescription
            )
        }.value

        XCTAssertEqual(results.0, "Couldn't load. Pull down to retry.")
        XCTAssertEqual(results.1, "Couldn't load probe. Pull down to retry.")
        XCTAssertTrue(results.2)
        XCTAssertFalse(results.3)
        XCTAssertEqual(results.4, "PO-42")
        XCTAssertEqual(results.5, "Expected po, got external")
        XCTAssertTrue(results.6.contains("probe=\"bad\""))
    }

    func testAttachmentResolutionRunsFromDetachedExecutor() async {
        let resolvedURL = await Task.detached { () -> URL? in
            let attachment = ChatService.MessageAttachment(
                id: 1,
                messageId: 1,
                attachmentType: "file",
                filePath: "/path/that/does/not/exist/attachment.pdf",
                fileName: "attachment.pdf",
                fileSize: nil,
                mimeType: "application/pdf",
                referenceId: nil,
                referenceLabel: nil
            )
            return resolveAttachmentURL(attachment)
        }.value

        XCTAssertNil(resolvedURL)
    }

    func testWarehouseAreaLoaderRunsFromDetachedExecutor() async throws {
        let areaCount = try await Task.detached { () throws -> Int in
            let database = try AppDatabase.openInMemoryDatabase()
            let service = WarehouseService(db: database)
            return try loadAllWizardAreas(floorPlanId: -1, service: service).count
        }.value

        XCTAssertEqual(areaCount, 0)
    }
}
