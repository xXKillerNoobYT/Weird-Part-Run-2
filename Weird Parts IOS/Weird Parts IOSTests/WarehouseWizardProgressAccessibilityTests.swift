import XCTest

/// Regression coverage for GitHub #1005 / WEI-3575.
///
/// The warehouse setup wizards should not expose their progress dots as tiny
/// gesture-only circles. They must route through a real 44×44 button with
/// VoiceOver label/value/hint/selected-state semantics.
final class WarehouseWizardProgressAccessibilityTests: XCTestCase {
    func testSharedProgressStepControlProvidesMinimumHitTargetAndAccessibilitySemantics() throws {
        let source = try Self.readWarehouseSource("WarehouseWizardProgressStepButton.swift")

        XCTAssertTrue(
            source.contains("Button {") || source.contains("Button(action:"),
            "Progress dots must be real Buttons, not gesture-only shapes."
        )
        XCTAssertTrue(
            source.contains(".frame(width: 44, height: 44)") || source.contains(".frame(minWidth: 44, minHeight: 44)"),
            "The shared progress step control must provide at least a 44×44 pt tappable target."
        )
        XCTAssertTrue(source.contains(".accessibilityLabel"), "VoiceOver needs a clear step label.")
        XCTAssertTrue(source.contains(".accessibilityValue"), "VoiceOver needs current/completed/available state.")
        XCTAssertTrue(source.contains(".accessibilityHint"), "VoiceOver needs guidance for whether the step can be opened.")
        XCTAssertTrue(
            source.contains(".accessibilityAddTraits(isCurrent ? .isSelected : [])"),
            "The current step must expose selected state."
        )
    }

    func testPartsFlowWizardUsesSharedAccessibleProgressStepControl() throws {
        let source = try Self.readWarehouseSource("PartsFlowWizard.swift")
        let progressSection = try Self.progressBarSection(in: source)

        XCTAssertTrue(
            progressSection.contains("WarehouseWizardProgressStepButton"),
            "Parts-first setup progress dots should use the shared accessible 44×44 button control."
        )
        XCTAssertFalse(
            progressSection.contains(".onTapGesture"),
            "Parts-first setup progress dots must not rely on gesture-only Circle tap handlers."
        )
    }

    func testPartsFlowWizardBlocksInvalidQuantitiesBeforeNavigationAndSave() throws {
        let source = try Self.readWarehouseSource("PartsFlowWizard.swift")

        XCTAssertTrue(
            source.contains("private var invalidQuantityEntries"),
            "Parts flow must collect invalid pasted/hardware-keyboard quantities instead of silently skipping them."
        )
        XCTAssertTrue(
            source.contains("validQuantity(from:") && source.contains("qty > 0"),
            "Parts flow quantities must be parsed through one positive whole-number validator before display and save."
        )
        XCTAssertTrue(
            source.contains("nonisolated private static func validQuantity"),
            "Quantity validation must opt out of SwiftUI View MainActor isolation so detached DB writes can reuse it."
        )
        XCTAssertTrue(
            source.contains("validateBeforeAdvancing()") && source.contains("guard currentStep == 2"),
            "The Next button must validate only when leaving the count step so draft errors do not trap users before Step 2."
        )
        XCTAssertTrue(
            source.contains("guard validateBeforeSaving() else { return }"),
            "Save & Exit and Finish must validate entries before writing notes or dismissing."
        )
        XCTAssertTrue(
            source.contains("parts_flow_count_validation_message"),
            "Invalid quantities need a visible, stable validation message for VoiceOver and UI automation."
        )
        XCTAssertTrue(
            source.contains("partCounts.removeValue(forKey: partId)") && source.contains("partCounts[partId] = trimmed"),
            "Quantity input should be trimmed and whitespace-only entries should clear the draft key instead of looking complete."
        )
        let draftSaveRange = try XCTUnwrap(
            source.range(of: "PartsFlowDraftStore.save(counts: partCounts, locations: partLocations, userId: userId)")
        )
        let validationGuardRange = try XCTUnwrap(
            source.range(of: "guard validateBeforeSaving() else { return }")
        )
        XCTAssertLessThan(
            draftSaveRange.lowerBound,
            validationGuardRange.lowerBound,
            "The draft should be persisted before validation blocks DB save/dismiss so in-progress edits are not lost."
        )
    }

