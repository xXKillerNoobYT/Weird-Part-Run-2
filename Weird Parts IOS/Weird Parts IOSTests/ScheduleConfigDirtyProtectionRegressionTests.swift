import XCTest

/// Regression coverage for issue #1248: the schedule config edit sheets
/// (`ShiftTemplateEditSheet`, `HolidayEditSheet`) only compared the name
/// field when deciding dirtiness, so edits to work days, times, breaks,
/// overtime rules, holiday dates, or paid/recurring toggles could be
/// swipe-dismissed or cancelled without any discard protection.
final class ScheduleConfigDirtyProtectionRegressionTests: XCTestCase {
    func testDirtyTrackingCoversAllPersistedFieldsNotJustName() throws {
        let source = try Self.readScheduleConfigSource()

        XCTAssertFalse(
            source.contains("name.trimmingCharacters(in: .whitespaces) != originalName"),
            "isDirty must not compare only the name field (issue #1248)."
        )
        // Both sheets derive dirtiness from a full-form signature baseline.
        XCTAssertEqual(
            source.components(separatedBy: "private var isDirty: Bool { formSignature != baselineSignature }").count - 1,
            2,
            "Both schedule config edit sheets should compare a full-form signature against the on-appear baseline."
        )
        // Shift template signature covers every persisted field.
        for field in ["String(selectedHatId)", "Formatters.timeHHmmFormatter.string(from: startTime)",
                      "Formatters.timeHHmmFormatter.string(from: endTime)", "String(breakMinutes)",
                      "String(breakPaid)", "overtimeRule"] {
            XCTAssertTrue(
                source.contains(field),
                "Shift template form signature should include \(field)."
            )
        }
        // Holiday signature covers date and both toggles.
        for field in ["Formatters.localDateFormatter.string(from: selectedDate)",
                      "String(isPaid)", "String(isRecurring)"] {
            XCTAssertTrue(
                source.contains(field),
                "Holiday form signature should include \(field)."
            )
        }
    }

    func testDirtySheetsRequireExplicitDiscardDecision() throws {
        let source = try Self.readScheduleConfigSource()

        // Cancel routes through the discard confirmation when dirty (both sheets).
        XCTAssertEqual(
            source.components(separatedBy: "if isDirty { showDiscardConfirm = true } else { dismiss() }").count - 1,
            2,
            "Cancel on both edit sheets should ask before discarding dirty forms."
        )
        // Swipe-dismiss protection stays wired to isDirty (both sheets, at minimum).
        XCTAssertGreaterThanOrEqual(
            source.components(separatedBy: ".interactiveDismissDisabled(isDirty)").count - 1,
            2,
            "Both edit sheets must keep interactive dismissal disabled while dirty."
        )
        XCTAssertEqual(
            source.components(separatedBy: "\"Discard changes?\"").count - 1,
            2,
            "Both edit sheets need a discard confirmation dialog."
        )
    }

    func testBaselineSnapshotsAfterPopulatingSoUntouchedSheetsAreClean() throws {
        let source = try Self.readScheduleConfigSource()

        XCTAssertEqual(
            source.components(separatedBy: "defer { baselineSignature = formSignature }").count - 1,
            2,
            "Both sheets must snapshot the baseline after populating (including the new-item defaults path) so untouched sheets never count as dirty."
        )
    }

    private static func readScheduleConfigSource(
        file: StaticString = #filePath
    ) throws -> String {
        let projectRoot = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Scheduling")
            .appendingPathComponent("IOSScheduleConfigPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
