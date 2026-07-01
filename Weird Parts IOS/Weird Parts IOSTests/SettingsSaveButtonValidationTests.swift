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
        XCTAssertTrue(
            source.contains("@State private var saveSuccessMessage: String?"),
            "IOSToolPoliciesPage must declare a success state so saves get positive feedback."
        )
        XCTAssertTrue(
            source.contains("Label(saveSuccessMessage, systemImage: \"checkmark.circle.fill\")") &&
                source.contains(".foregroundStyle(.green)"),
            "IOSToolPoliciesPage must show a visible green success confirmation after a successful save."
        )
        XCTAssertTrue(
            source.contains("saveSuccessMessage = \"Tool policies saved.\"") &&
                source.contains("saveSuccessMessage = nil") &&
                source.contains("private func markDirty()"),
            "IOSToolPoliciesPage must set success on save and clear stale success when fields change or a new save starts."
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

    // MARK: - IOSJobStageTemplatesSettingsPage

    func testJobStageTemplateAlertsRejectBlankNamesBeforeDismissal() throws {
        let source = try Self.readSettingsSource("IOSJobStageTemplatesSettingsPage.swift")

        XCTAssertTrue(
            source.contains("private var trimmedNewTemplateName: String") &&
                source.contains("private var trimmedRenameTemplateName: String") &&
                source.contains("private var trimmedDuplicateTemplateName: String"),
            "Job stage template alerts should centralize whitespace-trimmed names for create, rename, and duplicate actions."
        )
        XCTAssertTrue(
            source.contains("private var canCreateTemplate: Bool { !trimmedNewTemplateName.isEmpty }") &&
                source.contains("private var canRenameTemplate: Bool { !trimmedRenameTemplateName.isEmpty }") &&
                source.contains("private var canDuplicateTemplate: Bool { !trimmedDuplicateTemplateName.isEmpty }"),
            "Job stage template alerts should expose validity flags so blank names cannot be submitted."
        )
        XCTAssertTrue(
            source.contains("Button(\"Create\") { createTemplate() }\n                .disabled(!canCreateTemplate)") &&
                source.contains("Button(\"Duplicate\") { duplicateTemplate() }\n                .disabled(!canDuplicateTemplate)") &&
                source.contains("Button(\"Rename\") { renameTemplate() }\n                .disabled(!canRenameTemplate)"),
            "Create, duplicate, and rename alert actions should stay disabled while their names are blank or whitespace-only."
        )
        XCTAssertTrue(
            source.contains("Enter a template name before creating this workflow.") &&
                source.contains("Enter a new template name before duplicating this workflow.") &&
                source.contains("Enter a template name before renaming this workflow."),
            "Each alert should provide visible validation copy instead of dismissing to a hidden page-level error."
        )
        XCTAssertTrue(
            source.contains("guard canCreateTemplate else { return }") &&
                source.contains("guard canRenameTemplate else { return }") &&
                source.contains("guard canDuplicateTemplate else { return }"),
            "Template actions should keep defensive guards so invalid names never reach JobsService."
        )
        XCTAssertTrue(
            source.contains("name: templateName") &&
                source.contains("let templateName = trimmedNewTemplateName") &&
                source.contains("let templateName = trimmedRenameTemplateName") &&
                source.contains("let templateName = trimmedDuplicateTemplateName"),
            "Template actions should pass trimmed names to JobsService after validation."
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

    // MARK: - Settings persisted value parsing

    func testSettingsPagesUseStrictPersistedValueParser() throws {
        let pages = [
            "IOSAuditSettingsPage.swift",
            "IOSDispatchPreferencesPage.swift",
            "IOSForecastSettingsPage.swift",
            "IOSOrganizationThresholdsPage.swift",
            "IOSToolPoliciesPage.swift",
        ]

        for page in pages {
            let source = try Self.readSettingsSource(page)
            XCTAssertTrue(
                source.contains("try SettingsValueParser."),
                "\(page) must parse persisted numeric and boolean settings through SettingsValueParser so malformed saved values surface as load errors."
            )
            XCTAssertFalse(
                source.contains("Int(map[") || source.contains("Double(map[") || source.contains("] ?? \"true\") == \"true\"") || source.contains("] ?? \"false\") == \"true\""),
                "\(page) must not silently coerce malformed persisted settings to fallback defaults."
            )
        }
    }

    func testSettingsValueParserDistinguishesMissingFromMalformedValues() throws {
        let source = try Self.readSettingsSource("SettingsValueParser.swift")

        XCTAssertTrue(
            source.contains("guard let rawValue = map[key] else { return defaultValue }"),
            "SettingsValueParser must continue allowing missing values to use page defaults."
        )
        XCTAssertTrue(
            source.contains("throw ParseError.invalidValue") && source.contains("Saved setting") && source.contains("Fix or reset this setting before saving"),
            "SettingsValueParser must throw a visible validation error for present-but-malformed values before a page can overwrite them."
        )
        XCTAssertTrue(
            source.contains("case \"true\"") && source.contains("case \"false\"") && source.contains("expectedType: \"true/false\""),
            "SettingsValueParser must validate persisted booleans instead of treating every non-true value as false."
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