    func testPartsFlowWizardShowsSaveSuccessOnlyAfterConfirmedWrite() throws {
        let source = try Self.readWarehouseSource("PartsFlowWizard.swift")

        XCTAssertTrue(
            source.contains("parts_flow_save_success_message"),
            "The wizard should show a visible success confirmation after save completes."
        )
        XCTAssertTrue(
            source.contains("shouldDismiss = andDismiss") && source.contains("Task.sleep") && source.contains("await MainActor.run { dismiss() }"),
            "Finish should dismiss on the MainActor only after the save task confirms no error and gives the success state a render pass."
        )
        XCTAssertTrue(
            source.contains("Task.detached(priority: .userInitiated)"),
            "The synchronous DB write loop should run off the MainActor so large inventories do not freeze SwiftUI."
        )
        XCTAssertTrue(
            source.contains("savedCount = 0") && source.contains("savedCount = result.savedEntries"),
            "Partial failures should not switch the save button into a successful saved-count state."
        )
        XCTAssertLessThan(
            source.range(of: "saveErrorMessage = nil")?.lowerBound ?? source.endIndex,
            source.range(of: "guard validateBeforeSaving() else { return }")?.lowerBound ?? source.startIndex,
            "Stale save errors should be cleared before validation can show the current validation alert."
        )
        XCTAssertTrue(
            source.contains("await MainActor.run"),
            "State updates after detached DB work should be explicitly applied on the MainActor."
        )
    }

    func testPartsFlowWizardProvidesUnconditionalCancelSeparateFromSaveAndExit() throws {
        let source = try Self.readWarehouseSource("PartsFlowWizard.swift")
        let toolbar = try Self.braceBalancedBody(after: ".toolbar", in: source)

        XCTAssertTrue(
            toolbar.contains("Button(\"Cancel\") { dismiss() }"),
            "Parts-flow setup needs an unconditional Cancel path that does not validate or save before dismissing."
        )
        XCTAssertTrue(
            toolbar.contains("Button(\"Save & Exit\")"),
            "Parts-flow setup should keep Save & Exit as the explicit validating save path."
        )
        XCTAssertLessThan(
            toolbar.range(of: "Button(\"Cancel\")")?.lowerBound ?? toolbar.endIndex,
            toolbar.range(of: "Button(\"Save & Exit\")")?.lowerBound ?? toolbar.startIndex,
            "Cancel should be the leading cancellation action, separate from Save & Exit."
        )
    }

    func testWarehouseOnboardingWizardUsesSharedAccessibleProgressStepControl() throws {
        let source = try Self.readWarehouseSource("WarehouseOnboardingWizard.swift")
        let progressSection = try Self.progressBarSection(in: source)

        XCTAssertTrue(
            progressSection.contains("WarehouseWizardProgressStepButton"),
            "Warehouse onboarding progress dots should use the shared accessible 44×44 button control."
        )
        XCTAssertFalse(
            progressSection.contains(".onTapGesture"),
            "Warehouse onboarding progress dots must not rely on gesture-only Circle tap handlers."
        )
    }

