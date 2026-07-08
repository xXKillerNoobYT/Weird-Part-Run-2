import XCTest

final class PanelQualityInstructionBannerRegressionTests: XCTestCase {
    func testSharedInstructionBannerPinsPanelQualityContract() throws {
        let source = try Self.readDesignSystemSource(named: "CraftKit.swift")

        XCTAssertTrue(source.contains("struct PanelQualityInstructionBanner"))
        XCTAssertTrue(
            source.contains("minHeight: 44"),
            "Instruction banners should keep the Panel Schedule Builder tap-target floor when reused on modal/review flows."
        )
        XCTAssertTrue(
            source.contains("accessibilityIdentifier: String") && source.contains(".accessibilityIdentifier(accessibilityIdentifier)"),
            "Instruction banners need stable identifiers so adoption can be verified without copy-sensitive UI tests."
        )
        XCTAssertTrue(
            source.contains(".accessibilityLabel(message)"),
            "Instruction banners must expose the same guidance to VoiceOver users."
        )
    }

    func testPanelScheduleMoveModeUsesSharedInstructionBanner() throws {
        let source = try Self.readNotebookSource(named: "PanelScheduleBuilder.swift")

        XCTAssertTrue(source.contains("PanelQualityInstructionBanner("))
        XCTAssertTrue(source.contains("panelScheduleMoveModeBanner"))
    }

    func testSyncConflictReviewImportsInstructionBannerWithoutDowngradingChoiceFlow() throws {
        let source = try Self.readSyncSource(named: "SyncConflictReviewPage.swift")

        XCTAssertTrue(source.contains("PanelQualityInstructionBanner("))
        XCTAssertTrue(source.contains("syncConflictReviewInstructionBanner"))
        XCTAssertTrue(
            source.contains("CriticalConflictView(") && source.contains("resolve(conflict, keepLocal: true)") && source.contains("resolve(conflict, keepLocal: false)"),
            "Sync conflict review must keep the existing critical choose-local/choose-remote flow; the imported banner is guidance, not a downgrade to accept-only review."
        )
        XCTAssertTrue(
            source.contains(".dsMinTapTarget()"),
            "Conflict action buttons should keep the shared 44pt minimum target rather than reverting to compact controls."
        )
    }

    private static func projectRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS project directory
            .appendingPathComponent("Weird Parts IOS")
    }

    private static func readDesignSystemSource(named filename: String) throws -> String {
        try String(
            contentsOf: projectRoot()
                .appendingPathComponent("DesignSystem")
                .appendingPathComponent("Components")
                .appendingPathComponent(filename),
            encoding: .utf8
        )
    }

    private static func readNotebookSource(named filename: String) throws -> String {
        try String(
            contentsOf: projectRoot()
                .appendingPathComponent("Features")
                .appendingPathComponent("Notebooks")
                .appendingPathComponent(filename),
            encoding: .utf8
        )
    }

    private static func readSyncSource(named filename: String) throws -> String {
        try String(
            contentsOf: projectRoot()
                .appendingPathComponent("Sync")
                .appendingPathComponent(filename),
            encoding: .utf8
        )
    }
}
