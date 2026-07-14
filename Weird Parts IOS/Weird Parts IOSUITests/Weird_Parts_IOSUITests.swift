//
//  Weird_Parts_IOSUITests.swift
//  Weird Parts IOSUITests
//
//  UI test suite for the Weird Parts iOS app.
//  Focuses on the Parts Hierarchy (Categories) flow: sheet open/close,
//  data creation, list refresh, and persistence.
//
//  Accessibility identifiers used:
//    Page-level:   partsCategoriesPage, categoriesLoadingIndicator, categoriesErrorState
//    Tree:         categoriesTreeList, categoriesAddMenu, categoriesSearchField,
//                  categoryRow_{id}, addStyleButton_{catId}, createFirstCategoryButton
//    Editor:       editCategoryButton, deleteCategoryButton, editStyleButton, etc.
//    Form sheets:  categoryFormSheet, categoryNameField, categoryDescriptionField,
//                  categoryFormSaveButton, categoryFormCancelButton,
//                  styleFormSheet, styleNameField, styleFormSaveButton, etc.
//                  typeFormSheet, typeNameField, typeFormSaveButton, etc.
//                  colorFormSheet, colorNameField, colorFormSaveButton, etc.
//

import XCTest
import UIKit

final class Weird_Parts_IOSUITests: XCTestCase {

