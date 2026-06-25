import XCTest

/// Regression coverage for GH#877: failed Schedule Config sheet actions must not dismiss edit context.
final class ScheduleConfigSheetFailureRegressionTests: XCTestCase {
    func testShiftTemplateAndHolidayActionsDismissSheetsOnlyAfterSuccessfulServiceCalls() throws {
        let source = try Self.readSchedulingSource(named: "IOSScheduleConfigPage.swift")

        try Self.assertDismissesOnlyOnSuccess(in: source, functionName: "saveShiftTemplate")
        try Self.assertDismissesOnlyOnSuccess(in: source, functionName: "deleteShiftTemplate")
        try Self.assertDismissesOnlyOnSuccess(in: source, functionName: "saveHoliday")
        try Self.assertDismissesOnlyOnSuccess(in: source, functionName: "deleteHoliday")
    }

    func testFailurePathsSurfaceInlineSaveErrorWithoutClearingActiveSheet() throws {
        let source = try Self.readSchedulingSource(named: "IOSScheduleConfigPage.swift")

        XCTAssertTrue(
            source.contains("actionError: saveError"),
            "Schedule Config edit sheets should receive saveError so failures remain visible without dismissing the sheet."
        )
        XCTAssertTrue(
            source.contains("accessibilityIdentifier(\"shiftTemplateActionError\")") &&
                source.contains("accessibilityIdentifier(\"holidayActionError\")"),
            "Shift template and holiday sheets should expose inline action-error labels for failed saves/deletes."
        )

        try Self.assertCatchKeepsSheetOpen(in: source, functionName: "saveShiftTemplate", context: "save shift template")
        try Self.assertCatchKeepsSheetOpen(in: source, functionName: "deleteShiftTemplate", context: "delete shift template")
        try Self.assertCatchKeepsSheetOpen(in: source, functionName: "saveHoliday", context: "save holiday")
        try Self.assertCatchKeepsSheetOpen(in: source, functionName: "deleteHoliday", context: "delete holiday")
    }

    func testSheetsDismissThemselvesOnlyWhenCallbacksSucceed() throws {
        let source = try Self.readSchedulingSource(named: "IOSScheduleConfigPage.swift")

        XCTAssertTrue(
            source.contains("if onSave(TemplateData(") && source.contains("if onSave(HolidayData("),
            "Save buttons must keep entered sheet values in place when the parent save callback reports failure."
        )
        XCTAssertTrue(
            source.components(separatedBy: "if onDelete?() == true").count >= 3,
            "Delete confirmation buttons must dismiss only after the parent delete callback reports success."
        )
    }

    private static func assertDismissesOnlyOnSuccess(
        in source: String,
        functionName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let functionBody = try extractFunctionBody(named: functionName, from: source)
        let doBody = try extractBlock(startingAt: "do {", in: functionBody)

        XCTAssertTrue(
            doBody.contains("activeSheet = nil"),
            "\(functionName) should dismiss the active edit/confirm sheet from its success path only.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            sourceAfterDoCatch(in: functionBody).contains("activeSheet = nil"),
            "\(functionName) must not unconditionally dismiss the sheet after catch; failures need preserved context/input.",
            file: file,
            line: line
        )
    }

    private static func assertCatchKeepsSheetOpen(
        in source: String,
        functionName: String,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let functionBody = try extractFunctionBody(named: functionName, from: source)
        let catchBody = try extractBlock(startingAt: "catch {", in: functionBody)

        XCTAssertTrue(
            catchBody.contains("saveError = userFriendlyError(error, context: \"\(context)\")"),
            "\(functionName) should surface the failure near the sheet action.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            catchBody.contains("activeSheet = nil"),
            "\(functionName) catch path must keep the edit/confirm sheet open after failure.",
            file: file,
            line: line
        )
    }

    private static func sourceAfterDoCatch(in functionBody: String) -> String {
        guard let catchRange = functionBody.range(of: "catch {") else { return functionBody }
        let afterCatchStart = functionBody[catchRange.lowerBound...]
        guard let catchBody = try? extractBlock(startingAt: "catch {", in: String(afterCatchStart)),
              let catchBodyRange = afterCatchStart.range(of: catchBody) else {
            return String(afterCatchStart)
        }
        return String(afterCatchStart[catchBodyRange.upperBound...])
    }

    private static func extractFunctionBody(named functionName: String, from source: String) throws -> String {
        guard let signatureRange = source.range(of: "private func \(functionName)") else {
            XCTFail("Missing function \(functionName)")
            return ""
        }
        return try extractBlock(startingAt: "{", in: String(source[signatureRange.lowerBound...]))
    }

    private static func extractBlock(startingAt marker: String, in source: String) throws -> String {
        guard let markerRange = source.range(of: marker),
              let openBraceIndex = source[markerRange.lowerBound...].firstIndex(of: "{") else {
            XCTFail("Missing block marker \(marker)")
            return ""
        }

        var depth = 0
        var cursor = openBraceIndex
        while cursor < source.endIndex {
            let char = source[cursor]
            if char == "{" { depth += 1 }
            if char == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[openBraceIndex...cursor])
                }
            }
            cursor = source.index(after: cursor)
        }

        XCTFail("Unterminated block for marker \(marker)")
        return ""
    }

    private static func readSchedulingSource(named filename: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Scheduling")
            .appendingPathComponent(filename)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
