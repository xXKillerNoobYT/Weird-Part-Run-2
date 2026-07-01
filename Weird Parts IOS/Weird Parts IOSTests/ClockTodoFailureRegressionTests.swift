import XCTest

/// Regression coverage for GitHub #1207 / Paperclip WEI-4183.
///
/// Clock to-do selection must not show optimistic state when persistence fails,
/// and to-do load failures must remain visible instead of looking like an empty
/// picker. These source guards protect the SwiftUI state transitions until the
/// clock page is split into a directly injectable view model.
final class ClockTodoFailureRegressionTests: XCTestCase {
    func testSelectingTodoOnlyUpdatesCurrentTodoAfterLinkSucceeds() throws {
        let source = try Self.readClockSource()
        let section = try Self.section(
            named: "private func selectTodo",
            in: source,
            endingBefore: "private func markTodoDoneAndPickNext"
        )

        let linkRange = try XCTUnwrap(section.range(of: "try service.linkClockEntryToTodo(clockEntryId: entry.id, todoId: todo.id)"))
        let assignmentRange = try XCTUnwrap(section.range(of: "currentTodo = todo"))
        XCTAssertLessThan(linkRange.lowerBound, assignmentRange.lowerBound, "The picker must not show the selected to-do until the database link succeeds.")
        XCTAssertTrue(section.contains("errorMessage = \"Could not link this to-do to your clock entry"), "Link failures need a visible field-user error, not only a log line.")
    }

    func testCompletedTodoUnlinkFailureKeepsCurrentTodoAndSurfacesError() throws {
        let source = try Self.readClockSource()
        let section = try Self.section(
            named: "private func markTodoDoneAndPickNext",
            in: source,
            endingBefore: "// MARK: - Helpers"
        )

        let unlinkRange = try XCTUnwrap(section.range(of: "try jobsService.linkClockEntryToTodo(clockEntryId: entry.id, todoId: nil)"))
        let clearRange = try XCTUnwrap(section.range(of: "currentTodo = nil"))
        XCTAssertLessThan(unlinkRange.lowerBound, clearRange.lowerBound, "The UI must not clear the current to-do until the clock-entry unlink succeeds.")
        XCTAssertTrue(section.contains("The to-do was completed, but the clock entry could not be unlinked"), "Unlink failures need a visible error before another to-do can be picked.")
        XCTAssertTrue(section.contains("if !remaining.isEmpty, didUnlinkTodo"), "The next picker should only open after the unlink succeeded.")
    }

    func testTodoLoadFailuresPreserveSameJobListClearChangedJobAndShowSpecificError() throws {
        let source = try Self.readClockSource()
        let loadDataSection = try Self.section(
            named: "private func loadJobsAndClockStatus",
            in: source,
            endingBefore: "// MARK: - Switch Job Picker Sheet"
        )

        XCTAssertTrue(loadDataSection.contains("var todoLoadError: String?"), "Full clock refresh should isolate to-do load failures from the rest of the clock data.")
        XCTAssertTrue(loadDataSection.contains("if entry != nil, todoLoadError == nil {\n                    activeTodos = todos"), "Full clock refresh should preserve the previous to-do list when only to-do loading fails.")
        XCTAssertTrue(loadDataSection.contains("let previousActiveJobId = activeEntry?.jobId"), "Full clock refresh should remember which job the preserved to-do list belongs to.")
        XCTAssertTrue(loadDataSection.contains("} else if let entry, previousActiveJobId != entry.jobId {\n                    activeTodos = []\n                    currentTodo = nil"), "A to-do load failure for a changed active job must clear stale to-dos from the previous job.")
        XCTAssertTrue(loadDataSection.contains("errorMessage = todoLoadError"), "To-do load failures should remain visible after the rest of the clock data loads.")
    }

    private static func section(named startMarker: String, in source: String, endingBefore endMarker: String) throws -> String {
        guard let start = source.range(of: startMarker) else {
            XCTFail("Missing section starting with \(startMarker)")
            return ""
        }
        let afterStart = source[start.lowerBound...]
        guard let end = afterStart.range(of: endMarker) else {
            XCTFail("Missing section ending before \(endMarker)")
            return ""
        }
        return String(afterStart[..<end.lowerBound])
    }

    private static func readClockSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Jobs")
            .appendingPathComponent("IOSClockPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}