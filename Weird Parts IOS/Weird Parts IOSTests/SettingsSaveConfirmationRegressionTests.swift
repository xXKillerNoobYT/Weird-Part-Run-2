import XCTest

/// Regression coverage for issue #1214: several settings editors persisted
/// successfully but showed no positive confirmation — the Save button just
/// went disabled, indistinguishable from an unsaved form.
///
/// Each page below must follow the IOSToolPoliciesPage pattern: a green
/// success label after a successful save, cleared on the next edit or error.
final class SettingsSaveConfirmationRegressionTests: XCTestCase {
    private static let pages: [(file: String, message: String, identifier: String)] = [
        ("IOSAuditSettingsPage", "Audit settings saved.", "auditSettingsSaveSuccessMessage"),
        ("IOSDispatchPreferencesPage", "Dispatch preferences saved.", "dispatchPreferencesSaveSuccessMessage"),
        ("IOSOrganizationThresholdsPage", "Organization thresholds saved.", "organizationThresholdsSaveSuccessMessage"),
        ("IOSPreTripChecklistPage", "Checklist saved.", "preTripChecklistSaveSuccessMessage"),
    ]

    func testEachPageShowsSuccessConfirmationAfterSave() throws {
        for page in Self.pages {
            let source = try Self.readSettingsSource(page.file)

            XCTAssertTrue(
                source.contains("@State private var saveSuccessMessage: String?"),
                "\(page.file) needs the saveSuccessMessage state (issue #1214)."
            )
            XCTAssertTrue(
                source.contains("saveSuccessMessage = \"\(page.message)\""),
                "\(page.file) must set its success message after a successful save."
            )
            XCTAssertTrue(
                source.contains(".accessibilityIdentifier(\"\(page.identifier)\")"),
                "\(page.file) must render the success label with a stable accessibility identifier."
            )
            XCTAssertTrue(
                source.contains("Label(saveSuccessMessage, systemImage: \"checkmark.circle.fill\")"),
                "\(page.file) should render the shared green success label pattern."
            )
        }
    }

    func testSuccessMessageClearsOnErrorAndNewEdits() throws {
        for page in Self.pages {
            let source = try Self.readSettingsSource(page.file)

            // Every catch path must drop the stale success message.
            XCTAssertTrue(
                source.contains("saveError = userFriendlyError(error, context: \"save data\")\n            saveSuccessMessage = nil"),
                "\(page.file) must clear the success message when a save fails."
            )
            // New edits must clear it too (markDirty helper or inline).
            XCTAssertTrue(
                source.contains("saveSuccessMessage = nil }")
                    || source.contains("private func markDirty() {")
                    || source.contains("isDirty = true\n            saveSuccessMessage = nil"),
                "\(page.file) must clear the success message when the user edits again."
            )
        }
    }

    private static func readSettingsSource(
        _ pageName: String,
        file: StaticString = #filePath
    ) throws -> String {
        let projectRoot = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Settings")
            .appendingPathComponent("\(pageName).swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
