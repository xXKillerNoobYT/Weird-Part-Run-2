import Foundation
import XCTest

/// Regression coverage for GitHub #1450 / Paperclip WEI-4906.
///
/// The Clock page previously rendered three overlapping active Supply Run cards.
/// These source guards keep the SwiftUI render path and stable accessibility
/// identifier singular until the page has an injectable UI state fixture.
final class ClockSupplyRunCardRegressionTests: XCTestCase {
    func testClockedInSectionHasOneActiveSupplyRunCardRenderPath() throws {
        let source = try Self.readClockSource()
        let section = try Self.section(
            named: "private func clockedInSection",
            in: source,
            endingBefore: "// MARK: - Status Helpers"
        )

        XCTAssertEqual(
            Self.occurrenceCount(of: "activeSupplyRunCard(startedAt:", in: section),
            1,
            "An active supply run must render exactly one evidence card."
        )
        XCTAssertTrue(
            section.contains("if let supplyRunStart = activeSupplyRunStartDate, activityStatus == \"supply_run\""),
            "The card must require both an active marker timestamp and supply-run state so it disappears after the run ends."
        )
        XCTAssertFalse(section.contains("supplyRunStatusCard("), "The superseded status card render path must stay removed.")
        XCTAssertFalse(section.contains("activeSupplyRunCard(start:"), "The superseded unlabeled-parameter card render path must stay removed.")
    }

    func testCanonicalCardPreservesEvidenceAndOneStableIdentifier() throws {
        let source = try Self.readClockSource()
        let card = try Self.section(
            named: "private func activeSupplyRunCard(startedAt:",
            in: source,
            endingBefore: "private func activeBreakBanner"
        )

        XCTAssertTrue(card.contains("Text(\"Started\")"))
        XCTAssertTrue(card.contains("Text(\"Duration\")"))
        XCTAssertTrue(card.contains("Text(supplyRunElapsedText)"), "Supply Run duration must remain live.")
        XCTAssertTrue(card.contains("You stay clocked in and billable while this supply run is active."))
        XCTAssertTrue(card.contains(".accessibilityElement(children: .combine)"))
        XCTAssertTrue(card.contains(".accessibilityLabel("))
        XCTAssertEqual(
            Self.occurrenceCount(of: ".accessibilityIdentifier(\"clock-active-supply-run-card\")", in: source),
            1,
            "The canonical card must expose exactly one stable accessibility identifier."
        )
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

    private static func occurrenceCount(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
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
