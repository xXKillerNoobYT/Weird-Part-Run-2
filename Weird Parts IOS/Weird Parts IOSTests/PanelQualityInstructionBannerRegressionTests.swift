import GRDB
import WiredPartCore
import XCTest
@testable import Weird_Parts

final class PanelQualityInstructionBannerRegressionTests: XCTestCase {
    func testSharedInstructionBannerPinsPanelQualityContract() throws {
        let source = try Self.readDesignSystemSource(named: "CraftKit.swift")

        XCTAssertTrue(source.contains("struct PanelQualityInstructionBanner"))
        XCTAssertTrue(
            source.contains(".dsMinTapTarget()"),
            "Instruction banners should use the shared, Catalyst-compensated 44pt accessibility-frame floor."
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
            source.contains("CriticalConflictView(")
                && source.contains("requestCriticalResolution(conflict, keepLocal: true)")
                && source.contains("requestCriticalResolution(conflict, keepLocal: false)"),
            "Sync conflict review must keep the existing critical choose-local/choose-remote flow; the imported banner is guidance, not a downgrade to accept-only review."
        )
        XCTAssertTrue(
            source.contains("resolveText(conflict, selectedValue: selectedValue)"),
            "Hard-conflict callbacks must persist the exact AI/device/manual String instead of discarding it and marking review-only."
        )
        XCTAssertFalse(
            source.contains("AIConflictResolutionView(resolution: resolution) { _ in"),
            "The hard-conflict callback must not discard the selected resolution String."
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
        XCTAssertTrue(
            choiceSource.contains("Text(\"Use This\")\n                            .dsMinTapTarget()"),
            "Catalyst needs the 44pt modifier inside the Button label so the measured frame remains natively actionable."
        )
        XCTAssertGreaterThanOrEqual(
            choiceSource.components(separatedBy: ".overlay {").count - 1,
            2,
            "Both Catalyst choices need an idempotent pointer overlay across the full measured button target."
        )
        XCTAssertGreaterThanOrEqual(
            choiceSource.components(separatedBy: ".accessibilityHidden(true)").count - 1,
            2,
            "Pointer overlays must stay hidden from VoiceOver so each choice remains one focus stop."
        )
        XCTAssertGreaterThanOrEqual(
            choiceSource.components(separatedBy: "#if targetEnvironment(macCatalyst)").count - 1,
            2,
            "Pointer activation overlays must compile only for Catalyst so iOS keeps standard Button touch handling."
        )
        XCTAssertGreaterThanOrEqual(
            choiceSource.components(separatedBy: ".accessibilityAction").count - 1,
            2,
            "Both choices need an explicit default VoiceOver action that presents the same confirmation."
        )
        XCTAssertTrue(
            source.contains("@State private var activeAlert")
                && source.contains("case critical(PendingCriticalResolution)")
                && source.contains("\"Confirm Critical Write Decision\""),
            "The stable review-page scope must own the single Catalyst alert presenter."
        )
        XCTAssertFalse(
            choiceSource.contains("@State private var pendingResolution")
                || choiceSource.contains("\"Confirm Critical Write Decision\""),
            "The recyclable List-row child must not own the Catalyst confirmation presenter."
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

    @MainActor
    func testAcceptAllLeavesHumanRequiredConflictsPendingInDatabase() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let manager = IOSSyncManager()
        manager.configure(db: db, settingsService: SettingsService(db: db))

        try insertConflict(db: db, fieldName: "name", localValue: "Local", remoteValue: "Remote")
        try insertConflict(db: db, fieldName: "description", localValue: "Local notes", remoteValue: "Remote notes")
        try insertConflict(db: db, fieldName: "company_markup_percent", localValue: "18", remoteValue: "24")

        XCTAssertTrue(manager.markAutoResolvableConflictsReviewed())

        let pending = try ConflictResolver.getUnreviewedConflicts(db: db)
        XCTAssertEqual(Set(pending.map(\.fieldName)), ["description", "company_markup_percent"])
        XCTAssertEqual(manager.unreviewedConflictCount, 2)
    }

    @MainActor
    func testEveryPersistedCriticalPartsFieldClassifiesCriticalAndResolvesEitherSide() throws {
        let fields = [
            "company_cost_price",
            "company_markup_percent",
            "min_stock_level",
            "target_stock_level",
            "max_stock_level",
        ]

        for field in fields {
            for keepLocal in [true, false] {
                let db = try AppDatabase.openInMemoryDatabase()
                try AppCore.seedUITestingFixtures(db: db, authService: AuthService(db: db))
                let recordId = try XCTUnwrap(db.writer.read { dbConn in
                    try Int64.fetchOne(dbConn, sql: "SELECT id FROM parts ORDER BY id LIMIT 1")
                })
                // Conflict rows are recorded after LWW has already written the
                // winner. Seed that invariant so keepRemote proves the no-op
                // winner path while keepLocal proves the write-back path.
                try db.writer.write { dbConn in
                    try dbConn.execute(
                        sql: "UPDATE parts SET [\(field)] = 22 WHERE id = ?",
                        arguments: [recordId]
                    )
                }
                let insertedConflictId = try insertConflict(
                    db: db,
                    recordId: recordId,
                    fieldName: field,
                    localValue: "11",
                    remoteValue: "22"
                )
                let conflict = try XCTUnwrap(
                    ConflictResolver.getUnreviewedConflicts(db: db).first { $0.id == insertedConflictId }
                )
                guard case .critical = SyncConflictClassifier.classify(conflict) else {
                    return XCTFail("Expected persisted Parts field \(field) to require an explicit critical choice")
                }

                let manager = IOSSyncManager()
                manager.configure(db: db, settingsService: SettingsService(db: db))
                XCTAssertTrue(
                    manager.resolveConflict(conflict, keepLocal: keepLocal),
                    "Expected \(field) to retain the \(keepLocal ? "local" : "remote") action path"
                )

                let storedValue = try db.writer.read { dbConn in
                    try Double.fetchOne(
                        dbConn,
                        sql: "SELECT [\(field)] FROM parts WHERE id = ?",
                        arguments: [recordId]
                    )
                }
                XCTAssertEqual(storedValue, keepLocal ? 11 : 22, "Wrong chosen value persisted for \(field)")
                XCTAssertFalse(try ConflictResolver.getUnreviewedConflicts(db: db).contains { $0.id == conflict.id })
            }
        }
    }

    func testUITestBootstrapGuardsFixturePartLookupAndScreenshotButtonsMatchLabelOrIdentifier() throws {
        let appCoreSource = try Self.readAppSource(named: "AppCore.swift")
        let uiTestSource = try Self.readUITestSource(named: "ConflictScreenshotCaptureUITests.swift")

        XCTAssertTrue(
            appCoreSource.contains("case fixturePartMissing(String)") &&
                appCoreSource.contains("throw UITestBootstrapError.fixturePartMissing(\"UITEST-QA-CONDUIT\")"),
            "UI-test fixture seeding should fail with a controlled bootstrap error instead of force-unwrapping a missing part id."
        )
        XCTAssertTrue(
            appCoreSource.contains("code = 'UITEST-QA-CONDUIT' AND is_active = 1 AND deleted_at IS NULL"),
            "The UI-test fixture lookup must reject both inactive and soft-deleted parts."
        )
        XCTAssertTrue(
            appCoreSource.contains("guard let conflictPartId = try Int64.fetchOne"),
            "The UITEST-QA-CONDUIT lookup must use a guarded optional fetch."
        )
        XCTAssertTrue(
            uiTestSource.contains("identifier == %@ OR label == %@"),
            "Critical confirmation buttons should be discoverable by either accessibility identifier or visible label."
        )
    }

    @discardableResult
    private func insertConflict(
        db: AppDatabase,
        recordId: Int64 = 1,
        fieldName: String,
        localValue: String,
        remoteValue: String
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO _conflict_log (
                        table_name, record_id, field_name, local_value, remote_value,
                        winner, local_device, remote_device, local_ts, remote_ts, resolved_at
                    ) VALUES (?, ?, ?, ?, ?, 'remote', 'local-device', 'remote-device', ?, ?, ?)
                    """,
                arguments: [
                    "parts", String(recordId), fieldName, localValue, remoteValue,
                    "2026-07-14T09:00:00Z", "2026-07-14T10:00:00Z", "2026-07-14T10:00:00Z",
                ]
            )
            return dbConn.lastInsertedRowID
        }
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

    private static func readAppSource(named filename: String) throws -> String {
        try String(
            contentsOf: projectRoot()
                .appendingPathComponent("App")
                .appendingPathComponent(filename),
            encoding: .utf8
        )
    }

    private static func readUITestSource(named filename: String) throws -> String {
        try String(
            contentsOf: projectRoot(file: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Weird Parts IOSUITests")
                .appendingPathComponent(filename),
            encoding: .utf8
        )
    }
}