    func testWarehouseOnboardingWizardProvidesUnconditionalCancelSeparateFromSaveAndExit() throws {
        let source = try Self.readWarehouseSource("WarehouseOnboardingWizard.swift")
        let toolbar = try Self.braceBalancedBody(after: ".toolbar", in: source)

        XCTAssertTrue(
            toolbar.contains("Button(\"Cancel\") { dismiss() }"),
            "Warehouse onboarding needs an unconditional Cancel path for fresh Step 1 sessions without a progress row."
        )
        XCTAssertTrue(
            toolbar.contains("Button(\"Save & Exit\") { saveAndExit() }"),
            "Warehouse onboarding should keep Save & Exit as the explicit save path."
        )
        XCTAssertLessThan(
            toolbar.range(of: "Button(\"Cancel\")")?.lowerBound ?? toolbar.endIndex,
            toolbar.range(of: "Button(\"Save & Exit\")")?.lowerBound ?? toolbar.startIndex,
            "Cancel should be the leading cancellation action, separate from Save & Exit."
        )
    }

    func testMovementWizardLocationTilesExposeStableFromToAccessibilityTargets() throws {
        let source = try Self.readWarehouseSource("IOSMovementWizard.swift")

        XCTAssertTrue(
            source.contains("role: \"from\"") && source.contains("role: \"to\""),
            "Movement wizard must distinguish FROM and TO location tiles for user-like automation and VoiceOver."
        )
        XCTAssertTrue(
            source.contains(".accessibilityIdentifier(\"movementWizard_\\(role)_\\(type)\")"),
            "Movement wizard location tiles need stable role+type accessibility identifiers such as movementWizard_from_warehouse."
        )
        XCTAssertTrue(
            source.contains(".accessibilityLabel(\"\\(roleLabel) \\(label)\")"),
            "Movement wizard location tiles need unique spoken labels such as From Warehouse and To Truck."
        )
        XCTAssertTrue(
            source.contains("Already selected as the other side of this movement"),
            "Disabled duplicate-location tiles should explain why they cannot be selected."
        )
    }

