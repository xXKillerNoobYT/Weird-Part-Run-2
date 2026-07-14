import GRDB
import WiredPartCore
import XCTest
@testable import Weird_Parts

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
        let constrainedText = try XCTUnwrap(source.range(of: ".layoutPriority(1)"))
        let padding = try XCTUnwrap(source.range(of: ".padding(.horizontal, DS.Space.sm)"))
        XCTAssertTrue(source.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertLessThan(
            constrainedText.lowerBound,
            padding.lowerBound,
            "Compact banners must constrain the wrapping text before adding outer padding so their edges do not clip."
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

        let choiceSource = try Self.readSyncSource(named: "AIConflictResolutionView.swift")
        XCTAssertTrue(choiceSource.contains("syncConflictUseLocalValue"))
        XCTAssertTrue(choiceSource.contains("syncConflictUseRemoteValue"))
        XCTAssertGreaterThanOrEqual(
            choiceSource.components(separatedBy: ".dsMinTapTarget()").count - 1,
            2,
            "Both critical local/remote choice controls need 44x44pt hit regions."
        )
    }

    func testUITestingCriticalCostConflictResolvesEitherSideAgainstItsLiveFixtureRow() throws {
        func seededDatabase() throws -> AppDatabase {
            let db = try AppDatabase.openInMemoryDatabase()
            try AppCore.seedUITestingFixtures(db: db, authService: AuthService(db: db))
            return db
        }

        let localDB = try seededDatabase()
        let localConflict = try XCTUnwrap(
            ConflictResolver.getUnreviewedConflicts(db: localDB)
                .first { $0.fieldName == "company_cost_price" }
        )
        let localRecordId = try XCTUnwrap(Int64(localConflict.recordId))
        try ConflictResolver.applyConflictResolution(db: localDB, conflict: localConflict, choice: .keepLocal)
        let localCost = try localDB.writer.read { dbConn in
            try Double.fetchOne(dbConn, sql: "SELECT company_cost_price FROM parts WHERE id = ?", arguments: [localRecordId])
        }
        XCTAssertEqual(localCost, 17.45)
        XCTAssertFalse(try ConflictResolver.getUnreviewedConflicts(db: localDB).contains { $0.id == localConflict.id })

        let remoteDB = try seededDatabase()
        let remoteConflict = try XCTUnwrap(
            ConflictResolver.getUnreviewedConflicts(db: remoteDB)
                .first { $0.fieldName == "company_cost_price" }
        )
        let remoteRecordId = try XCTUnwrap(Int64(remoteConflict.recordId))
        try ConflictResolver.applyConflictResolution(db: remoteDB, conflict: remoteConflict, choice: .keepRemote)
        let remoteCost = try remoteDB.writer.read { dbConn in
            try Double.fetchOne(dbConn, sql: "SELECT company_cost_price FROM parts WHERE id = ?", arguments: [remoteRecordId])
        }
        XCTAssertEqual(remoteCost, 21.90)
        XCTAssertFalse(try ConflictResolver.getUnreviewedConflicts(db: remoteDB).contains { $0.id == remoteConflict.id })
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