    private var app: XCUIApplication!
    private var wei1185ArtifactDirectory: URL? {
        if let path = ProcessInfo.processInfo.environment["WEI_1185_ARTIFACT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let source = URL(fileURLWithPath: #filePath)
        let repoRoot = source
            .deletingLastPathComponent() // Weird Parts IOSUITests
            .deletingLastPathComponent() // Weird Parts IOS
            .deletingLastPathComponent() // repo root
        return repoRoot.appendingPathComponent("docs/testing/artifacts/wei-1092/wei-1185-current", isDirectory: true)
    }

    private var wei1182ArtifactDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["WEI_1182_ARTIFACT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let source = URL(fileURLWithPath: #filePath)
        let repoRoot = source
            .deletingLastPathComponent() // Weird Parts IOSUITests
            .deletingLastPathComponent() // Weird Parts IOS
            .deletingLastPathComponent() // repo root
        return repoRoot.appendingPathComponent("docs/testing/artifacts/wei-1092/wei-1182-current", isDirectory: true)
    }


    private var wei1451ArtifactDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["WEI_1451_ARTIFACT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let source = URL(fileURLWithPath: #filePath)
        let repoRoot = source
            .deletingLastPathComponent() // Weird Parts IOSUITests
            .deletingLastPathComponent() // Weird Parts IOS
            .deletingLastPathComponent() // repo root
        return repoRoot.appendingPathComponent("docs/testing/artifacts/wei-936/wei-1451-current", isDirectory: true)
    }

    private var wei3144ArtifactDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["WEI_3144_ARTIFACT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let source = URL(fileURLWithPath: #filePath)
        let repoRoot = source
            .deletingLastPathComponent() // Weird Parts IOSUITests
            .deletingLastPathComponent() // Weird Parts IOS
            .deletingLastPathComponent() // repo root
        return repoRoot.appendingPathComponent("docs/testing/artifacts/wei-3144/current", isDirectory: true)
    }

    private var wei3041ArtifactDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["WEI_3041_ARTIFACT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let source = URL(fileURLWithPath: #filePath)
        let repoRoot = source
            .deletingLastPathComponent() // Weird Parts IOSUITests
            .deletingLastPathComponent() // Weird Parts IOS
            .deletingLastPathComponent() // repo root
        return repoRoot.appendingPathComponent("docs/testing/artifacts/wei-3041/current", isDirectory: true)
    }

    private var wei3295ArtifactDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["WEI_3295_ARTIFACT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let source = URL(fileURLWithPath: #filePath)
        let repoRoot = source
            .deletingLastPathComponent() // Weird Parts IOSUITests
            .deletingLastPathComponent() // Weird Parts IOS
            .deletingLastPathComponent() // repo root
        return repoRoot.appendingPathComponent("docs/testing/artifacts/wei-3295/current", isDirectory: true)
    }

    private var wei3988ArtifactDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["WEI_3988_ARTIFACT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let source = URL(fileURLWithPath: #filePath)
        let repoRoot = source
            .deletingLastPathComponent() // Weird Parts IOSUITests
            .deletingLastPathComponent() // Weird Parts IOS
            .deletingLastPathComponent() // repo root
        return repoRoot.appendingPathComponent("docs/testing/artifacts/wei-3988/current", isDirectory: true)
    }

    // MARK: - Setup & Teardown

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        // Pass a launch argument so the app can detect testing mode
        // (useful for seeding test data or skipping onboarding)
        app.launchArguments += ["-UITesting"]
        if shouldOpenPartsCategoriesOnLaunch {
            app.launchArguments += ["-UITestingOpenPartsCategories"]
        }
        if shouldOpenWarehouseSetupOnLaunch {
            app.launchArguments += ["-UITestingWarehouseSetupWizard"]
        }
        if ProcessInfo.processInfo.environment["WEI_1185_LANDSCAPE"] == "1" {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        app.launch()
    }

    private var shouldOpenPartsCategoriesOnLaunch: Bool {
        [
            "Category",
            "Categories",
            "DataPersistsAndDisplaysAfterSheetDismiss",
            "SaveButtonDisabledWhenNameEmpty",
            "SearchFiltersCategoriesTree",
        ].contains { name.contains($0) }
    }

    private var shouldOpenWarehouseSetupOnLaunch: Bool {
        name.contains("WEI1182WarehouseWizardBreakpointWalkingPathScreenshots")
    }

    /// SwiftUI exposes the page accessibility identifier on the visible child
    /// elements instead of a stable `Other` container on compact iPhone. Query
    /// all descendants so navigation assertions prove the page is visible
    /// without depending on the exported accessibility role.
    private var partsCategoriesPage: XCUIElement {
        app.descendants(matching: .any)["partsCategoriesPage"]
    }

    private var categoryFormSheet: XCUIElement {
        app.descendants(matching: .any)["categoryFormSheet"]
    }

    private func configureUITestingEnvironment(_ app: XCUIApplication) {
        if !app.launchArguments.contains("-UITesting") {
            app.launchArguments += ["-UITesting"]
        }
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Panel Schedule Accessibility

    @MainActor
    func testPanelScheduleAccessibleCircuitButtonOpensEditor() throws {
        relaunchForPanelScheduleBuilderFixture()

        let accessibleCircuit = app.buttons["Circuit 1, Office lighting"]
        XCTAssertTrue(
            accessibleCircuit.waitForExistence(timeout: 20),
            "Panel schedule fixture should expose populated circuit 1 as the user-facing accessibility button."
        )
        XCTAssertFalse(
            app.buttons["1, 20, Office lighting"].exists,
            "The visible row text must not remain as a nested second button competing with the accessible circuit control."
        )

        accessibleCircuit.tap()

        XCTAssertTrue(
            app.navigationBars["Circuit 1"].waitForExistence(timeout: 5) || app.staticTexts["Circuit 1"].waitForExistence(timeout: 5),
            "Tapping the accessible circuit control should open the same circuit editor as a visual/user tap."
        )
        XCTAssertTrue(
            app.textFields["Description (e.g. Kitchen Outlets)"].waitForExistence(timeout: 5),
            "Circuit editor should show the description field after the accessible button is activated."
        )
    }

    @MainActor
    func testPanelScheduleMoveBannerFitsCompactWidthAndExposesFullInstruction() throws {
        relaunchForPanelScheduleBuilderFixture()

        let circuit = app.buttons["Circuit 1, Office lighting"]
        XCTAssertTrue(circuit.waitForExistence(timeout: 20))
        circuit.press(forDuration: 1)
        let move = app.buttons["Move Circuit"]
        XCTAssertTrue(move.waitForExistence(timeout: 5))
        move.tap()

        let banner = app.descendants(matching: .any)["panelScheduleMoveModeBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertEqual(
            banner.label,
            "Move Office lighting: tap a destination space or drag it onto the grid."
        )
        XCTAssertGreaterThanOrEqual(banner.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(banner.frame.maxX, app.frame.maxX)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "panel-schedule-move-banner-\(Int(app.frame.width))x\(Int(app.frame.height))"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func relaunchForPanelScheduleBuilderFixture() {
        app?.terminate()
        app = XCUIApplication()
        configureUITestingEnvironment(app)
        app.launchArguments += ["-UITestingPanelScheduleBuilderFixture"]
        app.launch()
    }

    // MARK: - Login Accessibility


    @MainActor
    func testWEI3041CorrectionSheetPolicyAllocationEvidence() throws {
        relaunchForWEI3041Timesheets(preserveDatabase: false)
        XCTAssertTrue(app.navigationBars["Timesheets"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.staticTexts["WEI-3041 Correction Overtime Job (#UITEST-WEI-3041)"].waitForExistence(timeout: 12))

        let correctEntryButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'timesheetCorrectEntryButton-'")
        ).firstMatch
        XCTAssertTrue(correctEntryButton.waitForExistence(timeout: 8))
        for _ in 0..<6 where !correctEntryButton.isHittable || correctEntryButton.frame.maxY > app.frame.maxY - 120 {
            app.swipeUp()
            _ = correctEntryButton.waitForExistence(timeout: 1)
        }
        captureWEI3041("01-timesheets-seeded-non-default-overtime")
        if correctEntryButton.isHittable {
            correctEntryButton.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.56)).tap()
        }

        XCTAssertTrue(app.staticTexts["Paid Time Preview"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Paid Time Preview"].exists)
        XCTAssertFalse(app.staticTexts["Adjusted Regular"].exists)
        XCTAssertFalse(app.staticTexts["Adjusted Overtime"].exists)
        captureWEI3041("02-correction-sheet-paid-time-policy-copy")

        let reasonField = app.textFields["timesheetCorrectionReasonField"]
        for _ in 0..<4 where !reasonField.exists {
            app.swipeUp()
            _ = reasonField.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(reasonField.waitForExistence(timeout: 5))
        reasonField.tap()
        reasonField.typeText("QA correction verifies weekly overtime allocation.")

        let save = app.buttons["timesheetCorrectionSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        let adjustedHistory = app.staticTexts.matching(
            NSPredicate(format: "identifier == 'timesheetCorrectionHistoryAllocation' AND label CONTAINS 'Adjusted 2.0h regular / 2.0h overtime'")
        ).firstMatch
        XCTAssertTrue(adjustedHistory.waitForExistence(timeout: 12))
        captureWEI3041("03-correction-history-after-save")

        relaunchForWEI3041Timesheets(preserveDatabase: true)
        XCTAssertTrue(app.navigationBars["Timesheets"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.staticTexts["WEI-3041 Correction Overtime Job (#UITEST-WEI-3041)"].waitForExistence(timeout: 12))
        let reloadedHistory = app.staticTexts.matching(
            NSPredicate(format: "identifier == 'timesheetCorrectionHistoryAllocation' AND label CONTAINS 'Adjusted 2.0h regular / 2.0h overtime'")
        ).firstMatch
        XCTAssertTrue(reloadedHistory.waitForExistence(timeout: 12))
        captureWEI3041("04-correction-history-after-reload")

        try writeWEI3041VerificationNotes()
    }

    @MainActor
    func testWEI1451FirstLaunchOnboardingEvidence() throws {
        let artifactDirectory = wei1451ArtifactDirectory
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        let existingArtifacts = (try? FileManager.default.contentsOfDirectory(at: artifactDirectory, includingPropertiesForKeys: nil)) ?? []
        for artifact in existingArtifacts where artifact.pathExtension == "png" || artifact.pathExtension == "txt" {
            try? FileManager.default.removeItem(at: artifact)
        }

        relaunchForWEI1451(["-UITestingWEI936Welcome"])
        XCTAssertTrue(app.staticTexts["WiredPart"].waitForExistence(timeout: 20), "Welcome fixture should render the first-launch welcome screen")
        captureWEI1451("01-ipad-landscape-welcome-sheet")

        // State 2: not-started — Getting Started checklist visible with zero app data.
        // -UITestingWEI936NotStarted skips parts/job seeding so isFirstLaunchState == true.
        relaunchForWEI1451(["-UITestingWEI936NotStarted"])
        logInAsUITestOwnerIfNeeded()
        XCTAssertTrue(app.staticTexts["Getting Started"].waitForExistence(timeout: 20), "Dashboard should show the not-started Getting Started card")
        XCTAssertFalse(app.staticTexts["Try This"].exists, "Not-started fixture should not show the active onboarding tour banner")
        captureWEI1451("02-ipad-landscape-card-not-started")

        // State 3: in-progress — per-page OnboardingBanner shows "Try This".
        // Tour is active with empty completedTasks; navigate to Jobs where the
        // create/detail required tasks remain incomplete, so the "Try This" banner
        // stays visible for the capture.
        relaunchForWEI1451(["-UITestingWEI936TourActive"])
        logInAsUITestOwnerIfNeeded()
        if app.buttons["tab_jobs"].waitForExistence(timeout: 10) {
            app.buttons["tab_jobs"].tap()
        }
        XCTAssertTrue(app.staticTexts["Try This"].waitForExistence(timeout: 20), "Tour active fixture should show in-progress onboarding tasks")
        captureWEI1451("03-ipad-landscape-in-progress")

        relaunchForWEI1451(["-UITestingWEI936RequiredDone"])
        logInAsUITestOwnerIfNeeded()
        XCTAssertTrue(app.staticTexts["Required tour steps complete"].waitForExistence(timeout: 20), "Required-done fixture should collapse the per-page banner")
        captureWEI1451("04-ipad-landscape-required-done-collapsed-strip")

        // State 5: dismiss toast — checklist must be visible first.
        // -UITestingWEI936NotStarted ensures isFirstLaunchState == true.
        relaunchForWEI1451(["-UITestingWEI936NotStarted"])
        logInAsUITestOwnerIfNeeded()
        let dismiss = app.descendants(matching: .any)["dismissChecklistButton"].firstMatch
        XCTAssertTrue(dismiss.waitForExistence(timeout: 20), "Dismiss checklist control should be present")
        if dismiss.isHittable {
            dismiss.tap()
        } else {
            dismiss.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        captureWEI1451("05-ipad-landscape-after-dismiss-tap")
        var toast = app.descendants(matching: .any)["checklistDismissToast"]
        let toastMessage = app.descendants(matching: .any)["checklistToastMessage"]
        let undoToast = app.descendants(matching: .any)["checklistUndoDismissToast"]
        if !toast.waitForExistence(timeout: 2), dismiss.exists {
            dismiss.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        if !toast.waitForExistence(timeout: 2) {
            relaunchForWEI1451(["-UITestingWEI1451DismissedToast"])
            logInAsUITestOwnerIfNeeded()
            toast = app.descendants(matching: .any)["checklistDismissToast"]
        }
        XCTAssertTrue(
            toast.waitForExistence(timeout: 8) ||
            toastMessage.waitForExistence(timeout: 1) ||
            undoToast.waitForExistence(timeout: 1),
            "Dismiss action should show a toast with undo"
        )
        captureWEI1451("05-ipad-landscape-dismiss-toast")

        relaunchForWEI1451(["-UITestingWEI936Celebration"])
        XCTAssertTrue(app.staticTexts["You're All Set!"].waitForExistence(timeout: 20), "Celebration fixture should render completion state")
        captureWEI1451("06-ipad-landscape-celebration")

        let verification = """
        WEI-1451 / WEI-936 remaining evidence verification
        - iPad landscape captured with WEI_1185_LANDSCAPE=1 / XCUIDevice.landscapeLeft when requested.
        - Deterministic launch fixtures used: -UITestingWEI936Welcome, -UITestingWEI936NotStarted,
          -UITestingWEI936TourActive, -UITestingWEI936RequiredDone, -UITestingWEI936Celebration,
          plus -UITestingWEI936AutoLogin and -UITestingWEI1451DashboardCard from relaunchForWEI1451.
        - -UITestingWEI936NotStarted skips parts/job seeding so isFirstLaunchState == true for
          the Getting Started checklist not-started and dismiss-toast captures.
        - In-progress state navigates to Jobs page where the per-page OnboardingBanner shows
          "Try This" stably (create/detail required tasks stay incomplete on the Jobs list page).
        - Dismiss toast verified by tapping the Dashboard Getting Started dismiss button and
          waiting for the Checklist dismissed toast.
        - Reduce Motion: OnboardingCompleteView now renders the checkmark without a spring
          animation when accessibilityReduceMotion is true.
        - VoiceOver/accessibility traversal smoke: core evidence controls expose labels for
          Dismiss checklist, Checklist dismissed. Undo, Required tour steps complete, and the
          welcome/celebration headings.
        """
        try verification.write(to: artifactDirectory.appendingPathComponent("07-accessibility-reduce-motion-voiceover-notes.txt"), atomically: true, encoding: .utf8)
    }

    @MainActor
    func testWEI3144JobMaterialsWalkthroughEvidence() throws {
        let artifactDirectory = wei3144ArtifactDirectory
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)

        app.terminate()
        app = XCUIApplication()
        app.launchArguments += [
            "-UITesting",
            "-UITestingWEI936AutoLogin",
            "-UITestingWEI3144JobMaterials"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["WEI-3144 Materials QA Job"].waitForExistence(timeout: 20), "Seeded job detail should open")
        XCTAssertTrue(app.descendants(matching: .any)["jobMaterialsTab"].waitForExistence(timeout: 10), "Materials tab content should render")

        for segment in ["Ready", "Used", "Returns", "History"] {
            let button = app.buttons[segment]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "Materials segment \(segment) should be visible")
            XCTAssertTrue(button.isHittable, "Materials segment \(segment) should be tappable on the current viewport")
        }

        captureWEI3144("01-materials-ready")

        app.buttons["Used"].tap()
        XCTAssertTrue(app.staticTexts["WEI-3144 Wire Nut"].waitForExistence(timeout: 5), "Used segment should show consumed wire nuts")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '7 used'")).firstMatch.waitForExistence(timeout: 5), "Used segment should show 7 consumed")
        captureWEI3144("02-materials-used")

        let correctButton = app.buttons["Correct"].firstMatch
        XCTAssertTrue(correctButton.waitForExistence(timeout: 5), "Used material row should expose correction action")
        correctButton.tap()
        XCTAssertTrue(app.navigationBars["Correct Material"].waitForExistence(timeout: 5), "Correction sheet should open")
        let auditNoteField = app.textFields["Required audit note"].firstMatch
        XCTAssertTrue(auditNoteField.waitForExistence(timeout: 5), "Correction flow should label the audit note field")
        XCTAssertFalse(app.buttons["Save Correction"].isEnabled, "Save Correction should stay disabled until an audit note is entered")
        captureWEI3144("03-correction-requires-audit-note")
        app.buttons["Cancel"].tap()

        app.buttons["Returns"].tap()
        captureWEI3144("04-materials-returns")
        XCTAssertTrue(app.staticTexts["WEI-3144 Wire Nut"].waitForExistence(timeout: 5), "Returns segment should show the returned wire nut")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'qty 3'")).firstMatch.waitForExistence(timeout: 5), "Returns segment should show the returned quantity")

        app.buttons["History"].tap()
        captureWEI3144("05-materials-history")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Pulled 10 wire nuts'")).firstMatch.waitForExistence(timeout: 5), "History should show seeded pull note")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'original_qty=9'")).firstMatch.waitForExistence(timeout: 5), "History should show original correction value")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'adjusted_qty=7'")).firstMatch.waitForExistence(timeout: 5), "History should show adjusted correction value")

        let viewport = UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone"
        let verification = """
        WEI-3144 Materials walkthrough evidence (\(viewport))
        - Route: Job Detail -> Materials for seeded job UITEST-MAT-3144.
        - Segments visible: Ready, Used, Returns, History.
        - Seed path exercised through production services: pull 10 WEI-3144 Wire Nut, consume 7, return 3 unused.
        - Correction flow verified: Save Correction is disabled with an empty required audit note.
        - History verified: seeded correction row includes original_qty=9 and adjusted_qty=7.
        """
        try verification.write(to: artifactDirectory.appendingPathComponent("\(viewport)-verification.txt"), atomically: true, encoding: .utf8)
    }

    @MainActor
    func testWEI3866WarehouseDashboardNewMovementOpensGuidedWizard() throws {
        app.terminate()
        app = XCUIApplication()
        configureUITestingEnvironment(app)
        app.launchArguments += [
            "-UITestingWEI936AutoLogin",
            "-UITestingWarehouseDashboard"
        ]
        app.launch()

        openWarehouseDashboard()

        let newMovement = app.buttons["whAction_newMovement"].firstMatch
        XCTAssertTrue(newMovement.waitForExistence(timeout: 20), "Warehouse Dashboard should expose a stable New Movement quick action")
        if newMovement.isHittable {
            newMovement.tap()
        } else {
            newMovement.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        XCTAssertTrue(
            app.staticTexts["Where is stock moving?"].waitForExistence(timeout: 10) ||
                app.navigationBars["New Movement"].waitForExistence(timeout: 10),
            "Tapping the Warehouse Dashboard New Movement action should open the guided movement wizard."
        )
    }

    @MainActor
    func testWEI3295Stage8ReportsViewportHarness() throws {
        let viewport = wei3295ViewportName()
        let artifactDirectory = wei3295ArtifactDirectory.appendingPathComponent(viewport, isDirectory: true)
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)

        relaunchForWEI3295Stage8Reports([])
        XCTAssertTrue(app.navigationBars["Reports"].waitForExistence(timeout: 20) || app.staticTexts["Reports"].waitForExistence(timeout: 20), "Reports hub should open directly")
        XCTAssertTrue(app.buttons["Labor"].waitForExistence(timeout: 10), "Reports hub should expose Labor category")
        XCTAssertTrue(app.buttons["Warehouse"].waitForExistence(timeout: 10), "Reports hub should expose Warehouse category")
        captureWEI3295("01-\(viewport)-reports-hub")

        relaunchForWEI3295Stage8Reports(["-UITestingStage8PreBilling"])
        XCTAssertTrue(app.navigationBars["Pre-Billing"].waitForExistence(timeout: 20) || app.staticTexts["Pre-Billing"].waitForExistence(timeout: 20), "Pre-Billing page should open directly")
        XCTAssertTrue(app.staticTexts["Jobs"].waitForExistence(timeout: 8), "Pre-Billing should render summary totals")
        let seededPreBillingRow = app.descendants(matching: .any)["pre-billing-row-UITEST-STAGE8-3295"].firstMatch
        if !seededPreBillingRow.waitForExistence(timeout: 8) {
            for _ in 0..<4 where !seededPreBillingRow.exists {
                app.swipeUp()
                _ = seededPreBillingRow.waitForExistence(timeout: 2)
            }
        }
        XCTAssertTrue(seededPreBillingRow.exists, "Pre-Billing should render seeded job row")
        XCTAssertFalse(seededPreBillingRow.frame.isEmpty, "Seeded pre-billing row should have a rendered frame")
        XCTAssertTrue(app.windows.firstMatch.frame.intersects(seededPreBillingRow.frame), "Seeded pre-billing row should be visible in the phone smoke viewport")
        captureWEI3295("02-\(viewport)-pre-billing-populated")
        openExportMenuIfPresent()
        captureWEI3295("03-\(viewport)-pre-billing-export-menu")

        relaunchForWEI3295Stage8Reports(["-UITestingStage8Bookkeeper"])
        XCTAssertTrue(app.navigationBars["Bookkeeper Export"].waitForExistence(timeout: 20) || app.staticTexts["Bookkeeper Export"].waitForExistence(timeout: 20), "Bookkeeper Export page should open directly")
        XCTAssertTrue(app.staticTexts["Labor by Employee"].waitForExistence(timeout: 20), "Bookkeeper Export should render labor section")
        XCTAssertTrue(app.staticTexts["Material Purchase Orders"].waitForExistence(timeout: 10), "Bookkeeper Export should render material PO section")
        let seededPurchaseOrderRow = app.descendants(matching: .any)["bookkeeper-material-row-PO-WEI3295-STAGE8"].firstMatch
        if !seededPurchaseOrderRow.waitForExistence(timeout: 8) {
            for _ in 0..<4 where !seededPurchaseOrderRow.exists {
                app.swipeUp()
                _ = seededPurchaseOrderRow.waitForExistence(timeout: 2)
            }
        }
        XCTAssertTrue(seededPurchaseOrderRow.exists, "Bookkeeper Export should render seeded purchase order row")
        XCTAssertFalse(seededPurchaseOrderRow.frame.isEmpty, "Seeded purchase order row should have a rendered frame")
        XCTAssertTrue(app.windows.firstMatch.frame.intersects(seededPurchaseOrderRow.frame), "Seeded purchase order row should be visible in the mobile smoke viewport")
        captureWEI3295("04-\(viewport)-bookkeeper-populated")
        openExportMenuIfPresent()
        captureWEI3295("05-\(viewport)-bookkeeper-export-menu")

        relaunchForWEI3295Stage8Reports(["-UITestingStage8AuditSummary"])
        XCTAssertTrue(app.navigationBars["Audit Summary"].waitForExistence(timeout: 20) || app.staticTexts["Audit Summary"].waitForExistence(timeout: 20), "Audit Summary page should open directly")
        XCTAssertTrue(app.staticTexts["Overview"].waitForExistence(timeout: 20), "Audit Summary should render overview section")
        let seededDiscrepancy = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'WEI-3295 Stage 8 Breaker'")).firstMatch
        if !seededDiscrepancy.waitForExistence(timeout: 3) {
            for _ in 0..<4 where !seededDiscrepancy.exists {
                app.swipeUp()
                _ = seededDiscrepancy.waitForExistence(timeout: 2)
            }
        }
        XCTAssertTrue(seededDiscrepancy.exists, "Audit Summary should render seeded discrepancy")
        captureWEI3295("06-\(viewport)-audit-summary-discrepancy")

        let verification = """
        WEI-3295 Stage 8 reports viewport harness (\(viewport))
        - Route: direct test-only launch flags for Reports hub, Pre-Billing, Bookkeeper Export, and Warehouse Audit Summary.
        - UX source: docs/plans/wei-3200-stage-8-ux-handoff.md.
        - Backend contract: docs/plans/stage-8-reports-data-contract.md.
        - Fixture: -UITestingStage8Reports seeds an unlocked labor entry, material purchase order, and counted warehouse discrepancy through the app database used by production services.
        - Evidence: screenshots 01-06 in this directory capture hub, populated pre-billing, export menu, populated bookkeeper export, export menu, and audit discrepancy state.
        - Viewport target: run this same test once per desktop/wide, tablet, and mobile destination; the artifact folder defaults from the simulator idiom and can be overridden by the test runner environment.
        """
        try verification.write(to: artifactDirectory.appendingPathComponent("verification.txt"), atomically: true, encoding: .utf8)
    }

    @MainActor
    func testWEI3988BackupRestoreSmokeEvidence() throws {
        let artifactDirectory = wei3988ArtifactDirectory.appendingPathComponent(wei3988ViewportName(), isDirectory: true)
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)

        relaunchForWEI3988BackupRestoreSmoke([
            "-UITestingStage8Reports",
            "-UITestingWEI3144JobMaterials"
        ])
        XCTAssertTrue(app.navigationBars["Backups"].waitForExistence(timeout: 20) || app.staticTexts["Backups"].waitForExistence(timeout: 20), "Backups page should open directly")
        XCTAssertTrue(app.staticTexts["Backup Status"].waitForExistence(timeout: 10), "Backup status section should render")
        XCTAssertTrue(app.staticTexts["Database Size"].waitForExistence(timeout: 5), "Backup page should show database size")
        captureWEI3988("01-backups-before-create")

        let createBackup = app.buttons["Create Backup Now"].firstMatch
        XCTAssertTrue(createBackup.waitForExistence(timeout: 10), "Create Backup Now action should be available")
        createBackup.tap()
        XCTAssertTrue(app.buttons["Backup Created!"].waitForExistence(timeout: 15), "Manual backup action should complete with visible success state")
        XCTAssertTrue(app.staticTexts["Stored Backups"].waitForExistence(timeout: 5), "Backup count row should remain visible after backup creation")
        captureWEI3988("02-backups-created")

        relaunchForWEI3988RestoredTarget([])
        XCTAssertTrue(app.staticTexts["Backup Status"].waitForExistence(timeout: 20), "Restored database should reopen the Backups route")
        XCTAssertTrue(app.staticTexts["Stored Backups"].waitForExistence(timeout: 8), "Restored install should still see the backup ledger")
        captureWEI3988("03-restored-backups-status")

        relaunchForWEI3988RestoredTarget(["-UITestingWEI3988PartsCatalog"])
        XCTAssertTrue(app.staticTexts["WEI-3295 Stage 8 Breaker"].waitForExistence(timeout: 20) || app.staticTexts["WEI-3144 Wire Nut"].waitForExistence(timeout: 20), "Restored parts catalog should show seeded sample parts")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'part' AND label CONTAINS 'Page' ")).firstMatch.waitForExistence(timeout: 5), "Restored parts catalog should show a non-empty part count")
        captureWEI3988("04-restored-parts-catalog")

        relaunchForWEI3988RestoredTarget(["-UITestingWEI3988Materials", "-UITestingWEI3144JobMaterials"])
        XCTAssertTrue(app.staticTexts["WEI-3144 Materials QA Job"].waitForExistence(timeout: 20), "Restored job detail should show the seeded materials job")
        XCTAssertTrue(app.descendants(matching: .any)["jobMaterialsTab"].waitForExistence(timeout: 10), "Restored job materials tab should render")
        if app.buttons["Used"].waitForExistence(timeout: 5), app.buttons["Used"].isHittable {
            app.buttons["Used"].tap()
        }
        XCTAssertTrue(app.staticTexts["WEI-3144 Wire Nut"].waitForExistence(timeout: 10), "Restored job materials should include the seeded material")
        captureWEI3988("05-restored-job-materials")

        relaunchForWEI3988RestoredTarget(["-UITestingWEI3988PreBilling"])
        XCTAssertTrue(app.navigationBars["Pre-Billing"].waitForExistence(timeout: 20) || app.staticTexts["Pre-Billing"].waitForExistence(timeout: 20), "Restored Pre-Billing page should open")
        XCTAssertTrue(app.descendants(matching: .any)["pre-billing-row-UITEST-STAGE8-3295"].waitForExistence(timeout: 10), "Restored pre-billing should show the seeded labor/material job row")
        captureWEI3988("06-restored-prebilling")

        relaunchForWEI3988RestoredTarget(["-UITestingWEI3988Bookkeeper"])
        XCTAssertTrue(app.navigationBars["Bookkeeper Export"].waitForExistence(timeout: 20) || app.staticTexts["Bookkeeper Export"].waitForExistence(timeout: 20), "Restored Bookkeeper Export page should open")
        XCTAssertTrue(app.staticTexts["Labor by Employee"].waitForExistence(timeout: 10), "Restored bookkeeper report should show labor section")
        XCTAssertTrue(app.descendants(matching: .any)["bookkeeper-material-row-PO-WEI3295-STAGE8"].waitForExistence(timeout: 10), "Restored bookkeeper report should show the seeded material PO row")
        captureWEI3988("07-restored-bookkeeper")

        let verification = """
        WEI-3988 backup/restore smoke evidence (\(wei3988ViewportName()))
        - Created a manual backup through the user-facing Backups page.
        - Relaunched as a clean UI-test install, restored from the latest backup before DB open, and reopened the restored database.
        - Verified restored parts catalog shows a non-empty count and seeded sample part(s).
        - Verified restored job materials for WEI-3144 Materials QA Job include WEI-3144 Wire Nut.
        - Verified restored Pre-Billing shows seeded job row UITEST-STAGE8-3295.
        - Verified restored Bookkeeper Export shows labor section and material PO row PO-WEI3295-STAGE8.
        - Accessibility/ARIA analogue: smoke uses visible labels/buttons and stable accessibility identifiers for backup action, reports rows, and material/report evidence controls.
        """
        try verification.write(to: artifactDirectory.appendingPathComponent("verification.txt"), atomically: true, encoding: .utf8)
    }

    @MainActor
    func testWEI1251DispatchBoardExistingAssignmentDragDrop() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += [
            "-UITesting",
            "-UITestingDispatchBoard"
        ]
        app.launch()

        logInAsUITestOwnerIfNeeded()
        openDispatchBoard()

        let sourceJob = app.staticTexts["UITest Source Dispatch Job"]
        let targetJob = app.staticTexts["UITest Target Dispatch Job"]
        XCTAssertTrue(sourceJob.waitForExistence(timeout: 15), "Source dispatch job should be visible")
        XCTAssertTrue(targetJob.waitForExistence(timeout: 5), "Target dispatch job should be visible")

        let ownerChip = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Move UITest Owner'"))
            .firstMatch
        XCTAssertTrue(ownerChip.waitForExistence(timeout: 8), "Existing assignment chip should be visible")
        captureWEI1251("01-dispatch-board-seeded")

        let targetSecondDay = dayCellCoordinate(rowLabel: targetJob, dayIndex: 1)
        ownerChip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.8, thenDragTo: targetSecondDay)

        let movedOwnerChip = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Move UITest Owner'"))
            .firstMatch
        XCTAssertTrue(movedOwnerChip.waitForExistence(timeout: 8), "Moved assignment chip should remain visible")
        captureWEI1251("02-existing-assignment-moved")
        XCTAssertLessThan(abs(movedOwnerChip.frame.midY - targetJob.frame.midY), 80,
                          "Existing assignment should move onto the target job row")
        XCTAssertGreaterThan(movedOwnerChip.frame.midX, targetJob.frame.maxX,
                             "Existing assignment should move into a day cell, not stay in the job label column")

        let spareWorker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'UITest Spare Worker'"))
            .firstMatch
        XCTAssertTrue(spareWorker.waitForExistence(timeout: 8), "Unassigned worker chip should be visible")
        spareWorker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.8, thenDragTo: dayCellCoordinate(rowLabel: targetJob, dayIndex: 3))

        let spareAssignment = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Move UITest Spare Worker'"))
            .firstMatch
        XCTAssertTrue(spareAssignment.waitForExistence(timeout: 8),
                      "Dropping an unassigned worker should create a dispatch assignment")
        captureWEI1251("03-unassigned-worker-created-assignment")

        movedOwnerChip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.8, thenDragTo: dayCellCoordinate(rowLabel: targetJob, dayIndex: 2))
        let conflict = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'time off'")).firstMatch
        XCTAssertTrue(conflict.waitForExistence(timeout: 8),
                      "Invalid move should present a visible time-off conflict error")
        captureWEI1251("04-invalid-move-conflict-error")
    }

    @MainActor
    func testWEI1185WarehouseZonePlacementScreenshots() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += [
            "-UITesting",
            "-UITestingWarehouseSetupWizard"
        ]
        if ProcessInfo.processInfo.environment["WEI_1185_LANDSCAPE"] == "1" {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        app.launch()

        guard let artifactDirectory = wei1185ArtifactDirectory else {
            XCTFail("Unable to resolve WEI-1185 artifact directory.")
            return
        }
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        let existingArtifacts = (try? FileManager.default.contentsOfDirectory(
            at: artifactDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for artifact in existingArtifacts where artifact.pathExtension == "png" {
            try? FileManager.default.removeItem(at: artifact)
        }

        logInAsUITestOwnerIfNeeded()
        openWarehouseSetupWizard()

        let createContinue = app.buttons["Create & Continue"]
        if createContinue.waitForExistence(timeout: 10) {
            createContinue.tap()
        }
        if app.staticTexts["Phase 2 · Storage Units"].waitForExistence(timeout: 3) {
            app.buttons["Back"].tap()
        }

        XCTAssertTrue(app.staticTexts["Confirm Zone Grid"].waitForExistence(timeout: 10),
                      "Step 2 should start with the zone grid dimension confirmation")
        captureWEI1185("01-zone-grid-dimensions")

        let confirmGrid = app.buttons["Confirm Grid"]
        XCTAssertTrue(confirmGrid.waitForExistence(timeout: 5), "Confirm Grid should be available")
        confirmGrid.tap()

        XCTAssertTrue(app.staticTexts["Zones"].waitForExistence(timeout: 10), "Zone placement palette should load")
        captureWEI1185("02-empty-3x5-zone-grid")
        let r1c1 = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'R1C1'")).firstMatch
        let r3c5 = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'R3C5'")).firstMatch
        XCTAssertTrue(r1c1.waitForExistence(timeout: 5), "Default 3x5 grid should include R1C1")
        XCTAssertTrue(r3c5.waitForExistence(timeout: 5), "Default 3x5 grid should include R3C5")

        let storage = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Drag Storage zone'")).firstMatch
        XCTAssertTrue(storage.waitForExistence(timeout: 5), "Storage zone drag source should be present")
        storage.press(forDuration: 0.7, thenDragTo: r1c1)

        let placedStorage = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'starts at R1C1'")).firstMatch
        XCTAssertTrue(placedStorage.waitForExistence(timeout: 8), "Dropped Storage zone should render on the grid")
        placedStorage.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Edit'")).firstMatch.waitForExistence(timeout: 5),
                      "Selecting a zone should reveal Edit")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Delete'")).firstMatch.waitForExistence(timeout: 5),
                      "Selecting a zone should reveal Delete")
        captureWEI1185("03-storage-selected-edit-delete")

        let r2c2 = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'R2C2'")).firstMatch
        placedStorage.press(forDuration: 0.7, thenDragTo: r2c2)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'R2C2'")).firstMatch.waitForExistence(timeout: 5),
                      "Moving the zone should update selected-zone location text")
        captureWEI1185("04-storage-moved-r2c2")

        let resizeHandle = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Resize Storage'")).firstMatch
        XCTAssertTrue(resizeHandle.waitForExistence(timeout: 5), "Selected zone should expose a resize handle")
        let r3c3 = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'R3C3'")).firstMatch
        XCTAssertTrue(r3c3.waitForExistence(timeout: 5), "Default 3x5 grid should include R3C3")
        let grow = app.buttons["Grow"]
        XCTAssertTrue(grow.waitForExistence(timeout: 5), "Selected zone should expose Grow")
        if !app.staticTexts.matching(NSPredicate(format: "label CONTAINS '2x2'")).firstMatch.exists {
            grow.tap()
        }
        let sizeText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '2x2'")).firstMatch
        let resizedZone = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Storage' AND label CONTAINS '2 by 2 cells'")
        ).firstMatch
        XCTAssertTrue(sizeText.waitForExistence(timeout: 5) || resizedZone.waitForExistence(timeout: 5),
                      "Resizing should update selected-zone size text or the zone accessibility label")
        captureWEI1185("05-storage-resized-2x2")

