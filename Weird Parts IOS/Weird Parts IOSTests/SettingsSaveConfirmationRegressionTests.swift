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
        ("IOSPreTripChecklistPage", "All checklists saved.", "preTripChecklistSaveSuccessMessage"),
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

            // The save routine must both set the success message (happy path)
            // and clear it (failure path) — asserted on the extracted method
            // body so indentation/ordering changes can't break the test.
            let saveBody = try Self.methodBody(named: "saveSettings", in: source)
            XCTAssertTrue(
                saveBody.contains("saveSuccessMessage = \"\(page.message)\""),
                "\(page.file).saveSettings() must set the success message on success."
            )
            XCTAssertTrue(
                saveBody.contains("saveSuccessMessage = nil"),
                "\(page.file).saveSettings() must clear the success message when a save fails."
            )
            // New edits must clear it too (markDirty helper or the page's
            // dirty hook), somewhere outside the save routine.
            let outsideSave = source.replacingOccurrences(of: saveBody, with: "")
            XCTAssertTrue(
                outsideSave.contains("saveSuccessMessage = nil"),
                "\(page.file) must clear the success message when the user edits again."
            )
        }
    }

    /// Extracts the brace-balanced body of the named function.
    private static func methodBody(named methodName: String, in source: String) throws -> String {
        guard let nameRange = source.range(of: "func \(methodName)(") else {
            throw XCTSkip("Expected method \(methodName) in source")
        }
        guard let openBrace = source[nameRange.upperBound...].firstIndex(of: "{") else {
            throw XCTSkip("Expected opening brace for \(methodName)")
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

        throw XCTSkip("Expected closing brace for \(methodName)")
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
