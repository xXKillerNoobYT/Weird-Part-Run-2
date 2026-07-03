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
            routerSource.contains("case \"settings-bug-report\"") && routerSource.contains("BugReportComposerView("),
            "The Report a Bug settings item must route to the real bug-report composer."
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
            assistantSource.contains("showBugReport") && assistantSource.contains("Report a bug or assistant issue"),
            "The assistant must expose a direct report action for assistant mistakes or page-specific app bugs."
        )
        XCTAssertTrue(
            assistantSource.contains("source=AI Assistant") && assistantSource.contains("conversation_id"),
            "Assistant bug reports must include source/conversation context so reports are actionable."
        )
    }

    func testStartupFailureCanOpenBugReportDraft() throws {
        let appSource = try Self.readSource("App/WiredPartIOSApp.swift")
        XCTAssertTrue(
            appSource.contains("Report this startup problem") && appSource.contains("source: .launchError"),
            "The database/startup failure screen must let users self-report the exact failure instead of only retrying."
        )
    }

    func testComposerBuildsPrefilledGitHubIssueDraft() throws {
        let supportSource = try Self.readSource("Shared/BugReportSupport.swift")
        XCTAssertTrue(
            supportSource.contains("issues/new") && supportSource.contains("URLQueryItem(name: \"title\"") && supportSource.contains("URLQueryItem(name: \"body\""),
            "Bug reports must open a pre-filled GitHub issue draft with title/body details."
        )
        XCTAssertTrue(
            supportSource.contains("Category:") && supportSource.contains("App context:") && supportSource.contains("Device:"),
            "Bug report bodies must carry category, context, and device/build diagnostics."
        )
    }

    private static func readSource(_ relativePath: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
