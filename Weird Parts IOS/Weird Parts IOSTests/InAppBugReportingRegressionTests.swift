import XCTest

/// Regression coverage for GH #574: users need first-class app paths to report
/// bugs / feature requests from Settings, the AI assistant, and startup failure UI.
final class InAppBugReportingRegressionTests: XCTestCase {
    func testSettingsExposesReportABugRoute() throws {
        let menuSource = try Self.readSource("Navigation/UserMenuSheet.swift")
        XCTAssertTrue(
            menuSource.contains("settings-bug-report") && menuSource.contains("Report a Bug"),
            "Settings must expose a visible Report a Bug entry instead of leaving feedback buried outside the app."
        )

        let routerSource = try Self.readSource("Features/Settings/SettingsRouter.swift")
        XCTAssertTrue(
            routerSource.contains("case \"settings-bug-report\"") && routerSource.contains("ReportABugPage(originModule: \"Settings\")"),
            "The Report a Bug settings item must route to the real bug-report page."
        )

        let contentRouterSource = try Self.readSource("Navigation/IOSContentRouter.swift")
        XCTAssertTrue(
            contentRouterSource.contains("/settings/bug-report") && contentRouterSource.contains("settings-bug-report"),
            "Deep links/search navigation must be able to open the bug-report settings route."
        )
    }

    func testAssistantHasBugReportEntryPointWithContext() throws {
        let assistantSource = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        XCTAssertTrue(
            assistantSource.contains("isBugReportPresented") && assistantSource.contains("ReportABugPage(originModule: activeModuleName)"),
            "The assistant must expose a direct report action for assistant mistakes or page-specific app bugs."
        )
        XCTAssertTrue(
            assistantSource.contains("activeModuleName") && assistantSource.contains("HelpContentRegistry.helpFor"),
            "Assistant bug reports must include the active module/page context so reports are actionable."
        )
    }

    func testStartupFailureCanOpenBugReportDraft() throws {
        let appSource = try Self.readSource("App/WiredPartIOSApp.swift")
        XCTAssertTrue(
            appSource.contains("Report this startup problem") && appSource.contains("ReportABugPage(originModule: \"Startup\")"),
            "The database/startup failure screen must let users self-report the exact failure instead of only retrying."
        )

        let appCoreSource = try Self.readSource("App/AppCore.swift")
        XCTAssertTrue(
            appCoreSource.contains("BugReportErrorLog.shared.record(loadError, context: \"App startup\")"),
            "Startup failures must be recorded so the startup report includes the exact failure details."
        )
    }

    func testReporterBuildsPrefilledGitHubIssueDraft() throws {
        let pageSource = try Self.readSource("Features/Settings/ReportABugPage.swift")
        XCTAssertTrue(
            pageSource.contains("Open GitHub issue") && pageSource.contains("githubURL"),
            "Bug reports must expose a pre-filled GitHub issue draft."
        )

        let composerSource = try Self.readProjectFile("core/Sources/WiredPartCore/BugReportComposer.swift")
        XCTAssertTrue(
            composerSource.contains("issues/new") && composerSource.contains("URLQueryItem(name: \"title\"") && composerSource.contains("URLQueryItem(name: \"body\""),
            "Bug reports must open a pre-filled GitHub issue draft with title/body details."
        )
        XCTAssertTrue(
            composerSource.contains("Device:") && composerSource.contains("Page/module:") && composerSource.contains("Recent errors"),
            "Bug report bodies must carry page, recent-error, and device/build diagnostics."
        )
    }

    private static func readSource(_ relativePath: String, file: StaticString = #filePath) throws -> String {
        let projectRoot = try projectRoot(file: file)
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func readProjectFile(_ relativePath: String, file: StaticString = #filePath) throws -> String {
        let sourceURL = try projectRoot(file: file)
            .appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func projectRoot(file: StaticString = #filePath) throws -> URL {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        return testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
            .deletingLastPathComponent() // repository root
    }
}
