import XCTest

/// Regression coverage for GitHub #1029 / WEI-3751 / WEI-3752.
///
/// Field workflow rows can group static summary text for VoiceOver, but any
/// visible workflow action buttons must remain real, separately discoverable
/// controls. Do not put `.accessibilityElement(children: .combine)` on parent
/// rows that also contain `Button`s for these field-critical actions.
final class FieldWorkflowActionButtonAccessibilityTests: XCTestCase {
    func testRecoveredClockBannerKeepsTimerActionsIndependent() throws {
        let source = try Self.readJobSource("IOSClockPage.swift")
        let section = try Self.section(
            named: "private func clockRecoverySection",
            in: source,
            endingBefore: "private func activeBreakTitle"
        )

        XCTAssertFalse(
            section.contains(".accessibilityElement(children: .combine)\n            }"),
            "The recovered timer banner must not combine the parent container around Continue Timer and Clock Out buttons."
        )
        XCTAssertTrue(section.contains(".accessibilityIdentifier(\"clock-recovered-continue-timer-button\")"))
        XCTAssertTrue(section.contains(".accessibilityIdentifier(\"clock-recovered-clock-out-button\")"))
        XCTAssertTrue(section.contains(".accessibilityHint(\"Dismisses the recovered timer banner"))
        XCTAssertTrue(section.contains(".accessibilityHint(\"Opens confirmation to clock out"))
    }

    func testJobMaterialRowsKeepUseReturnCorrectButtonsIndependent() throws {
        let source = try Self.readJobSource("IOSJobDetailPage.swift")
        let readyRow = try Self.section(
            named: "private func readyMaterialRow",
            in: source,
            endingBefore: "private var usedMaterialsSegment"
        )
        let usedRow = try Self.section(
            named: "private func usedMaterialRow",
            in: source,
            endingBefore: "private var returnsMaterialsSegment"
        )

        XCTAssertFalse(
            readyRow.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(".accessibilityElement(children: .combine)"),
            "The ready material row parent must not combine Use and Return buttons."
        )
        XCTAssertFalse(
            usedRow.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(".accessibilityElement(children: .combine)"),
            "The used material row parent must not combine Return and Correct buttons."
        )
        XCTAssertTrue(readyRow.contains(".accessibilityIdentifier(\"job-ready-material-use-button-\\(material.id)\")"))
        XCTAssertTrue(readyRow.contains(".accessibilityIdentifier(\"job-ready-material-return-button-\\(material.id)\")"))
        XCTAssertTrue(usedRow.contains(".accessibilityIdentifier(\"job-used-material-return-button-\\(part.id)\")"))
        XCTAssertTrue(usedRow.contains(".accessibilityIdentifier(\"job-used-material-correct-button-\\(part.id)\")"))
        XCTAssertTrue(readyRow.contains(".accessibilityElement(children: .combine)"), "Static ready material summary text can still be grouped separately.")
        XCTAssertTrue(usedRow.contains(".accessibilityElement(children: .combine)"), "Static used material summary text can still be grouped separately.")
    }

    func testMisplacedPartSelectionSummariesKeepChangeButtonsIndependent() throws {
        let source = try Self.readWarehouseSource("IOSAuditPage.swift")
        let partSummary = try Self.section(
            named: "private var selectedPartSummary",
            in: source,
            endingBefore: "private var selectedAreaSummary"
        )
        let areaSummary = try Self.section(
            named: "private var selectedAreaSummary",
            in: source,
            endingBefore: "private var partResultsView"
        )

        XCTAssertFalse(
            partSummary.contains("Button(\"Change\") {\n                        self.selectedPart = nil\n                        homeOptions = []\n                        homeAreaId = nil\n                    }\n                }\n                .accessibilityElement(children: .combine)"),
            "The selected part HStack must not combine the Change button into a static parent row."
        )
        XCTAssertFalse(
            areaSummary.contains("Button(\"Change\") {\n                    self.selectedArea = nil\n                }\n            }\n            .accessibilityElement(children: .combine)"),
            "The selected area HStack must not combine the Change button into a static parent row."
        )
        XCTAssertTrue(partSummary.contains(".accessibilityIdentifier(\"misplaced-selected-part-change-button\")"))
        XCTAssertTrue(areaSummary.contains(".accessibilityIdentifier(\"misplaced-selected-area-change-button\")"))
        XCTAssertTrue(partSummary.contains(".accessibilityLabel(\"Change selected part\")"))
        XCTAssertTrue(areaSummary.contains(".accessibilityLabel(\"Change selected area\")"))
    }

    private static func section(named startMarker: String, in source: String, endingBefore endMarker: String) throws -> String {
        guard let start = source.range(of: startMarker) else {
            XCTFail("Missing section starting with \(startMarker)")
            return source
        }
        let afterStart = source[start.lowerBound...]
        guard let end = afterStart.range(of: endMarker) else {
            XCTFail("Missing section ending before \(endMarker)")
            return String(afterStart)
        }
        return String(afterStart[..<end.lowerBound])
    }

    private static func readJobSource(_ fileName: String, file: StaticString = #filePath) throws -> String {
        try readFeatureSource(fileName, folder: "Jobs", file: file)
    }

    private static func readWarehouseSource(_ fileName: String, file: StaticString = #filePath) throws -> String {
        try readFeatureSource(fileName, folder: "Warehouse", file: file)
    }

    private static func readFeatureSource(
        _ fileName: String,
        folder: String,
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent(folder)
            .appendingPathComponent(fileName)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
