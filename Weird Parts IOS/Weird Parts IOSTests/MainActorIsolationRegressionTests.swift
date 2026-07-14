import Foundation
import WiredPartCore
import XCTest
@testable import Weird_Parts

final class MainActorIsolationRegressionTests: XCTestCase {
    private enum ProbeError: Error {
        case failed
    }

    func testErrorHelpersRunFromDetachedExecutor() async {
        let messages = await Task.detached {
            (
                settingsHydrationMessage(ProbeError.failed),
                userFriendlyError(ProbeError.failed, context: "load probe")
            )
        }.value

        XCTAssertEqual(messages.0, "Couldn't load. Pull down to retry.")
        XCTAssertEqual(messages.1, "Couldn't load probe. Pull down to retry.")
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