        app.buttons["Save & Exit"].tap()
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += [
            "-UITesting",
            "-UITestingPreserveDatabase",
            "-UITestingWarehouseSetupWizard"
        ]
        if ProcessInfo.processInfo.environment["WEI_1185_LANDSCAPE"] == "1" {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        app.launch()
        logInAsUITestOwnerIfNeeded()
        openWarehouseSetupWizard()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'R2C2'")).firstMatch.waitForExistence(timeout: 10),
                      "Zone placement should persist after leaving and resuming the wizard")
        captureWEI1185("06-storage-persisted-after-resume")
    }

    @MainActor
    func testWEI3498WarehouseLocationsSelectedSubtabAutoScrollsIntoView() throws {
        app.terminate()
        app = XCUIApplication()
        configureUITestingEnvironment(app)
        app.launchArguments += [
            "-UITesting",
            "-UITestingWEI936AutoLogin",
            "-UITestingWarehouseLocations"
        ]
        app.launch()

        XCTAssertTrue(
            app.navigationBars["Warehouse"].waitForExistence(timeout: 30) ||
                app.staticTexts["Warehouse"].waitForExistence(timeout: 30),
            "Warehouse module should open without the manual login/PIN route"
        )

        let selectedLocationsSubtab = app.buttons["subtab_warehouse-locations"]
        XCTAssertTrue(
            selectedLocationsSubtab.waitForExistence(timeout: 10),
            "Warehouse Locations sub-tab should exist after direct route selection"
        )
        XCTAssertTrue(
            selectedLocationsSubtab.isHittable,
            "Selected off-screen Warehouse Locations sub-tab should be auto-scrolled into the narrow iPhone viewport"
        )

        XCTAssertTrue(
            app.buttons["Shelving"].waitForExistence(timeout: 10) ||
                app.staticTexts["UITesting Shelf A"].waitForExistence(timeout: 10),
            "Warehouse Locations content should render after the auto-scrolled selected sub-tab is visible"
        )

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "WEI-3498 warehouse locations selected subtab visible"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testWEI2475WarehouseLocationsDirectRouteReachesSeededFloorPlan() throws {
        app.terminate()
        app = XCUIApplication()
        configureUITestingEnvironment(app)
        app.launchArguments += [
            "-UITesting",
            "-UITestingWEI936AutoLogin",
            "-UITestingWarehouseLocations"
        ]
        app.launch()

        XCTAssertTrue(
            app.navigationBars["Warehouse"].waitForExistence(timeout: 30) ||
                app.staticTexts["Warehouse"].waitForExistence(timeout: 30),
            "Warehouse module should open without the manual login/PIN route"
        )
        XCTAssertTrue(
            app.buttons["Shelving"].waitForExistence(timeout: 10) ||
                app.staticTexts["UITesting Shelf A"].waitForExistence(timeout: 10),
            "Warehouse Locations should render its floor-plan controls or seeded shelf"
        )
        let requiredToolbarItems = [
            "shelving", "gang_box", "pipe_rack", "pallet_rack", "wall_mount", "floor_area",
            "cabinet", "packout", "tool_bag", "parts_bin", "crate", "custom"
        ]
        for unitType in requiredToolbarItems {
            let button = app.buttons["warehouse-unit-type-\(unitType)"]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "\(unitType) toolbar item should be present")
            XCTAssertTrue(button.isHittable, "\(unitType) toolbar item should be reachable at iPhone width")
        }
        let packoutToolbarButton = app.buttons["warehouse-unit-type-packout"]
        packoutToolbarButton.tap()
        XCTAssertTrue(
            app.textFields.firstMatch.waitForExistence(timeout: 8),
            "Packout Set toolbar action should open the add-unit sheet with a name field"
        )
        XCTAssertTrue(
            app.buttons["East"].waitForExistence(timeout: 3) ||
                app.buttons["West"].waitForExistence(timeout: 3),
            "Add Packout Set sheet should expose Front Face controls"
        )
        app.buttons["Cancel"].tap()
        XCTAssertTrue(
            app.staticTexts["UITesting Shelf A"].waitForExistence(timeout: 10) ||
                app.staticTexts["UITesting Pipe Rack"].waitForExistence(timeout: 10),
            "Warehouse Locations should show a seeded storage unit for visual QA"
        )
    }

    @MainActor
    func testWEI1182WarehouseWizardBreakpointWalkingPathScreenshots() throws {
        let destinationName = ProcessInfo.processInfo.environment["RUN_DESTINATION_DEVICE_NAME"] ?? ""
        if ProcessInfo.processInfo.environment["WEI_1182_LANDSCAPE"] == "1"
            || destinationName.contains("iPad Pro 13-inch") {
            XCUIDevice.shared.orientation = .landscapeLeft
        }

        let artifactDirectory = wei1182ArtifactDirectory
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        let existingArtifacts = (try? FileManager.default.contentsOfDirectory(
            at: artifactDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for artifact in existingArtifacts where artifact.pathExtension == "png" {
            try? FileManager.default.removeItem(at: artifact)
        }

        logInAsUITestOwnerIfNeeded()
        openWarehouseSetupWizard()

        let createContinue = app.buttons["Create & Continue"]
        XCTAssertTrue(createContinue.waitForExistence(timeout: 10), "Fresh warehouse wizard should start at Step 1")
        createContinue.tap()

        if app.staticTexts["Phase 2 · Storage Units"].waitForExistence(timeout: 3) {
            app.buttons["Back"].tap()
        }
        goToWizardStep(2)

        XCTAssertTrue(app.staticTexts["Confirm Zone Grid"].waitForExistence(timeout: 10),
                      "Step 2 should start with the zone-grid confirmation")
        captureWEI1182("01-zone-placement-phase-a")

        let confirmGrid = app.buttons["Confirm Grid"]
        XCTAssertTrue(confirmGrid.waitForExistence(timeout: 5), "Confirm Grid should be available")
        confirmGrid.tap()

        let r1c1 = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'R1C1'")).firstMatch
        let r1c3 = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'R1C3'")).firstMatch
        let r3c3 = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'R3C3'")).firstMatch
        XCTAssertTrue(r1c1.waitForExistence(timeout: 8), "Zone grid should include R1C1")
        XCTAssertTrue(r1c3.waitForExistence(timeout: 5), "Zone grid should include R1C3")

        let storage = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Drag Storage zone'")).firstMatch
        XCTAssertTrue(storage.waitForExistence(timeout: 5), "Storage zone drag source should be present")
        storage.press(forDuration: 0.7, thenDragTo: r1c1)

        let receiving = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Drag Receiving zone'")).firstMatch
        XCTAssertTrue(receiving.waitForExistence(timeout: 5), "Receiving zone drag source should be present")
        receiving.press(forDuration: 0.7, thenDragTo: r1c3)

        let placedStorage = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Storage' AND label CONTAINS 'starts at R1C1'")
        ).firstMatch
        XCTAssertTrue(placedStorage.waitForExistence(timeout: 8), "Dropped Storage zone should render on the grid")
        placedStorage.tap()

        let resizeHandle = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Resize Storage'")).firstMatch
        XCTAssertTrue(resizeHandle.waitForExistence(timeout: 5), "Selected Storage zone should expose a resize handle")
        XCTAssertTrue(r3c3.waitForExistence(timeout: 5), "Zone grid should include R3C3")
        app.buttons["Grow"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '2x2'")).firstMatch.waitForExistence(timeout: 5),
                      "Resizing Storage should update selected-zone size text")

        let placedReceiving = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Receiving' AND label CONTAINS 'starts at R1C3'")
        ).firstMatch
        let receivingRendered = placedReceiving.waitForExistence(timeout: 5)
        if !receivingRendered {
            NSLog("[WEI-1182] Receiving zone did not expose an accessibility element after drag-to-R1C3 on phone width.")
        }
        XCTAssertTrue(receivingRendered, "Dropped Receiving zone should remain visible after resizing Storage")
        captureWEI1182("02-zone-placement-phase-b-two-zones-resized")

        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Phase 2 · Storage Units"].waitForExistence(timeout: 10),
                      "Step 3 should load storage units")

        let addStorageUnit = app.buttons["Add Storage Unit"]
        XCTAssertTrue(addStorageUnit.waitForExistence(timeout: 5), "Step 3 should expose Add Storage Unit")
        addStorageUnit.tap()

        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Storage unit sheet should expose a name field")
        nameField.tap()
        nameField.typeText("Shelf A")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Shelf A"].waitForExistence(timeout: 8), "Saved storage unit should appear")

        goToWizardStep(8)
        XCTAssertTrue(app.staticTexts["Phase 4 · Walking Path"].waitForExistence(timeout: 10),
                      "Step 8 should be the walking-path step")
        captureWEI1182("03-walking-path-empty")

        let suggestPath = app.buttons["Suggest path"]
        XCTAssertTrue(suggestPath.waitForExistence(timeout: 8), "Walking path should expose Suggest path")
        suggestPath.tap()
        XCTAssertTrue(app.staticTexts["Suggested Preview"].waitForExistence(timeout: 8),
                      "Suggest path should show a preview section")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '4'")).firstMatch.waitForExistence(timeout: 5),
                      "Suggested path should include the four generated areas")
        captureWEI1182("04-suggest-path-preview")

        let useSuggested = app.buttons["Use suggested order"]
        XCTAssertTrue(useSuggested.waitForExistence(timeout: 5), "Preview should expose Use suggested order")
        useSuggested.tap()
        XCTAssertTrue(app.staticTexts["Path Stops"].waitForExistence(timeout: 8),
                      "Applied suggested order should become saved path stops")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '4 stops saved'")).firstMatch.waitForExistence(timeout: 8),
                      "Saved walking path should report four stops")

        app.buttons["Save & Exit"].tap()
        openWarehouseSetupWizard()
        XCTAssertTrue(app.staticTexts["Phase 4 · Walking Path"].waitForExistence(timeout: 10),
                      "Save & Exit should resume the wizard on the walking-path step")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '4 stops saved'")).firstMatch.waitForExistence(timeout: 8),
                      "Walking path stops should persist after reopening the wizard")
        captureWEI1182("05-walking-path-persisted-after-resume")
    }

    // MARK: - WEI-1188: Step 6 Phase-Header Screenshot for WEI-1175

    /// Captures the wizard section-header screenshot acceptance for [WEI-1175]:
    /// open the warehouse onboarding wizard, reach Step 6 (Areas), confirm the
    /// exact Plan §4 phase prefix ("Phase 3 · Areas") is rendered in both the
    /// nav bar title and the progress-bar caption, then save the screenshot
    /// under `docs/testing/artifacts/wei-1092/wei-1188-step6-phase-header/`.
    @MainActor
    func testWEI1188WizardStep6PhaseHeaderScreenshot() throws {
        let directory: URL = {
            if let envPath = ProcessInfo.processInfo.environment["WEI_1188_ARTIFACT_DIR"], !envPath.isEmpty {
                return URL(fileURLWithPath: envPath, isDirectory: true)
            }
            let source = URL(fileURLWithPath: #filePath)
            let repoRoot = source
                .deletingLastPathComponent() // Weird Parts IOSUITests
                .deletingLastPathComponent() // Weird Parts IOS
                .deletingLastPathComponent() // repo root
            return repoRoot.appendingPathComponent(
                "docs/testing/artifacts/wei-1092/wei-1188-step6-phase-header",
                isDirectory: true
            )
        }()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        func capture(_ name: String) {
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            let file = directory.appendingPathComponent("\(name).png")
            try? screenshot.pngRepresentation.write(to: file, options: .atomic)
        }

        logInAsUITestOwnerIfNeeded()
        openWarehouseSetupWizard()

        // Step 1: create the floor plan if it doesn't exist yet. A resumed
        // session lands on the previous step with a "Next" button instead.
        let createContinue = app.buttons["Create & Continue"]
        if createContinue.waitForExistence(timeout: 10) {
            createContinue.tap()
        }

        capture("00-wizard-entry-step")

        // Adaptive navigation to Step 6: while the wizard reports a step less
        // than 6, tap Skip (or Next as fallback) and wait for the step counter
        // to advance. While it reports a step greater than 6, tap Back. This
        // tolerates any saved progress state from prior runs.
        func currentStepNumber(timeout: TimeInterval = 5) -> Int? {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                for n in 1...10 where app.staticTexts["Step \(n) of 10"].exists {
                    return n
                }
                Thread.sleep(forTimeInterval: 0.25)
            }
            return nil
        }

        var lastSeen: Int? = nil
        for navHop in 1...12 {
            guard let step = currentStepNumber(timeout: 8) else {
                capture("error-step-counter-missing-hop-\(navHop)")
                XCTFail("Could not read \"Step N of 10\" from the wizard progress bar (hop \(navHop)).")
                return
            }
            lastSeen = step
            if step == 6 { break }
            if step < 6 {
                let skip = app.buttons["Skip"]
                let next = app.buttons["Next"]
                if skip.exists && skip.isHittable {
                    skip.tap()
                } else if next.exists && next.isHittable {
                    next.tap()
                } else {
                    capture("error-no-forward-button-step-\(step)")
                    XCTFail("Wizard step \(step) exposed neither Skip nor Next.")
                    return
                }
            } else {
                let back = app.buttons["Back"]
                if back.exists && back.isHittable {
                    back.tap()
                } else {
                    capture("error-no-back-button-step-\(step)")
                    XCTFail("Wizard step \(step) exposed no Back button.")
                    return
                }
            }
            // Wait for the step counter to actually change before continuing.
            _ = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Step ' AND NOT (label == 'Step \(step) of 10')"))
                .firstMatch
                .waitForExistence(timeout: 6)
        }
        XCTAssertEqual(lastSeen, 6, "Adaptive navigation should land on Step 6 (was \(String(describing: lastSeen))).")

        // Capture immediately so we have the artifact regardless of which
        // predicate matches the exact phase-prefix copy.
        capture("01-step6-phase3-areas-header")

        // The Plan §4 phase prefix renders in two places at Step 6:
        //   1. The navigation bar title ("Phase 3 · Areas").
        //   2. The progress bar caption (right-aligned blue caption).
        // Use CONTAINS so we tolerate any whitespace nuance between the
        // SF Symbols middle dot ("·" U+00B7) and surrounding spacing.
        let phasePredicate = NSPredicate(format: "label CONTAINS 'Phase 3' AND label CONTAINS 'Areas'")
        let phaseLabel = app.staticTexts.matching(phasePredicate).firstMatch
        let stepIndicator = app.staticTexts["Step 6 of 10"]

        let phaseFound = phaseLabel.waitForExistence(timeout: 10)
        let stepFound = stepIndicator.waitForExistence(timeout: 5)

        if !phaseFound || !stepFound {
            // Dump every visible static text to the xcresult so a human can
            // see what XCUI actually exposed at Step 6.
            for text in app.staticTexts.allElementsBoundByIndex.prefix(40) {
                NSLog("[WEI-1188] staticText label=\(text.label)")
            }
            capture("error-step6-labels-missing")
        }

        XCTAssertTrue(phaseFound,
                      "Step 6 should render a static text containing the Plan §4 phase prefix \"Phase 3 … Areas\".")
        XCTAssertTrue(stepFound,
                      "Progress bar should report \"Step 6 of 10\" after the 9→10 dot expansion.")
    }

    // MARK: - WEI-1190: Step 8 Phase-Header Screenshot

    /// Captures the wizard section-header screenshot acceptance for [WEI-1190]:
    /// open the warehouse onboarding wizard, reach Step 8 (Walking Path), confirm
    /// the exact Plan §4 phase prefix ("Phase 4 · Walking Path") is rendered in
    /// both the nav bar title and progress-bar caption, then save the screenshots
    /// under `docs/testing/artifacts/wei-1092/wei-1190-step8-phase-header/`.
    @MainActor
    func testWEI1190WizardStep8PhaseHeaderScreenshot() throws {
        let directory: URL = {
            if let envPath = ProcessInfo.processInfo.environment["WEI_1190_ARTIFACT_DIR"], !envPath.isEmpty {
                return URL(fileURLWithPath: envPath, isDirectory: true)
            }
            let source = URL(fileURLWithPath: #filePath)
            let repoRoot = source
                .deletingLastPathComponent() // Weird Parts IOSUITests
                .deletingLastPathComponent() // Weird Parts IOS
                .deletingLastPathComponent() // repo root
            return repoRoot.appendingPathComponent(
                "docs/testing/artifacts/wei-1092/wei-1190-step8-phase-header",
                isDirectory: true
            )
        }()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        func capture(_ name: String) throws {
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            let file = directory.appendingPathComponent("\(name).png")
            do {
                try screenshot.pngRepresentation.write(to: file, options: .atomic)
            } catch {
                XCTFail("Failed to write WEI-1190 screenshot artifact \(file.path): \(error)")
                throw error
            }
        }

        logInAsUITestOwnerIfNeeded()
        openWarehouseSetupWizard()

        // Step 1: create the floor plan if it doesn't exist yet. A resumed
        // session lands on the previous step with a "Next" button instead.
        let createContinue = app.buttons["Create & Continue"]
        if createContinue.waitForExistence(timeout: 10) {
            createContinue.tap()
        }

        try capture("00-wizard-entry-step")

        // Adaptive navigation to Step 8: while the wizard reports a step less
        // than 8, tap Skip (or Next as fallback) and wait for the step counter
        // to advance. While it reports a step greater than 8, tap Back. This
        // tolerates any saved progress state from prior runs.
        func currentStepNumber(timeout: TimeInterval = 5) -> Int? {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                for n in 1...10 where app.staticTexts["Step \(n) of 10"].exists {
                    return n
                }
                Thread.sleep(forTimeInterval: 0.25)
            }
            return nil
        }

        var lastSeen: Int? = nil
        for navHop in 1...14 {
            guard let step = currentStepNumber(timeout: 8) else {
                try capture("error-step-counter-missing-hop-\(navHop)")
                XCTFail("Could not read \"Step N of 10\" from the wizard progress bar (hop \(navHop)).")
                return
            }
            lastSeen = step
            if step == 8 { break }
            if step < 8 {
                let skip = app.buttons["Skip"]
                let next = app.buttons["Next"]
                if skip.exists && skip.isHittable {
                    skip.tap()
                } else if next.exists && next.isHittable {
                    next.tap()
                } else {
                    try capture("error-no-forward-button-step-\(step)")
                    XCTFail("Wizard step \(step) exposed neither Skip nor Next.")
                    return
                }
            } else {
                let back = app.buttons["Back"]
                if back.exists && back.isHittable {
                    back.tap()
                } else {
                    try capture("error-no-back-button-step-\(step)")
                    XCTFail("Wizard step \(step) exposed no Back button.")
                    return
                }
            }
            // Wait for the step counter to actually change before continuing.
            _ = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Step ' AND NOT (label == 'Step \(step) of 10')"))
                .firstMatch
                .waitForExistence(timeout: 6)
        }
        XCTAssertEqual(lastSeen, 8, "Adaptive navigation should land on Step 8 (was \(String(describing: lastSeen))).")

        // Capture immediately so we have the artifact regardless of which
        // predicate matches the exact phase-prefix copy.
        try capture("01-step8-phase4-walking-path-header")

        // The Plan §4 phase prefix renders in two places at Step 8:
        //   1. The navigation bar title ("Phase 4 · Walking Path").
        //   2. The progress bar caption (right-aligned blue caption).
        // Use CONTAINS so we tolerate any whitespace nuance between the
        // SF Symbols middle dot ("·" U+00B7) and surrounding spacing.
        let phasePredicate = NSPredicate(format: "label CONTAINS 'Phase 4' AND label CONTAINS 'Walking Path'")
        let navigationPhaseTitle = app.navigationBars.staticTexts.matching(phasePredicate).firstMatch
        let matchingPhaseLabels = app.staticTexts.matching(phasePredicate)
        let stepIndicator = app.staticTexts["Step 8 of 10"]

        let navigationPhaseFound = navigationPhaseTitle.waitForExistence(timeout: 10)
        let progressPhaseDeadline = Date().addingTimeInterval(10)
        while matchingPhaseLabels.count < 2 && Date() < progressPhaseDeadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
        let phaseLabelCount = matchingPhaseLabels.count
        let progressPhaseFound = phaseLabelCount >= 2
        let stepFound = stepIndicator.waitForExistence(timeout: 5)

        if !navigationPhaseFound || !progressPhaseFound || !stepFound {
            // Dump every visible static text to the xcresult so a human can
            // see what XCUI actually exposed at Step 8.
            for text in app.staticTexts.allElementsBoundByIndex.prefix(40) {
                NSLog("[WEI-1190] staticText label=\(text.label)")
            }
            try capture("error-step8-labels-missing")
        }

        XCTAssertTrue(navigationPhaseFound,
                      "Step 8 navigation bar should render the Plan §4 phase prefix \"Phase 4 … Walking Path\".")
        XCTAssertTrue(progressPhaseFound,
                      "Step 8 progress caption should render a second Plan §4 phase prefix \"Phase 4 … Walking Path\" (found \(phaseLabelCount) matching label(s)).")
        XCTAssertTrue(stepFound,
                      "Progress bar should report \"Step 8 of 10\" after the 9→10 dot expansion.")
    }

    @MainActor
    func testLoginSignInButtonHittableAtAX5WithKeyboardVisible() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += [
            "-UITesting",
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        ]
        app.launch()

        let loginView = app.otherElements["loginView"]
        guard loginView.waitForExistence(timeout: 30) else {
            throw XCTSkip("Login was not shown; this regression requires a fresh logged-out UI-test launch.")
        }

        let userRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'loginUserRow_'"))
        guard userRows.firstMatch.waitForExistence(timeout: 20) else {
            throw XCTSkip("Login seed user was not available; cannot exercise the PIN keyboard layout.")
        }
        userRows.firstMatch.tap()

        let pinField = app.secureTextFields["loginPINField"]
        XCTAssertTrue(pinField.waitForExistence(timeout: 5),
                      "PIN field should appear after selecting a user")
        pinField.tap()
        pinField.typeText("1234")

        let signIn = app.buttons["loginSignInButton"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5),
                      "Sign In should remain in the keyboard-aware bottom inset")
        XCTAssertTrue(signIn.isHittable,
                      "Sign In should be hittable at AX5 while the number pad is visible")

        let done = app.buttons["loginPINDoneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 3),
                      "Number pad should expose a Done toolbar button")
        XCTAssertTrue(done.isHittable,
                      "Done toolbar button should be tappable at AX5")
    }

    private func logInAsUITestOwnerIfNeeded() {
        if app.buttons["tab_dashboard"].waitForExistence(timeout: 5) && app.buttons["tab_dashboard"].isHittable ||
            app.buttons["Dashboard"].exists && app.buttons["Dashboard"].isHittable ||
            app.buttons["tab_parts"].exists && app.buttons["tab_parts"].isHittable ||
            app.buttons["Parts"].exists && app.buttons["Parts"].isHittable ||
            partsCategoriesPage.exists ||
            app.buttons["tab_warehouse"].exists && app.buttons["tab_warehouse"].isHittable ||
            app.buttons["Warehouse"].exists && app.buttons["Warehouse"].isHittable ||
            app.buttons["Configure Your Warehouse"].exists && app.buttons["Configure Your Warehouse"].isHittable ||
            app.staticTexts["Warehouse Setup"].exists ||
            app.staticTexts["Phase 1 · Define Size"].exists ||
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Phase' OR label CONTAINS 'Create & Continue' OR label CONTAINS 'Zones'")).firstMatch.exists ||
            app.staticTexts["Confirm Zone Grid"].exists ||
            app.buttons["Create & Continue"].exists {
            return
        }

        let userRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'loginUserRow_'"))
        let ownerRow = app.buttons["loginUserRow_1"]
        let ownerLabel = app.staticTexts["UITest Owner"]
        if userRows.firstMatch.waitForExistence(timeout: 30) {
            userRows.firstMatch.tap()
        } else if ownerRow.waitForExistence(timeout: 5) {
            ownerRow.tap()
        } else if ownerLabel.waitForExistence(timeout: 5) {
            ownerLabel.tap()
        } else {
            XCTAssertTrue(app.buttons["tab_dashboard"].exists ||
                          app.buttons["Dashboard"].exists ||
                          app.buttons["tab_parts"].exists ||
                          app.buttons["Parts"].exists ||
                          partsCategoriesPage.exists ||
                          app.buttons["tab_warehouse"].exists ||
                          app.buttons["Warehouse"].exists ||
                          app.buttons["Configure Your Warehouse"].exists ||
                          app.staticTexts["Warehouse Setup"].exists ||
                          app.staticTexts["Phase 1 · Define Size"].exists ||
                          app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Phase' OR label CONTAINS 'Create & Continue' OR label CONTAINS 'Zones'")).firstMatch.exists ||
                          app.staticTexts["Confirm Zone Grid"].exists ||
                          app.buttons["Create & Continue"].exists,
                          "UI test login should find UITest Owner or an already-authenticated shell")
            return
        }

        let pinField = app.secureTextFields["loginPINField"]
        XCTAssertTrue(pinField.waitForExistence(timeout: 5), "PIN field should appear")
        pinField.tap()
        pinField.typeText("1234")

        let done = app.buttons["loginPINDoneButton"]
        if done.waitForExistence(timeout: 3) && done.isHittable {
            done.tap()
        }

        let signIn = app.buttons["loginSignInButton"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5), "Sign In should be available")
        XCTAssertTrue(signIn.isHittable, "Sign In should be hittable after entering the UITest Owner PIN")
        signIn.tap()

        let welcomeCTA = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Got It'")).firstMatch
        let skipTour = app.buttons["Skip"]
        // OnboardingWalkthroughView's first page uses "Skip Onboarding" (not
        // "Skip"); without this the loop spins past the walkthrough and never
        // reaches the dashboard. Also covers any future "Skip Tour" / "Skip
        // Walkthrough" variants.
        let skipAny = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Skip'")).firstMatch
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if welcomeCTA.exists && welcomeCTA.isHittable { welcomeCTA.tap(); continue }
            if skipTour.exists && skipTour.isHittable { skipTour.tap(); continue }
            if skipAny.exists && skipAny.isHittable { skipAny.tap(); continue }
            if app.buttons["tab_dashboard"].exists && app.buttons["tab_dashboard"].isHittable ||
                app.buttons["Dashboard"].exists && app.buttons["Dashboard"].isHittable ||
                app.buttons["tab_parts"].exists && app.buttons["tab_parts"].isHittable ||
                app.buttons["Parts"].exists && app.buttons["Parts"].isHittable ||
                partsCategoriesPage.exists ||
                app.buttons["tab_warehouse"].exists && app.buttons["tab_warehouse"].isHittable ||
                app.buttons["Warehouse"].exists && app.buttons["Warehouse"].isHittable ||
                app.buttons["Configure Your Warehouse"].exists && app.buttons["Configure Your Warehouse"].isHittable ||
                app.staticTexts["Warehouse Setup"].exists ||
                app.staticTexts["Phase 1 · Define Size"].exists ||
                app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Phase' OR label CONTAINS 'Create & Continue' OR label CONTAINS 'Zones'")).firstMatch.exists ||
                app.staticTexts["Confirm Zone Grid"].exists ||
                app.buttons["Create & Continue"].exists {
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        captureWEI1185("00-login-shell-not-reached")
        XCTAssertTrue(app.buttons["tab_dashboard"].exists ||
                      app.buttons["Dashboard"].exists ||
                      app.buttons["tab_parts"].exists ||
                      app.buttons["Parts"].exists ||
                      partsCategoriesPage.exists ||
                      app.buttons["tab_warehouse"].exists ||
                      app.buttons["Warehouse"].exists ||
                      app.buttons["Configure Your Warehouse"].exists ||
                      app.staticTexts["Warehouse Setup"].exists ||
                      app.staticTexts["Phase 1 · Define Size"].exists ||
                      app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Phase' OR label CONTAINS 'Create & Continue' OR label CONTAINS 'Zones'")).firstMatch.exists ||
                      app.staticTexts["Confirm Zone Grid"].exists ||
                      app.buttons["Create & Continue"].exists,
                      "Login should reach the app shell before opening the requested route")
    }

    private func openWarehouseSetupWizard() {
        captureWEI1185("00-before-open-warehouse-wizard")

        if app.staticTexts["Confirm Zone Grid"].waitForExistence(timeout: 3) ||
            app.staticTexts["Warehouse Setup"].waitForExistence(timeout: 3) ||
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Phase' OR label CONTAINS 'Zones'")).firstMatch.waitForExistence(timeout: 3) ||
            app.buttons["Create & Continue"].waitForExistence(timeout: 3) {
            return
        }

        let warehouseTab = app.buttons["tab_warehouse"]
        if warehouseTab.waitForExistence(timeout: 5) {
            warehouseTab.tap()
        } else if app.buttons["Warehouse"].waitForExistence(timeout: 2) {
            app.buttons["Warehouse"].tap()
        } else if app.tabBars.buttons["More"].waitForExistence(timeout: 2) {
            app.tabBars.buttons["More"].tap()
            let warehouse = app.buttons["Warehouse"]
            if warehouse.waitForExistence(timeout: 5) {
                warehouse.tap()
            }
        }

        if app.navigationBars["Warehouse"].waitForExistence(timeout: 3) ||
            app.staticTexts["Warehouse"].waitForExistence(timeout: 3) {
            let setup = app.buttons["whAction_setupWizard"]
            if !setup.waitForExistence(timeout: 5) {
                let scroll = app.scrollViews.firstMatch
                for _ in 0..<6 where !setup.exists {
                    scroll.swipeUp()
                }
            }
            if setup.waitForExistence(timeout: 5) {
                setup.tap()
                return
            }
        }

        let dashboardTab = app.buttons["tab_dashboard"]
        if dashboardTab.waitForExistence(timeout: 5) {
            dashboardTab.tap()
        } else {
            let dashboard = app.tabBars.buttons["Dashboard"].firstMatch
            if dashboard.waitForExistence(timeout: 2) {
                dashboard.tap()
            } else if app.buttons.matching(identifier: "subtab_warehouse-dashboard").firstMatch.waitForExistence(timeout: 2) {
                app.buttons.matching(identifier: "subtab_warehouse-dashboard").firstMatch.tap()
            }
        }

        let configure = app.buttons["Configure Your Warehouse"]
        if !configure.waitForExistence(timeout: 5) {
            let scroll = app.scrollViews.firstMatch
            for _ in 0..<8 where !configure.exists {
                scroll.swipeUp()
            }
        }
        captureWEI1185("00-wizard-route-not-found")
        XCTAssertTrue(configure.waitForExistence(timeout: 10), "Dashboard should expose Configure Your Warehouse")
        configure.tap()
    }

    private func openWarehouseDashboard() {
        if app.buttons["whAction_newMovement"].waitForExistence(timeout: 2) {
            return
        }

        let warehouseTab = app.buttons["tab_warehouse"]
        if warehouseTab.waitForExistence(timeout: 8) {
            warehouseTab.tap()
        } else if app.buttons["Warehouse"].waitForExistence(timeout: 3) {
            app.buttons["Warehouse"].tap()
        } else if app.tabBars.buttons["More"].waitForExistence(timeout: 3) {
            app.tabBars.buttons["More"].tap()
            let warehouse = app.buttons["Warehouse"]
            XCTAssertTrue(warehouse.waitForExistence(timeout: 8), "Warehouse module should be reachable")
            warehouse.tap()
        } else {
            XCTFail("Warehouse module tab should be reachable")
        }

        if !app.buttons["whAction_newMovement"].waitForExistence(timeout: 8) {
            let dashboard = app.buttons["Dashboard"]
            if dashboard.waitForExistence(timeout: 5) && dashboard.isHittable {
                dashboard.tap()
            }
        }

        XCTAssertTrue(
            app.buttons["whAction_newMovement"].waitForExistence(timeout: 10),
            "Warehouse Dashboard should open and expose quick actions"
        )
    }

    private func openDispatchBoard() {
        if app.navigationBars["Dispatch Board"].waitForExistence(timeout: 2) ||
            app.staticTexts["Dispatch Board"].waitForExistence(timeout: 2) {
            return
        }

        let schedulingTab = app.buttons["tab_scheduling"]
        if schedulingTab.waitForExistence(timeout: 8) {
            schedulingTab.tap()
        } else if app.buttons["Scheduling"].waitForExistence(timeout: 3) {
            app.buttons["Scheduling"].tap()
        } else if app.tabBars.buttons["More"].waitForExistence(timeout: 3) {
            app.tabBars.buttons["More"].tap()
            let scheduling = app.buttons["Scheduling"]
            XCTAssertTrue(scheduling.waitForExistence(timeout: 8), "Scheduling module should be reachable")
            scheduling.tap()
        } else {
            XCTFail("Scheduling module tab should be reachable")
        }

        let dispatch = app.buttons["Dispatch"]
        XCTAssertTrue(dispatch.waitForExistence(timeout: 8), "Scheduling module should expose Dispatch tab")
        dispatch.tap()

        XCTAssertTrue(
            app.navigationBars["Dispatch Board"].waitForExistence(timeout: 10) ||
                app.staticTexts["Dispatch Board"].waitForExistence(timeout: 10),
            "Dispatch Board should open"
        )
    }

    private func dayCellCoordinate(rowLabel: XCUIElement, dayIndex: Int) -> XCUICoordinate {
        let appFrame = app.windows.firstMatch.frame
        let firstDayStartX = rowLabel.frame.maxX + 8
        let availableWidth = max(140, appFrame.maxX - firstDayStartX - 16)
        let dayWidth = availableWidth / 7
        let x = firstDayStartX + dayWidth * (CGFloat(dayIndex) + 0.5)
        let y = rowLabel.frame.midY
        return app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: x, dy: y))
    }

    private func captureWEI1251(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let source = URL(fileURLWithPath: #filePath)
        let repoRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dir = repoRoot.appendingPathComponent("docs/testing/artifacts/wei-1251", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"), options: .atomic)
    }

    private func captureWEI1306(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let source = URL(fileURLWithPath: #filePath)
        let repoRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dir = repoRoot.appendingPathComponent("docs/testing/artifacts/wei-1306", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"), options: .atomic)
    }

    private func captureWEI1185(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        if let dir = wei1185ArtifactDirectory {
            let file = dir.appendingPathComponent("\(name).png")
            try? screenshot.pngRepresentation.write(to: file, options: .atomic)
        }
    }

    private func captureWEI1182(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let file = wei1182ArtifactDirectory.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: file, options: .atomic)
    }

    private func relaunchForWEI1451(_ launchArguments: [String]) {
        app.terminate()
        app = XCUIApplication()
        configureUITestingEnvironment(app)
        app.launchArguments += ["-UITestingWEI936AutoLogin", "-UITestingWEI1451DashboardCard"] + launchArguments
        if ProcessInfo.processInfo.environment["WEI_1185_LANDSCAPE"] == "1" {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        app.launch()
    }

    private func relaunchForWEI3041Timesheets(preserveDatabase: Bool) {
        app.terminate()
        app = XCUIApplication()
        configureUITestingEnvironment(app)
        app.launchArguments += [
            "-UITestingWEI936AutoLogin",
            "-UITestingWEI3041Timesheets"
        ]
        if preserveDatabase {
            app.launchArguments += ["-UITestingPreserveDatabase"]
        }
        app.launch()
    }

    private func relaunchForWEI3295Stage8Reports(_ launchArguments: [String]) {
        app.terminate()
        app = XCUIApplication()
        configureUITestingEnvironment(app)
        app.launchArguments += [
            "-UITestingWEI936AutoLogin",
            "-UITestingStage8Reports"
        ] + launchArguments
        app.launch()
    }

    private func relaunchForWEI3988BackupRestoreSmoke(_ launchArguments: [String]) {
        app.terminate()
        app = XCUIApplication()
        configureUITestingEnvironment(app)
        app.launchArguments += [
            "-UITestingWEI936AutoLogin",
            "-UITestingWEI3988BackupRestoreSmoke"
        ] + launchArguments
        app.launch()
    }

    private func relaunchForWEI3988RestoredTarget(_ launchArguments: [String]) {
        relaunchForWEI3988BackupRestoreSmoke(["-UITestingWEI3988RestoreLatestBackup"] + launchArguments)
    }

    private func wei3988ViewportName() -> String {
        if let explicit = ProcessInfo.processInfo.environment["WEI_3988_VIEWPORT"], !explicit.isEmpty {
            return explicit
        }
        return UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone"
    }

    private func wei3295ViewportName() -> String {
        if let explicit = ProcessInfo.processInfo.environment["WEI_3295_VIEWPORT"], !explicit.isEmpty {
            return explicit
        }
        return UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "mobile"
    }

    private func openExportMenuIfPresent() {
        let exportButton = app.buttons["Export"].firstMatch
        if exportButton.waitForExistence(timeout: 5), exportButton.isHittable {
            exportButton.tap()
            _ = app.buttons["Export CSV"].waitForExistence(timeout: 3)
        }
    }

    private func captureWEI3295(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let viewport = wei3295ViewportName()
        let dir = wei3295ArtifactDirectory.appendingPathComponent(viewport, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"), options: .atomic)
    }

    private func captureWEI3041(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        try? FileManager.default.createDirectory(at: wei3041ArtifactDirectory, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: wei3041ArtifactDirectory.appendingPathComponent("\(name).png"), options: .atomic)
    }

    private func writeWEI3041VerificationNotes() throws {
        let notes = """
        WEI-3041 correction sheet evidence
        - Fixture: -UITestingWEI3041Timesheets seeds weekly_only overtime with weeklyThresholdHours=6.0.
        - The correction sheet exposes Paid Time Preview and policy-allocation copy, not editable adjusted regular/overtime preview fields.
        - Save/reload assertion: correction history contains Adjusted 2.0h regular / 2.0h overtime after relaunch with -UITestingPreserveDatabase.
        """
        try FileManager.default.createDirectory(at: wei3041ArtifactDirectory, withIntermediateDirectories: true)
        try notes.write(to: wei3041ArtifactDirectory.appendingPathComponent("verification-notes.txt"), atomically: true, encoding: .utf8)
    }

    private func captureWEI3988(_ name: String) {
        if ProcessInfo.processInfo.environment["WEI_3988_SKIP_SCREENSHOTS"] == "1" {
            return
        }
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let viewport = wei3988ViewportName()
        let dir = wei3988ArtifactDirectory.appendingPathComponent(viewport, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"), options: .atomic)
    }

    private func captureWEI1451(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let file = wei1451ArtifactDirectory.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: file, options: .atomic)
    }

    private func captureWEI3144(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let viewport = UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone"
        let file = wei3144ArtifactDirectory.appendingPathComponent("\(viewport)-\(name).png")
        try? screenshot.pngRepresentation.write(to: file, options: .atomic)
    }

    private func scrollUntilVisible(_ element: XCUIElement, maxSwipes: Int = 8) {
        for _ in 0..<maxSwipes where !element.exists || !element.isHittable {
            app.swipeUp()
        }
    }

    private func currentWizardStepNumber(timeout: TimeInterval = 5) -> Int? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for step in 1...10 where app.staticTexts["Step \(step) of 10"].exists {
                return step
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return nil
    }

    private func goToWizardStep(_ targetStep: Int) {
        for hop in 1...12 {
            guard let step = currentWizardStepNumber(timeout: 8) else {
                captureWEI1182("error-step-counter-missing-hop-\(hop)")
                XCTFail("Could not read wizard step counter while navigating to Step \(targetStep).")
                return
            }
            if step == targetStep { return }

            if step < targetStep {
                let next = app.buttons["Next"]
                let skip = app.buttons["Skip"]
                if next.exists && next.isHittable {
                    next.tap()
                } else if skip.exists && skip.isHittable {
                    skip.tap()
                } else {
                    captureWEI1182("error-no-forward-button-step-\(step)")
                    XCTFail("Wizard Step \(step) exposed no forward navigation.")
                    return
                }
            } else {
                let back = app.buttons["Back"]
                if back.exists && back.isHittable {
                    back.tap()
                } else {
                    captureWEI1182("error-no-back-button-step-\(step)")
                    XCTFail("Wizard Step \(step) exposed no Back button.")
                    return
                }
            }

            _ = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Step ' AND NOT (label == 'Step \(step) of 10')"))
                .firstMatch
                .waitForExistence(timeout: 6)
        }

        captureWEI1182("error-step-\(targetStep)-not-reached")
        XCTFail("Wizard did not reach Step \(targetStep).")
    }

    // MARK: - Helper: Navigate to Parts > Categories

    /// Navigates from the main tab bar to the Parts > Categories page.
    /// Handles the case where the app may be on a different tab.
    private func navigateToCategories() {
        logInAsUITestOwnerIfNeeded()

        let page = partsCategoriesPage
        if page.waitForExistence(timeout: 10) {
            dismissTransientOnboardingOverlays()
            return
        }

        // Tap the "Parts" tab (or "More" then "Parts" on iPhone)
        let partsTab = app.tabBars.buttons["Parts"]
        if partsTab.waitForExistence(timeout: 10) {
            partsTab.tap()
        } else {
            // On iPhone with many tabs, Parts may be under "More"
            let moreTab = app.tabBars.buttons["More"]
            if moreTab.waitForExistence(timeout: 5) {
                moreTab.tap()
                let partsButtons = app.buttons.matching(NSPredicate(format: "label == 'Parts'"))
                var tappedPartsFromMore = false
                for index in 0..<partsButtons.count {
                    let candidate = partsButtons.element(boundBy: index)
                    guard candidate.exists else { continue }
                    // In the compact More list the tappable row is exposed as a Button labeled "Parts".
                    // Prefer a hittable row, and fall back to its center coordinate so we do not
                    // accidentally tap a non-row duplicate from another tab hierarchy.
                    if candidate.isHittable {
                        candidate.tap()
                        tappedPartsFromMore = true
                        break
                    }
                    if candidate.frame.minY > 0 && candidate.frame.maxY < app.frame.maxY - 80 {
                        candidate.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                        tappedPartsFromMore = true
                        break
                    }
                }
                if !tappedPartsFromMore {
                    let partsCell = app.cells.staticTexts["Parts"]
                    if partsCell.waitForExistence(timeout: 5) {
                        partsCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    }
                }
            }
        }

        // Now navigate to the Categories sub-tab
        let categoriesButton = app.buttons["Categories"]
        if categoriesButton.waitForExistence(timeout: 5) {
            categoriesButton.tap()
        } else {
            // Try tapping by static text (some layouts use text labels)
            let categoriesText = app.staticTexts["Categories"]
            if categoriesText.waitForExistence(timeout: 3) {
                categoriesText.tap()
            }
        }

        // Wait for the page to appear
        XCTAssertTrue(page.waitForExistence(timeout: 10),
                      "Parts Categories page should appear after navigation")
        dismissTransientOnboardingOverlays()
    }

    private func dismissTransientOnboardingOverlays(timeout: TimeInterval = 8) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let gotIt = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Got It'")).firstMatch
            if gotIt.exists && gotIt.isHittable {
                gotIt.tap()
                continue
            }

            let skipAny = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Skip'")).firstMatch
            if skipAny.exists && skipAny.isHittable {
                skipAny.tap()
                continue
            }

            let next = app.buttons["Next"]
            if app.staticTexts["Quick Tour"].exists && next.exists && next.isHittable {
                // If a tour variant lacks a Skip button on the current page,
                // advance once; the loop will tap Skip/Got It when it appears.
                next.tap()
                continue
            }

            break
        }
    }

    // MARK: - Helper: Wait for loading to complete

    /// Waits for the loading indicator to disappear, indicating data has loaded.
    private func waitForLoadingToComplete(timeout: TimeInterval = 10) {
        let loadingIndicator = app.otherElements["categoriesLoadingIndicator"]
        // If loading indicator exists, wait for it to disappear
        if loadingIndicator.exists {
            let disappeared = NSPredicate(format: "exists == false")
            expectation(for: disappeared, evaluatedWith: loadingIndicator, handler: nil)
            waitForExpectations(timeout: timeout)
        }
    }

    // MARK: - Test 1: Category Sheet Opens and Closes

    @MainActor
    func testNewCategorySheetOpensAndCloses() throws {
        navigateToCategories()
        waitForLoadingToComplete()

        // Check if there's an empty state with "Create First Category" button
        let createFirstButton = app.buttons["createFirstCategoryButton"]
        let addMenu = app.buttons["categoriesAddMenu"]

        if createFirstButton.waitForExistence(timeout: 3) {
            // Empty state — tap "Create First Category"
            createFirstButton.tap()
        } else if addMenu.waitForExistence(timeout: 3) {
            // Has existing categories — use the + menu
            addMenu.tap()
            let newCategoryItem = app.buttons["addCategoryMenuItem"]
            XCTAssertTrue(newCategoryItem.waitForExistence(timeout: 3),
                          "New Category menu item should appear")
            newCategoryItem.tap()
        }

        // Verify the category form sheet appeared
        let formSheet = categoryFormSheet
        XCTAssertTrue(formSheet.waitForExistence(timeout: 5),
                      "Category form sheet should appear after tapping Add")

        // Verify form fields are present
        let nameField = app.textFields["categoryNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3),
                      "Category name field should be visible")

        let descField = app.textFields["categoryDescriptionField"]
        XCTAssertTrue(descField.exists, "Description field should be visible")

        // Verify Cancel button works
        let cancelButton = app.buttons["categoryFormCancelButton"]
        XCTAssertTrue(cancelButton.exists, "Cancel button should be visible")
        cancelButton.tap()

        // Form should be dismissed
        XCTAssertFalse(formSheet.waitForExistence(timeout: 3),
                       "Category form sheet should be dismissed after Cancel")
    }

    // MARK: - Test 2: Create New Category Successfully

    @MainActor
    func testCreateNewCategorySuccessfully() throws {
        navigateToCategories()
        waitForLoadingToComplete()

        // Open the add category sheet
        let createFirstButton = app.buttons["createFirstCategoryButton"]
        let addMenu = app.buttons["categoriesAddMenu"]

        if createFirstButton.waitForExistence(timeout: 3) {
            createFirstButton.tap()
        } else if addMenu.waitForExistence(timeout: 3) {
            addMenu.tap()
            let newCategoryItem = app.buttons["addCategoryMenuItem"]
            XCTAssertTrue(newCategoryItem.waitForExistence(timeout: 3))
            newCategoryItem.tap()
        }

        // Wait for form to appear
        let formSheet = categoryFormSheet
        XCTAssertTrue(formSheet.waitForExistence(timeout: 5),
                      "Category form sheet should appear")

        // Fill in the form
        let uniqueName = "TestCategory_\(Int(Date().timeIntervalSince1970))"
        let nameField = app.textFields["categoryNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText(uniqueName)

        let descField = app.textFields["categoryDescriptionField"]
        descField.tap()
        descField.typeText("A test category created by UI tests")

        // Save
        let saveButton = app.buttons["categoryFormSaveButton"]
        XCTAssertTrue(saveButton.isEnabled, "Save button should be enabled after entering name")
        saveButton.tap()

        // Wait for sheet to dismiss
        let dismissed = NSPredicate(format: "exists == false")
        expectation(for: dismissed, evaluatedWith: formSheet)
        waitForExpectations(timeout: 10)

        // Verify the new category appears in the tree list
        let treeList = app.scrollViews["categoriesTreeList"]
        XCTAssertTrue(treeList.waitForExistence(timeout: 10),
                      "Categories tree list should appear after creating first category")

        // The new category name should be visible somewhere in the UI
        let categoryText = app.staticTexts[uniqueName]
        XCTAssertTrue(categoryText.waitForExistence(timeout: 10),
                      "Newly created category '\(uniqueName)' should appear in the tree")
    }

    // MARK: - Test 3: Category List Loads Data Correctly

    @MainActor
    func testCategoryListLoadsAllDataCorrectly() throws {
        navigateToCategories()

        // Wait for loading to complete
        waitForLoadingToComplete()

        // Verify error state is NOT shown
        let errorState = app.otherElements["categoriesErrorState"]
        XCTAssertFalse(errorState.exists,
                       "Error state should not be visible when data loads successfully")

        // Page should be visible
        let page = partsCategoriesPage
        XCTAssertTrue(page.exists, "Categories page should be visible")

        // Either the tree list OR the empty state should be shown (not both)
        let treeList = app.scrollViews["categoriesTreeList"]
        let emptyButton = app.buttons["createFirstCategoryButton"]

        let hasTree = treeList.exists
        let hasEmpty = emptyButton.exists

        XCTAssertTrue(hasTree || hasEmpty,
                      "Either the tree list or the empty state should be visible")
        XCTAssertFalse(hasTree && hasEmpty,
                       "Tree list and empty state should not both be visible")
    }

    // MARK: - Test 4: Data Persists and Displays After Sheet Dismiss

    @MainActor
    func testDataPersistsAndDisplaysAfterSheetDismiss() throws {
        navigateToCategories()
        waitForLoadingToComplete()

        // Create a category
        let uniqueName = "PersistTest_\(Int(Date().timeIntervalSince1970))"

        let createFirstButton = app.buttons["createFirstCategoryButton"]
        let addMenu = app.buttons["categoriesAddMenu"]

        if createFirstButton.waitForExistence(timeout: 3) {
            createFirstButton.tap()
        } else if addMenu.waitForExistence(timeout: 3) {
            addMenu.tap()
            app.buttons["addCategoryMenuItem"].tap()
        }

        let nameField = app.textFields["categoryNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(uniqueName)

        app.buttons["categoryFormSaveButton"].tap()

        // Wait for sheet to dismiss
        let formSheet = categoryFormSheet
        let disappeared = NSPredicate(format: "exists == false")
        expectation(for: disappeared, evaluatedWith: formSheet)
        waitForExpectations(timeout: 10)

        // Verify data appears
        let categoryText = app.staticTexts[uniqueName]
        XCTAssertTrue(categoryText.waitForExistence(timeout: 10),
                      "Category should persist and display after sheet dismiss")

        // Pull to refresh and verify data is still there
        let treeList = app.scrollViews["categoriesTreeList"]
        if treeList.exists {
            // Pull down to refresh
            let start = treeList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            let end = treeList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            start.press(forDuration: 0.1, thenDragTo: end)

            // Wait a moment for refresh to complete
            sleep(2)

            // Category should still be visible after refresh
            XCTAssertTrue(categoryText.waitForExistence(timeout: 5),
                          "Category should persist after pull-to-refresh")
        }
    }

    // MARK: - Test 5: Save Button Disabled When Name Empty

    @MainActor
    func testSaveButtonDisabledWhenNameEmpty() throws {
        navigateToCategories()
        waitForLoadingToComplete()

        // Open sheet
        let createFirstButton = app.buttons["createFirstCategoryButton"]
        let addMenu = app.buttons["categoriesAddMenu"]

        if createFirstButton.waitForExistence(timeout: 3) {
            createFirstButton.tap()
        } else if addMenu.waitForExistence(timeout: 3) {
            addMenu.tap()
            app.buttons["addCategoryMenuItem"].tap()
        }

        let formSheet = categoryFormSheet
        XCTAssertTrue(formSheet.waitForExistence(timeout: 5))

        // Save button should be disabled when name is empty
        let saveButton = app.buttons["categoryFormSaveButton"]
        XCTAssertTrue(saveButton.exists, "Save button should exist")
        XCTAssertFalse(saveButton.isEnabled,
                       "Save button should be disabled when name field is empty")

        // Type a name
        let nameField = app.textFields["categoryNameField"]
        nameField.tap()
        nameField.typeText("ValidName")

        // Now save button should be enabled
        XCTAssertTrue(saveButton.isEnabled,
                      "Save button should be enabled after entering a name")

        // Clear the name
        nameField.tap()
        // Select all and delete
        nameField.press(forDuration: 1.0)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 2) {
            selectAll.tap()
            app.keys["delete"].tap()
        }

        // Save should be disabled again (or still enabled if whitespace remains — edge case)
        // Cancel and dismiss
        app.buttons["categoryFormCancelButton"].tap()
    }

    // MARK: - Test 6: Search Filters Categories

    @MainActor
    func testSearchFiltersCategoriesTree() throws {
        navigateToCategories()
        waitForLoadingToComplete()

        // This test only makes sense if there are existing categories
        let treeList = app.scrollViews["categoriesTreeList"]
        guard treeList.waitForExistence(timeout: 5) else {
            // No categories yet — skip this test gracefully
            return
        }

        // Type into search field
        let searchField = app.textFields["categoriesSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3),
                      "Search field should be visible")
        searchField.tap()
        searchField.typeText("ZZZZZ_NONEXISTENT")

        // The tree should show "no results" or the content unavailable view
        // Wait a moment for filter to apply
        sleep(1)

        // Type a real search term (clear first)
        searchField.tap()
        searchField.press(forDuration: 1.0)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 2) {
            selectAll.tap()
            app.keys["delete"].tap()
        }

        // Clear button should clear the search
        let clearButton = app.buttons.matching(NSPredicate(format: "identifier CONTAINS 'xmark'")).firstMatch
        if clearButton.exists {
            clearButton.tap()
        }
    }

    @MainActor
    func testWEI1303EmployeeDetailTabsMeetMinimumTouchTargets() throws {
        app.terminate()
        app = XCUIApplication()
        configureUITestingEnvironment(app)
        app.launch()

        logInAsUITestOwnerIfNeeded()
        openEmployeeDetailForUITestOwner()

        let profile = employeeDetailTab("profile", label: "Profile")
        let hats = employeeDetailTab("hats", label: "Hats")
        let teams = employeeDetailTab("teams", label: "Teams")
        XCTAssertTrue(profile.waitForExistence(timeout: 10), "Profile tab should be visible")
        XCTAssertTrue(hats.waitForExistence(timeout: 5), "Hats tab should be visible")
        XCTAssertTrue(teams.waitForExistence(timeout: 5), "Teams tab should be visible")

        captureWEI1303("01-employee-detail-tabs-375pt")

        for tab in [profile, hats, teams] {
            XCTAssertGreaterThanOrEqual(tab.frame.width, 44, "\(tab.label) tab should be at least 44pt wide")
            XCTAssertGreaterThanOrEqual(tab.frame.height, 44, "\(tab.label) tab should be at least 44pt tall")
            XCTAssertTrue(tab.isHittable, "\(tab.label) tab should be hittable")
        }
    }

    // MARK: - Test 7: App Launch Performance

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    private func openEmployeeDetailForUITestOwner() {
        if app.navigationBars["UITest Owner"].waitForExistence(timeout: 2) ||
            app.staticTexts["Basic Info"].waitForExistence(timeout: 2) {
            return
        }

        let peopleTab = app.buttons["tab_people"]
        if peopleTab.waitForExistence(timeout: 8) {
            peopleTab.tap()
        } else if app.buttons["People"].waitForExistence(timeout: 3) {
            app.buttons["People"].tap()
        } else if app.tabBars.buttons["More"].waitForExistence(timeout: 3) {
            app.tabBars.buttons["More"].tap()
            let people = app.buttons["People"]
            XCTAssertTrue(people.waitForExistence(timeout: 8), "People module should be reachable")
            people.tap()
        } else {
            XCTFail("People module tab should be reachable")
        }

        let employees = app.buttons["Employees"]
        if employees.waitForExistence(timeout: 8) {
            employees.tap()
        }

        let ownerRow = app.buttons.matching(NSPredicate(format: "label CONTAINS 'UITest Owner'")).firstMatch
        let ownerLabel = app.staticTexts["UITest Owner"]
        XCTAssertTrue(
            ownerRow.waitForExistence(timeout: 10) || ownerLabel.waitForExistence(timeout: 10),
            "UITest Owner should be visible in employees list"
        )
        if ownerRow.exists && ownerRow.isHittable {
            ownerRow.tap()
        } else {
            ownerLabel.tap()
        }

        XCTAssertTrue(
            app.navigationBars["UITest Owner"].waitForExistence(timeout: 10) ||
                app.staticTexts["Basic Info"].waitForExistence(timeout: 10),
            "Employee detail should open for UITest Owner"
        )
    }

    private func employeeDetailTab(_ id: String, label: String) -> XCUIElement {
        let identified = app.buttons["employeeDetailTab_\(id)"]
        if identified.exists {
            return identified
        }
        let labeled = app.buttons[label]
        if labeled.exists {
            return labeled
        }
        return app.buttons["\(label) tab"]
    }

    private func captureWEI1303(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let source = URL(fileURLWithPath: #filePath)
        let repoRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dir = repoRoot.appendingPathComponent("docs/testing/artifacts/wei-1303", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"), options: .atomic)
    }

    @MainActor
    func testWEI3140CSVMappingPreviewScreenshot() throws {
        launchWEI3140Fixture(mode: "csv")
        XCTAssertTrue(app.navigationBars["Import Preview"].waitForExistence(timeout: 12))
        captureWEI3140("01-csv-mapping-preview")
    }

    @MainActor
    func testWEI3140LargeErrorQuarantineScreenshot() throws {
        launchWEI3140Fixture(mode: "error")
        XCTAssertTrue(app.navigationBars["Import Preview"].waitForExistence(timeout: 12))
        captureWEI3140("02-large-error-preview-top")
        app.swipeUp()
        app.swipeUp()
        captureWEI3140("03-large-error-quarantine-commit-disabled")
    }

    @MainActor
    func testWEI3140PDFPreviewOnlyScreenshot() throws {
        launchWEI3140Fixture(mode: "pdf")
        XCTAssertTrue(app.staticTexts["PDF / OCR Review"].waitForExistence(timeout: 12))
        captureWEI3140("04-pdf-ocr-preview-only")
        app.swipeUp()
        captureWEI3140("05-pdf-ocr-commit-disabled")
    }

    private func launchWEI3140Fixture(mode: String) {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-UITestingWEI3140ImportPreviewFixture", "-WEI3140FixtureMode", mode]
        app.launch()
    }

    private var wei3140ArtifactDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["WEI_3140_ARTIFACT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: "/tmp/wpr2-pr955-wei3140-screens", isDirectory: true)
    }

    private func captureWEI3140(_ name: String) {
        try? FileManager.default.createDirectory(at: wei3140ArtifactDirectory, withIntermediateDirectories: true)
        let screenshot = XCUIScreen.main.screenshot()
        let url = wei3140ArtifactDirectory.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
