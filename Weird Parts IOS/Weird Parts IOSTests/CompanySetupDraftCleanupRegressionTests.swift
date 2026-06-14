import XCTest

/// Regression tests for GitHub #950 / WEI-3586.
///
/// CompanySetupWizard must not mark setup complete while silently swallowing
/// deleteSetupDraft failures; otherwise stale setup drafts can remain hidden
/// behind hasCompletedCompanySetup=true.
final class CompanySetupDraftCleanupRegressionTests: XCTestCase {

    func testCompletionPathsDoNotSetCompletionFlagDirectly() throws {
        let source = try Self.readCompanySetupWizardSource()

        XCTAssertFalse(
            source.contains("cleanupDraft()\n                    hasCompletedCompanySetup = true"),
            "Exit/continue path must not set hasCompletedCompanySetup immediately after cleanupDraft(); cleanup success must gate completion."
        )
        XCTAssertFalse(
            source.contains("cleanupDraft()\n                hasCompletedCompanySetup = true"),
            "Dashboard completion path must not set hasCompletedCompanySetup immediately after cleanupDraft(); cleanup success must gate completion."
        )
    }

    func testCleanupDraftFailureIsUserVisibleAndNotSwallowed() throws {
        let source = try Self.readCompanySetupWizardSource()

        XCTAssertFalse(
            source.contains("try? appCore.settingsService?.deleteSetupDraft()"),
            "deleteSetupDraft failures must not be swallowed with try?."
        )
        XCTAssertTrue(
            source.contains("completeSetupAfterDraftCleanup") || source.contains("finishSetupAfterDraftCleanup"),
            "CompanySetupWizard should route finish/skip through a helper that gates completion on draft cleanup success."
        )
        XCTAssertTrue(
            source.contains("saveError = userFriendlyError(error, context: \"clear setup draft\")"),
            "Draft cleanup failures should be surfaced through the existing Error alert instead of being hidden."
        )
    }

    private static func readCompanySetupWizardSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Auth")
            .appendingPathComponent("CompanySetupWizard.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
