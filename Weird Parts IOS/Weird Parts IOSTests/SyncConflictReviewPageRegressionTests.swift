import XCTest

final class SyncConflictReviewPageRegressionTests: XCTestCase {
    func testAIAndCriticalResolutionsPassSelectedValueIntoConflictResolver() throws {
        let source = try Self.readSyncConflictReviewPageSource()

        XCTAssertTrue(
            source.contains("AIConflictResolutionView(resolution: resolution) { selectedText in"),
            "AI merge selection should capture the chosen text instead of discarding it."
        )
        XCTAssertTrue(
            source.contains("markReviewed(conflict, selectedValue: selectedText)"),
            "AI/manual merge choices must pass the selected value into markReviewed."
        )
        XCTAssertTrue(
            source.contains("markReviewed(conflict, selectedValue: conflict.localValue)") &&
                source.contains("markReviewed(conflict, selectedValue: conflict.remoteValue)"),
            "Critical conflict local/remote decisions should persist the selected value before review."
        )
        XCTAssertTrue(
            source.contains("syncManager.resolveConflict(conflictId: id, selectedValue: selectedValue)"),
            "markReviewed should call IOSSyncManager.resolveConflict so chosen text is applied before marking reviewed."
        )
    }

    private static func readSyncConflictReviewPageSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Sync")
            .appendingPathComponent("SyncConflictReviewPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
