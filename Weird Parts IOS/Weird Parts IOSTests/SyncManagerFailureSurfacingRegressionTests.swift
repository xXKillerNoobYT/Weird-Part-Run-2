import XCTest

final class SyncManagerFailureSurfacingRegressionTests: XCTestCase {
    func testSyncReadFailuresMoveManagerIntoVisibleErrorState() throws {
        let source = try Self.readSyncManagerSource()

        XCTAssertFalse(
            source.contains("try? ChangeTracker.getPendingChangeCount(db: db)"),
            "Pending-change query failures must not be hidden as a zero-count state."
        )
        XCTAssertFalse(
            source.contains("try? ConflictResolver.getConflictStats(db: db)"),
            "Conflict-count query failures must not be hidden as a zero-conflict state."
        )
        XCTAssertFalse(
            source.contains("try? ConflictResolver.getUnreviewedConflicts(db: db)"),
            "Conflict-list query failures must not be hidden as an empty review list."
        )
        XCTAssertTrue(
            source.contains("private func syncReadFailed(_ error: Error, context: String, logMessage: String)") &&
                source.contains("syncStatus = .error") &&
                source.contains("errorMessage = userFriendlyError(error, context: context)"),
            "Sync read failures should route through a helper that exposes a recoverable sync error state."
        )
        XCTAssertTrue(
            source.contains("context: \"load pending sync changes\"") &&
                source.contains("context: \"load sync conflict count\"") &&
                source.contains("context: \"load unreviewed sync conflicts\""),
            "Pending-count, conflict-count, and conflict-list reads should all surface contextual user-facing errors."
        )
    }

    func testConflictReviewActionsDoNotSilentlySkipMissingIdsOrFailedWrites() throws {
        let managerSource = try Self.readSyncManagerSource()
        let reviewSource = try Self.readConflictReviewSource()

        XCTAssertFalse(
            reviewSource.contains("guard let id = conflict.id else { return }"),
            "Conflict-review rows with missing IDs must show an error instead of making Accept a silent no-op."
        )
        XCTAssertFalse(
            reviewSource.contains("guard let conflictId = conflict.id else { return }"),
            "AI merge requests with missing IDs must show an error instead of silently doing nothing."
        )
        XCTAssertTrue(
            reviewSource.contains("@State private var actionError: String?") &&
                reviewSource.contains(".alert(\"Sync conflict action failed\"") &&
                reviewSource.contains("conflict id is missing"),
            "The review page should present a visible recovery message for corrupt/id-less conflict rows."
        )
        XCTAssertTrue(
            managerSource.contains("@discardableResult\n    func markConflictReviewed(conflictId: Int64) -> Bool") &&
                managerSource.contains("@discardableResult\n    func markAllConflictsReviewed() -> Bool"),
            "Review actions should return success/failure so the UI only removes rows after a confirmed write."
        )
        XCTAssertTrue(
            managerSource.contains("syncReviewActionFailed(\"A sync conflict could not be marked reviewed because its conflict id is missing") &&
                managerSource.contains("context: \"mark sync conflict reviewed\"") &&
                managerSource.contains("context: \"mark sync conflicts reviewed\"") &&
                managerSource.contains("surfaceConflictReviewActionFailure"),
            "Manager-level conflict review failures should be promoted into the same visible sync error surface."
        )
        XCTAssertTrue(
            managerSource.contains("conflicts = try ConflictResolver.getUnreviewedConflicts(db: db)") &&
                managerSource.contains("context: \"load unreviewed sync conflicts before marking reviewed\""),
            "Accept All must fail visibly if the conflict list cannot be read before writes start."
        )
    }

    private static func repoRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func readSyncManagerSource(file: StaticString = #filePath) throws -> String {
        let sourceURL = repoRoot(file: file)
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Sync")
            .appendingPathComponent("IOSSyncManager.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func readConflictReviewSource(file: StaticString = #filePath) throws -> String {
        let sourceURL = repoRoot(file: file)
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Sync")
            .appendingPathComponent("SyncConflictReviewPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
