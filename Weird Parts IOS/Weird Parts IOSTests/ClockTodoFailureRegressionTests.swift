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
        XCTAssertTrue(section.contains("errorMessage = \"No active clock entry available\""), "Missing active-entry failures should be distinct from missing service failures.")
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
        XCTAssertTrue(section.contains("let didUnlinkTodo = await MainActor.run"), "The unlink result should be returned from MainActor.run instead of mutating captured state across an await.")
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
        let normalizedLoadData = Self.normalizedWhitespace(loadDataSection)
        XCTAssertTrue(normalizedLoadData.contains("if entry != nil, todoLoadError == nil { activeTodos = todos"), "Full clock refresh should preserve the previous to-do list when only to-do loading fails.")
        XCTAssertTrue(loadDataSection.contains("let previousActiveJobId = activeEntry?.jobId"), "Full clock refresh should remember which job the preserved to-do list belongs to.")
        XCTAssertTrue(normalizedLoadData.contains("} else if let entry, previousActiveJobId != entry.jobId { activeTodos = [] currentTodo = nil"), "A to-do load failure for a changed active job must clear stale to-dos from the previous job.")
        XCTAssertTrue(loadDataSection.contains("errorMessage = todoLoadError"), "To-do load failures should remain visible after the rest of the clock data loads.")
    }

    func testPickerButtonsReloadTodosBeforeOpeningSheet() throws {
        let source = try Self.readClockSource()
        let section = try Self.section(
            named: "private func currentTaskSection",
            in: source,
            endingBefore: "// MARK: - Flex Pool Actions"
        )
        let normalized = Self.normalizedWhitespace(section)
        let reloadBeforePickerCount = normalized.components(separatedBy: "loadTodosForJob(jobId: entry.jobId) activeSheet = .todoPicker").count - 1

        XCTAssertEqual(reloadBeforePickerCount, 2, "Both picker buttons should reload the active job's list before showing the picker.")
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

    private static func normalizedWhitespace(_ source: String) -> String {
        source
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
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