    func testMovementWizardSelectableLocationTilesUseEnumBackedSupportedEndpoints() throws {
        let source = try Self.readWarehouseSource("IOSMovementWizard.swift")
        let locationTypes = try Self.movementWizardLocationTypesSection(in: source)

        for supportedEndpoint in ["warehouse", "truck", "trailer", "job"] {
            XCTAssertTrue(
                locationTypes.contains("WarehouseService.GuidedMovementLocationType.\(supportedEndpoint).rawValue"),
                "Movement wizard \(supportedEndpoint) tile should use the core movement location topology instead of ad hoc strings."
            )
        }
        XCTAssertNil(
            locationTypes.range(of: #"(?m)^\s*\(\s*""#, options: .regularExpression),
            "Movement wizard location tiles should not use string literals as tuple endpoints."
        )
        XCTAssertNil(
            locationTypes.range(of: #"\bstaging\b"#, options: [.regularExpression, .caseInsensitive]),
            "Movement wizard must not offer Staging as a generic movement endpoint until WarehouseService accepts staging paths."
        )
    }

    func testMovementWizardPartSelectionDismissesKeyboardBeforeNextNavigation() throws {
        let source = try Self.readWarehouseSource("IOSMovementWizard.swift")

        XCTAssertTrue(
            source.contains("@FocusState private var isPartSearchFocused"),
            "Movement wizard must track part-search focus so the iOS keyboard can be dismissed after a part is selected."
        )
        XCTAssertTrue(
            source.contains(".focused($isPartSearchFocused)"),
            "The part search field must bind to focus state for deterministic keyboard dismissal."
        )
        XCTAssertTrue(
            source.contains("isPartSearchFocused = false") && source.contains("partSearchResults = []"),
            "Selecting a part should dismiss the keyboard and collapse search results so bottom navigation remains reachable."
        )
        XCTAssertTrue(
            source.contains(".accessibilityIdentifier(\"movement_wizard_next\")"),
            "The Next button needs a stable accessibility identifier for user-like UI verification."
        )
    }

    func testModuleSidebarTabsExposeSameStableSubtabIdentifiersAsTopTabs() throws {
        let source = try Self.readNavigationSource("IOSMainView.swift")
        let sidebarStart = try XCTUnwrap(source.range(of: "private var sidebarLayout"))
        let sidebarTail = source[sidebarStart.lowerBound...]
        let sidebarEnd = sidebarTail.range(of: "/// Sidebar width adapts")?.lowerBound ?? sidebarTail.endIndex
        let sidebarSource = String(sidebarTail[..<sidebarEnd])
        let fullSidebarStart = try XCTUnwrap(source.range(of: "private func fullSidebarTabRow"))
        let fullSidebarTail = source[fullSidebarStart.lowerBound...]
        let fullSidebarEnd = fullSidebarTail.range(of: "private var fullSidebarActions")?.lowerBound ?? fullSidebarTail.endIndex
        let fullSidebarSource = String(fullSidebarTail[..<fullSidebarEnd])

        XCTAssertTrue(
            sidebarSource.contains(".accessibilityElement(children: .ignore)"),
            "Sidebar module navigation should expose the button itself as the automation target instead of its child label/icon."
        )
        XCTAssertTrue(
            sidebarSource.contains(".accessibilityIdentifier(\"subtab_\\(tab.id)\")"),
            "iPad/sidebar module navigation must expose the same stable subtab_<id> identifiers as the horizontal sub-tab picker."
        )
        XCTAssertTrue(
            fullSidebarSource.contains(".accessibilityElement(children: .ignore)"),
            "Full-sidebar module navigation should expose the button itself as the automation target instead of its child label/icon."
        )
        XCTAssertTrue(
            fullSidebarSource.contains(".accessibilityIdentifier(\"subtab_\\(tab.id)\")"),
            "Full-sidebar iPad navigation must expose the same stable subtab_<id> identifiers as the horizontal sub-tab picker."
        )
        XCTAssertTrue(
            sidebarSource.contains(".accessibilityLabel(tab.label)") && fullSidebarSource.contains(".accessibilityLabel(tab.label)"),
            "Sidebar module navigation needs the same readable labels as top tabs for VoiceOver and UI tests."
        )
        XCTAssertTrue(
            sidebarSource.contains(".contentShape(Rectangle())") && fullSidebarSource.contains(".contentShape(Rectangle())"),
            "Sidebar module navigation needs an explicit tappable hit region for user-like tests."
        )
    }

    private static func progressBarSection(in source: String) throws -> String {
        guard let start = source.range(of: "private var progressBar") else {
            XCTFail("Missing progressBar property")
            return source
        }
        let afterStart = source[start.lowerBound...]
        let end = afterStart.range(of: "// MARK: - Step 1")?.lowerBound ?? afterStart.endIndex
        return String(afterStart[..<end])
    }

    private static func movementWizardLocationTypesSection(in source: String) throws -> String {
        guard let start = source.range(of: "private let locationTypes = [") else {
            XCTFail("Missing movement wizard locationTypes list")
            return source
        }
        let afterStart = source[start.lowerBound...]
        let end = afterStart.range(of: "]")?.upperBound ?? afterStart.endIndex
        return String(afterStart[..<end])
    }

    /// Extracts the brace-balanced body that follows the first occurrence of
    /// `anchor`, so assertions stay scoped to the code under test.
    private static func braceBalancedBody(after anchor: String, in source: String) throws -> String {
        guard let anchorRange = source.range(of: anchor) else {
            throw XCTSkip("Expected anchor \(anchor) in source")
        }
        guard let openBrace = source[anchorRange.upperBound...].firstIndex(of: "{") else {
            throw XCTSkip("Expected opening brace after \(anchor)")
        }

        var depth = 0
        var index = openBrace
        while index < source.endIndex {
            let char = source[index]
            if char == "{" { depth += 1 }
            if char == "}" { depth -= 1 }
            let next = source.index(after: index)
            if depth == 0 {
                return String(source[openBrace..<next])
            }
            index = next
        }

        throw XCTSkip("Expected closing brace for \(anchor)")
    }

    private static func readWarehouseSource(
        _ fileName: String,
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Warehouse")
            .appendingPathComponent(fileName)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func readNavigationSource(
        _ fileName: String,
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Navigation")
            .appendingPathComponent(fileName)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
