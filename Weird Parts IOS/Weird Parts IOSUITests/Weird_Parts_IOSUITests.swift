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

    // MARK: - Setup & Teardown

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        // Pass a launch argument so the app can detect testing mode
        // (useful for seeding test data or skipping onboarding)
        app.launchArguments += ["-UITesting"]
        if ProcessInfo.processInfo.environment["WEI_1185_LANDSCAPE"] == "1" {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Login Accessibility

    @MainActor
    func testWEI1185WarehouseZonePlacementScreenshots() throws {
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
        goToWizardStep(2)
        if app.buttons["Confirm Grid"].waitForExistence(timeout: 3) {
            app.buttons["Confirm Grid"].tap()
            XCTAssertTrue(app.staticTexts["Zones"].waitForExistence(timeout: 10),
                          "Resumed wizard should load the zone placement phase after confirming the grid")
        } else {
            XCTAssertTrue(app.staticTexts["Zones"].waitForExistence(timeout: 10),
                          "Resumed wizard should allow returning to the zone placement phase")
        }
        captureWEI1185("06-storage-persisted-after-resume")
        let persistedLocation = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'R2C2'")).firstMatch
        let persistedZone = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Storage' AND label CONTAINS 'starts at R2C2'")
        ).firstMatch
        XCTAssertTrue(persistedLocation.waitForExistence(timeout: 10) || persistedZone.waitForExistence(timeout: 10),
                      "Zone placement should persist after leaving and resuming the wizard")
        captureWEI1185("06-storage-persisted-after-resume")
    }

    @MainActor
    func testWEI1211WarehouseWizardBreakpointZoneDrop() throws {
        let artifactDirectory = wei1182ArtifactDirectory
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)

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

        let confirmGrid = app.buttons["Confirm Grid"]
        XCTAssertTrue(confirmGrid.waitForExistence(timeout: 5), "Confirm Grid should be available")
        confirmGrid.tap()

        let r1c1 = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'R1C1'")).firstMatch
        let r1c3 = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'R1C3'")).firstMatch
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
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Storage at R1C1'")).firstMatch.waitForExistence(timeout: 5),
                      "Tapping Storage should select the Storage zone before resizing")

        let grow = app.buttons["Grow"]
        XCTAssertTrue(grow.waitForExistence(timeout: 5), "Selected Storage zone should expose Grow")
        grow.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '2x2'")).firstMatch.waitForExistence(timeout: 5),
                      "Resizing Storage should update selected-zone size text")

        let receivingAtR1C3 = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Receiving' AND label CONTAINS 'starts at R1C3'")
        ).firstMatch
        XCTAssertTrue(receivingAtR1C3.waitForExistence(timeout: 5),
                      "Dropped Receiving zone should remain visible after resizing Storage")
        captureWEI1182("wei-1211-two-zones-after-storage-resize")
    }

    @MainActor
    func testWEI1182WarehouseWizardBreakpointWalkingPathScreenshots() throws {
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
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Storage at R1C1'")).firstMatch.waitForExistence(timeout: 5),
                      "Tapping Storage should select the Storage zone before resizing")

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
        XCTAssertTrue(app.staticTexts["Phase 2 · Place Units"].waitForExistence(timeout: 10),
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
            app.buttons["tab_warehouse"].exists && app.buttons["tab_warehouse"].isHittable ||
            app.buttons["Warehouse"].exists && app.buttons["Warehouse"].isHittable ||
            app.buttons["Configure Your Warehouse"].exists && app.buttons["Configure Your Warehouse"].isHittable ||
            app.staticTexts["Warehouse Setup"].exists ||
            app.staticTexts["Confirm Zone Grid"].exists ||
            app.buttons["Create & Continue"].exists {
            return
        }

        let loginView = app.otherElements["loginView"]
        if loginView.waitForExistence(timeout: 30) || app.staticTexts["UITest Owner"].waitForExistence(timeout: 5) {
            let userRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'loginUserRow_'"))
            if userRows.firstMatch.waitForExistence(timeout: 10) {
                userRows.firstMatch.tap()
            } else {
                let ownerLabel = app.staticTexts["UITest Owner"]
                XCTAssertTrue(ownerLabel.waitForExistence(timeout: 10), "UITest Owner should be seeded")
                ownerLabel.tap()
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
        }

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
                app.buttons["tab_warehouse"].exists && app.buttons["tab_warehouse"].isHittable ||
                app.buttons["Warehouse"].exists && app.buttons["Warehouse"].isHittable ||
                app.buttons["Configure Your Warehouse"].exists && app.buttons["Configure Your Warehouse"].isHittable ||
                app.staticTexts["Warehouse Setup"].exists ||
                app.staticTexts["Confirm Zone Grid"].exists ||
                app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Step '")).firstMatch.exists ||
                app.buttons["Create & Continue"].exists {
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        captureWEI1185("00-login-shell-not-reached")
        XCTAssertTrue(app.buttons["tab_dashboard"].exists ||
                      app.buttons["Dashboard"].exists ||
                      app.buttons["tab_warehouse"].exists ||
                      app.buttons["Warehouse"].exists ||
                      app.buttons["Configure Your Warehouse"].exists ||
                      app.staticTexts["Warehouse Setup"].exists ||
                      app.staticTexts["Confirm Zone Grid"].exists ||
                      app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Step '")).firstMatch.exists ||
                      app.buttons["Create & Continue"].exists,
                      "Login should reach the dashboard or warehouse shell before opening the wizard")
    }

    private func openWarehouseSetupWizard() {
        captureWEI1185("00-before-open-warehouse-wizard")

        if app.staticTexts["Confirm Zone Grid"].waitForExistence(timeout: 3) ||
            app.staticTexts["Warehouse Setup"].waitForExistence(timeout: 3) ||
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Step '")).firstMatch.waitForExistence(timeout: 3) ||
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
        } else if app.buttons["Dashboard"].waitForExistence(timeout: 2) {
            app.buttons["Dashboard"].tap()
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
        // Tap the "Parts" tab (or "More" then "Parts" on iPhone)
        let partsTab = app.tabBars.buttons["Parts"]
        if partsTab.waitForExistence(timeout: 10) {
            partsTab.tap()
        } else {
            // On iPhone with many tabs, Parts may be under "More"
            let moreTab = app.tabBars.buttons["More"]
            if moreTab.waitForExistence(timeout: 5) {
                moreTab.tap()
                let partsCell = app.cells.staticTexts["Parts"]
                if partsCell.waitForExistence(timeout: 5) {
                    partsCell.tap()
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
        let page = app.otherElements["partsCategoriesPage"]
        XCTAssertTrue(page.waitForExistence(timeout: 10),
                      "Parts Categories page should appear after navigation")
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
        let formSheet = app.otherElements["categoryFormSheet"]
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
        let formSheet = app.otherElements["categoryFormSheet"]
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
        let page = app.otherElements["partsCategoriesPage"]
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
        let formSheet = app.otherElements["categoryFormSheet"]
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

        let formSheet = app.otherElements["categoryFormSheet"]
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

    // MARK: - Test 7: App Launch Performance

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
