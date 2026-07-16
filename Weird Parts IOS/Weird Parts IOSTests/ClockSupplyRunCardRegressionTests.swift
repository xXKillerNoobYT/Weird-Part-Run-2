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
        XCTAssertTrue(
            card.contains("TimelineView(.periodic(from: .now, by: 1))"),
            "The active card must own a foreground timeline so its duration keeps advancing after the state-picker sheet dismisses."
        )
        XCTAssertTrue(card.contains("formatDuration(max(0, context.date.timeIntervalSince(startedAt)))"))
        XCTAssertFalse(
            source.contains("@State private var supplyRunElapsedText"),
            "Supply Run duration must not depend on a manually managed timer state that can be invalidated by sheet lifecycle events."
        )
        XCTAssertTrue(card.contains("You stay clocked in and billable while this supply run is active."))
        XCTAssertTrue(card.contains(".accessibilityElement(children: .combine)"))
        XCTAssertTrue(card.contains(".accessibilityLabel("))
        XCTAssertTrue(
            card.contains(".dynamicTypeSize(...DynamicTypeSize.xxxLarge)"),
            "The compact evidence card must stay fully visible at AX5 instead of growing beyond the phone viewport."
        )
        XCTAssertEqual(
            Self.occurrenceCount(of: ".accessibilityIdentifier(\"clock-active-supply-run-card\")", in: source),
            1,
            "The canonical card must expose exactly one stable accessibility identifier."
        )
    }

    func testClockAX5LayoutStacksActionsAndReservesBottomChromeClearance() throws {
        let source = try Self.readClockSource()
        let section = try Self.section(
            named: "private func clockedInSection",
            in: source,
            endingBefore: "// MARK: - Status Helpers"
        )

        XCTAssertTrue(source.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
        XCTAssertTrue(section.contains("AnyLayout(VStackLayout(spacing: 12))"))
        XCTAssertTrue(section.contains("AnyLayout(HStackLayout(spacing: 12))"))
        XCTAssertGreaterThanOrEqual(
            Self.occurrenceCount(of: ".frame(maxWidth: .infinity, minHeight: 44)", in: section),
            4,
            "Clock actions must retain explicit 44pt minimum targets after AX layout changes."
        )
        XCTAssertTrue(
            source.contains(".frame(height: dynamicTypeSize.isAccessibilitySize ? 104 : 76)"),
            "Clock scroll content must clear the floating assistant and persistent tab bar."
        )
    }

    func testAX5NavigationChromeDoesNotExpandAcrossClockContent() throws {
        let source = try Self.readMainViewSource()
        let assistant = try Self.section(
            named: "private func aiFloatingButton",
            in: source,
            endingBefore: "// MARK: - More Tab"
        )
        let chip = try Self.section(
            named: "private func subTabChip",
            in: source,
            endingBefore: "\n}"
        )

        XCTAssertFalse(
            assistant.contains(".dsMinTapTarget()"),
            "The fixed 52pt assistant must not scale its hit frame over card copy at AX5."
        )
        XCTAssertTrue(assistant.contains(".frame(width: 52, height: 52)"))
        XCTAssertTrue(
            chip.contains(".dynamicTypeSize(...DynamicTypeSize.large)"),
            "Sub-tab visuals must remain compact enough to avoid covering adjacent tabs at AX5."
        )
        XCTAssertTrue(chip.contains(".frame(minWidth: 44, minHeight: 44)"))
        XCTAssertTrue(source.contains("!dynamicTypeSize.isAccessibilitySize"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"moreAIAssistantButton\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"sidebarAIAssistantButton\")"))
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

    private static func readMainViewSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Navigation")
            .appendingPathComponent("IOSMainView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
