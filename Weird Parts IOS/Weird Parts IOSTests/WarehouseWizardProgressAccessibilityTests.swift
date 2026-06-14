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

    private static func progressBarSection(in source: String) throws -> String {
        guard let start = source.range(of: "private var progressBar") else {
            XCTFail("Missing progressBar property")
            return source
        }
        let afterStart = source[start.lowerBound...]
        let end = afterStart.range(of: "// MARK: - Step 1")?.lowerBound ?? afterStart.endIndex
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
}
