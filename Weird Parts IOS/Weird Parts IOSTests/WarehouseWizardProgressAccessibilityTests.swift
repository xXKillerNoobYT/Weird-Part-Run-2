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

    func testMovementWizardOnlyOffersCoreSupportedMovementLocations() throws {
        let source = try Self.readWarehouseSource("IOSMovementWizard.swift")
        let locationTypes = try Self.movementWizardLocationTypesSection(in: source)

        XCTAssertTrue(
            locationTypes.contains("\"warehouse\"") &&
                locationTypes.contains("\"truck\"") &&
                locationTypes.contains("\"trailer\"") &&
                locationTypes.contains("\"job\""),
            "Movement wizard should keep offering the core-supported warehouse/truck/trailer/job movement buckets."
        )
        XCTAssertFalse(
            locationTypes.contains("\"staging\"") || locationTypes.contains("\"Staging\""),
            "Movement wizard must not offer staging as a movement endpoint until WarehouseService accepts staging movement paths."
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
