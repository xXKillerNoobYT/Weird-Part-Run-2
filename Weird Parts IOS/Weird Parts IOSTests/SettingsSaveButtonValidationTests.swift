import XCTest

/// Regression tests for Scanner 5a: Settings save buttons must have a .disabled() validation guard.
///
/// Verifies that each Settings page with a Save button has the appropriate guard to prevent
/// saving invalid data or unchanged state (issue #WEI-794).
final class SettingsSaveButtonValidationTests: XCTestCase {

    // MARK: - IOSDailyReportTemplatesPage

    func testDailyReportTemplatesPageHasIsDirtyGuard() throws {
        let source = try Self.readSettingsSource("IOSDailyReportTemplatesPage.swift")

        XCTAssertTrue(
            source.contains("@State private var isDirty = false"),
            "IOSDailyReportTemplatesPage must declare isDirty state to track unsaved changes."
        )
        XCTAssertTrue(
            source.contains(".disabled(!isDirty)"),
            "IOSDailyReportTemplatesPage Save button must be disabled when no changes have been made."
        )
        XCTAssertTrue(
            source.contains(".onChange(of: sections)") && source.contains(".onChange(of: aiInstructions)"),
            "IOSDailyReportTemplatesPage must watch sections and aiInstructions to set isDirty."
        )
        XCTAssertTrue(
            source.contains("isDirty = false"),
            "IOSDailyReportTemplatesPage must reset isDirty after save and after load."
        )
    }

    // MARK: - IOSToolPoliciesPage

    func testToolPoliciesPageHasIsDirtyGuard() throws {
        let source = try Self.readSettingsSource("IOSToolPoliciesPage.swift")

        XCTAssertTrue(
            source.contains("@State private var isDirty = false"),
            "IOSToolPoliciesPage must declare isDirty state to track unsaved changes."
        )
        XCTAssertTrue(
            source.contains(".disabled(!isDirty)"),
            "IOSToolPoliciesPage Save button must be disabled when no changes have been made."
        )
        XCTAssertTrue(
            source.contains(".onChange(of: maxCheckoutDays)"),
            "IOSToolPoliciesPage must watch maxCheckoutDays to set isDirty."
        )
        XCTAssertTrue(
            source.contains("isDirty = false"),
            "IOSToolPoliciesPage must reset isDirty after save and after load."
        )
    }

    // MARK: - IOSForecastSettingsPage

    func testForecastSettingsPageHasValidSettingsGuard() throws {
        let source = try Self.readSettingsSource("IOSForecastSettingsPage.swift")

        XCTAssertTrue(
            source.contains("private var hasValidSettings: Bool"),
            "IOSForecastSettingsPage must declare a hasValidSettings computed property."
        )
        XCTAssertTrue(
            source.contains("commonMinMult > 0") && source.contains("criticalMinMult > 0"),
            "IOSForecastSettingsPage hasValidSettings must check that all multipliers are non-zero."
        )
        XCTAssertTrue(
            source.contains(".disabled(!hasValidSettings)"),
            "IOSForecastSettingsPage Save button must be disabled when multipliers are invalid."
        )
    }

    // MARK: - IOSOrganizationThresholdsPage

    func testOrganizationThresholdsPageHasValidSettingsGuard() throws {
        let source = try Self.readSettingsSource("IOSOrganizationThresholdsPage.swift")

        XCTAssertTrue(
            source.contains("private var hasValidSettings: Bool"),
            "IOSOrganizationThresholdsPage must declare a hasValidSettings computed property."
        )
        XCTAssertTrue(
            source.contains("baseDecayRate > 0") && source.contains("movementDecayFactor > 0"),
            "IOSOrganizationThresholdsPage hasValidSettings must check that decay rate fields are non-zero."
        )
        XCTAssertTrue(
            source.contains(".disabled(!hasValidSettings)"),
            "IOSOrganizationThresholdsPage Save button must be disabled when threshold fields are invalid."
        )
    }

    // MARK: - IOSPreTripChecklistPage

    func testPreTripChecklistPageHasIsDirtyGuard() throws {
        let source = try Self.readSettingsSource("IOSPreTripChecklistPage.swift")

        XCTAssertTrue(
            source.contains("@State private var isDirty = false"),
            "IOSPreTripChecklistPage must declare isDirty state to track unsaved changes."
        )
        XCTAssertTrue(
            source.contains(".disabled(!isDirty)"),
            "IOSPreTripChecklistPage Save button must be disabled when no changes have been made."
        )
        XCTAssertTrue(
            source.contains(".onChange(of: checklists)"),
            "IOSPreTripChecklistPage must watch the checklists dictionary to set isDirty."
        )
        XCTAssertTrue(
            source.contains("isDirty = false"),
            "IOSPreTripChecklistPage must reset isDirty after save and after load."
        )
    }

    // MARK: - IOSDispatchPreferencesPage

    func testDispatchPreferencesPageHasIsDirtyGuard() throws {
        let source = try Self.readSettingsSource("IOSDispatchPreferencesPage.swift")

        XCTAssertTrue(
            source.contains("@State private var isDirty = false"),
            "IOSDispatchPreferencesPage must declare isDirty state to track unsaved changes."
        )
        XCTAssertTrue(
            source.contains(".disabled(!isDirty)"),
            "IOSDispatchPreferencesPage Save button must be disabled when no changes have been made."
        )
        XCTAssertTrue(
            source.contains(".onChange(of: enableAISuggestions)"),
            "IOSDispatchPreferencesPage must watch enableAISuggestions to set isDirty."
        )
        XCTAssertTrue(
            source.contains("isDirty = false"),
            "IOSDispatchPreferencesPage must reset isDirty after save and after load."
        )
    }

    // MARK: - IOSAuditSettingsPage

    func testAuditSettingsPageHasBothIsDirtyAndValidSettingsGuard() throws {
        let source = try Self.readSettingsSource("IOSAuditSettingsPage.swift")

        XCTAssertTrue(
            source.contains("@State private var isDirty = false"),
            "IOSAuditSettingsPage must declare isDirty state to track unsaved changes."
        )
        XCTAssertTrue(
            source.contains("private var hasValidSettings: Bool"),
            "IOSAuditSettingsPage must declare a hasValidSettings computed property."
        )
        XCTAssertTrue(
            source.contains("misplacementPenalty > 0"),
            "IOSAuditSettingsPage hasValidSettings must require misplacementPenalty to be positive."
        )
        XCTAssertTrue(
            source.contains(".disabled(!isDirty || !hasValidSettings)"),
            "IOSAuditSettingsPage Save button must be disabled when no changes made OR penalty is invalid."
        )
        XCTAssertTrue(
            source.contains(".onChange(of: misplacementPenalty)"),
            "IOSAuditSettingsPage must watch misplacementPenalty to set isDirty."
        )
        XCTAssertTrue(
            source.contains("isDirty = false"),
            "IOSAuditSettingsPage must reset isDirty after save and after load."
        )
    }

    // MARK: - Helpers

    private static func readSettingsSource(_ filename: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Settings")
            .appendingPathComponent(filename)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
