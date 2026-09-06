import XCTest
@testable import WiredPartCore

final class BugReportComposerTests: XCTestCase {
    private func makeContext(
        currentModule: String? = "Settings > About",
        recentErrors: [BugReportComposer.ErrorEntry] = [],
        appBuild: String = "128",
        launchError: String? = nil,
        isIOSAppOnMac: Bool = false
    ) -> BugReportComposer.Context {
        BugReportComposer.Context(
            deviceModel: "iPhone 15 Pro",
            systemVersion: "iOS 18.2",
            isIOSAppOnMac: isIOSAppOnMac,
            appVersion: "1.4.0",
            appBuild: appBuild,
            coreVersion: "1.0.0",
            currentModule: currentModule,
            launchError: launchError,
            recentErrors: recentErrors
        )
    }

    // MARK: - Title

    func testTitleUsesTrimmedUserTitleWhenProvided() {
        let title = BugReportComposer.title(
            userTitle: "  Sync spins forever  ",
            context: makeContext()
        )
        XCTAssertEqual(title, "Sync spins forever")
    }

    func testTitleFallsBackToModuleWhenUserTitleBlank() {
        let title = BugReportComposer.title(userTitle: "   ", context: makeContext())
        XCTAssertEqual(title, "[Beta] Bug in Settings > About")
    }

    func testTitleFallsBackToGenericWhenModuleMissing() {
        let title = BugReportComposer.title(
            userTitle: nil,
            context: makeContext(currentModule: nil)
        )
        XCTAssertEqual(title, "[Beta] Bug report")
    }

    func testTitleTreatsBlankModuleAsMissing() {
        let title = BugReportComposer.title(
            userTitle: nil,
            context: makeContext(currentModule: "   ")
        )
        XCTAssertEqual(title, "[Beta] Bug report")
    }

    // MARK: - Body

    func testBodyIncludesEnvironmentAndDescription() {
        let body = BugReportComposer.body(
            description: "Tapped save and nothing happened.",
            context: makeContext()
        )
        XCTAssertTrue(body.contains("Tapped save and nothing happened."))
        XCTAssertTrue(body.contains("- App version: 1.4.0 (128)"))
        XCTAssertTrue(body.contains("- Core version: 1.0.0"))
        XCTAssertTrue(body.contains("- Device: iPhone 15 Pro"))
        XCTAssertTrue(body.contains("- OS: iOS 18.2"))
        XCTAssertTrue(body.contains("- iOS app on Mac: No"))
        XCTAssertTrue(body.contains("- Page/module: Settings > About"))
    }

    func testStartupErrorAndEnvironmentReachShareTextAndGithubBodyWithoutDatabase() throws {
        let exactError = "WiredPartCore.CipherKeyError 2: Keychain access failed for cipher salt (OSStatus -25308)"
        let context = makeContext(
            currentModule: "Startup",
            launchError: exactError,
            isIOSAppOnMac: true
        )

        // This is the exact text handed to the system share sheet. Context is
        // constructed directly, so the diagnostic path has no database dependency.
        let shareText = BugReportComposer.body(description: nil, context: context)
        XCTAssertTrue(shareText.contains("### Startup error"))
        XCTAssertTrue(shareText.contains("WiredPartCore.CipherKeyError"))
        XCTAssertTrue(shareText.contains("OSStatus -25308"))
        XCTAssertFalse(shareText.contains("Keychain access failed for cipher salt"))
        XCTAssertTrue(shareText.contains("- Device: iPhone 15 Pro"))
        XCTAssertTrue(shareText.contains("- OS: iOS 18.2"))
        XCTAssertTrue(shareText.contains("- iOS app on Mac: Yes"))

        let url = try XCTUnwrap(
            BugReportComposer.githubIssueURL(
                userTitle: nil,
                description: nil,
                context: context
            )
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let githubBody = try XCTUnwrap(
            components.queryItems?.first { $0.name == "body" }?.value
        )
        XCTAssertEqual(githubBody, shareText)
        XCTAssertTrue(githubBody.contains("WiredPartCore.CipherKeyError"))
        XCTAssertTrue(githubBody.contains("OSStatus -25308"))
        XCTAssertFalse(githubBody.contains("Keychain access failed for cipher salt"))
        XCTAssertTrue(githubBody.contains("- Device: iPhone 15 Pro"))
        XCTAssertTrue(githubBody.contains("- OS: iOS 18.2"))
        XCTAssertTrue(githubBody.contains("- iOS app on Mac: Yes"))
    }

    func testBodyUsesPlaceholderWhenDescriptionBlank() {
        let body = BugReportComposer.body(description: "   ", context: makeContext())
        XCTAssertTrue(body.contains(BugReportComposer.descriptionPlaceholder))
    }

    func testStartupErrorRedactsPathsCredentialsAndRowContentsFromOutboundReports() throws {
        let unsafeError = """
        GRDB.DatabaseError Code=19 at /Users/tester/Library/private.sqlite \
        row={name: AliceError, pin=1234, token=SECRET-ABC123}
        """
        let context = makeContext(
            currentModule: "Startup",
            recentErrors: [.init(message: unsafeError)],
            launchError: unsafeError
        )

        let shareText = BugReportComposer.body(description: nil, context: context)
        XCTAssertTrue(shareText.contains("GRDB.DatabaseError"))
        XCTAssertTrue(shareText.contains("Code=19"))
        XCTAssertFalse(shareText.contains("/Users/tester"))
        XCTAssertFalse(shareText.contains("private.sqlite"))
        XCTAssertFalse(shareText.contains("AliceError"))
        XCTAssertFalse(shareText.contains("1234"))
        XCTAssertFalse(shareText.contains("SECRET-ABC123"))
        XCTAssertFalse(shareText.contains("### Recent errors"))

        let url = try XCTUnwrap(
            BugReportComposer.githubIssueURL(
                userTitle: nil,
                description: nil,
                context: context
            )
        )
        let decodedBody = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "body" }?.value
        )
        XCTAssertEqual(decodedBody, shareText)
    }

    func testUnknownStartupErrorUsesFixedRedactedFallback() {
        let body = BugReportComposer.body(
            description: nil,
            context: makeContext(
                currentModule: "Startup",
                launchError: "database row contained private customer details"
            )
        )

        XCTAssertTrue(body.contains("Startup failed — details redacted"))
        XCTAssertFalse(body.contains("private customer details"))
    }

    func testWhitespaceLaunchErrorDoesNotSuppressRecentErrors() throws {
        for launchError in ["", " \t\n\r "] {
            let context = makeContext(
                currentModule: "Startup",
                recentErrors: [.init(message: "Network timeout")],
                launchError: launchError
            )

            let shareText = BugReportComposer.body(description: nil, context: context)
            XCTAssertFalse(shareText.contains("### Startup error"))
            XCTAssertTrue(shareText.contains("### Recent errors"))
            XCTAssertTrue(shareText.contains("Network timeout"))

            let url = try XCTUnwrap(
                BugReportComposer.githubIssueURL(
                    userTitle: nil,
                    description: nil,
                    context: context
                )
            )
            let githubBody = try XCTUnwrap(
                URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "body" }?.value
            )
            XCTAssertEqual(githubBody, shareText)
        }
    }

    func testBodyOmitsBuildWhenBuildBlank() {
        let body = BugReportComposer.body(
            description: "x",
            context: makeContext(appBuild: "")
        )
        XCTAssertTrue(body.contains("- App version: 1.4.0"))
        XCTAssertFalse(body.contains("1.4.0 ("))
    }

    func testBodyShowsUnknownModuleWhenMissing() {
        let body = BugReportComposer.body(
            description: "x",
            context: makeContext(currentModule: nil)
        )
        XCTAssertTrue(body.contains("- Page/module: Unknown"))
    }

    func testBodyOmitsRecentErrorsSectionWhenNone() {
        let body = BugReportComposer.body(description: "x", context: makeContext())
        XCTAssertFalse(body.contains("### Recent errors"))
    }

    func testBodyRendersRecentErrorsMostRecentFirst() {
        let errors = [
            BugReportComposer.ErrorEntry(message: "Failed to load jobs"),
            BugReportComposer.ErrorEntry(message: "Network timeout"),
        ]
        let body = BugReportComposer.body(
            description: "x",
            context: makeContext(recentErrors: errors)
        )
        XCTAssertTrue(body.contains("### Recent errors"))
        let loadIndex = body.range(of: "Failed to load jobs")
        let netIndex = body.range(of: "Network timeout")
        XCTAssertNotNil(loadIndex)
        XCTAssertNotNil(netIndex)
        XCTAssertLessThan(loadIndex!.lowerBound, netIndex!.lowerBound)
    }

    func testBodyCapsRecentErrorsAtMax() {
        let errors = (1...10).map {
            BugReportComposer.ErrorEntry(message: "Error \($0)")
        }
        let body = BugReportComposer.body(
            description: "x",
            context: makeContext(recentErrors: errors)
        )
        XCTAssertTrue(body.contains("Error 1"))
        XCTAssertTrue(body.contains("Error \(BugReportComposer.maxRenderedErrors)"))
        XCTAssertFalse(body.contains("Error \(BugReportComposer.maxRenderedErrors + 1)"))
    }

    func testBodyDropsBlankErrorMessages() {
        let errors = [
            BugReportComposer.ErrorEntry(message: "   "),
            BugReportComposer.ErrorEntry(message: "Real error"),
        ]
        let body = BugReportComposer.body(
            description: "x",
            context: makeContext(recentErrors: errors)
        )
        XCTAssertTrue(body.contains("Real error"))
        // Only the real error should appear under the section, no empty bullet.
        XCTAssertFalse(body.contains("- \n"))
    }

    // MARK: - GitHub URL

    func testGithubURLTargetsCorrectRepoAndPath() throws {
        let url = try XCTUnwrap(
            BugReportComposer.githubIssueURL(
                userTitle: "Crash on launch",
                description: "It crashed.",
                context: makeContext()
            )
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(
            components.path,
            "/xXKillerNoobYT/Weird-Part-Run-2/issues/new"
        )
    }

    func testGithubURLEncodesTitleAndBodyRecoverably() throws {
        let url = try XCTUnwrap(
            BugReportComposer.githubIssueURL(
                userTitle: "Crash on launch",
                description: "It crashed while saving a job.",
                context: makeContext()
            )
        )
        // Decode the query back and confirm title/body survived encoding intact.
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try XCTUnwrap(components.queryItems)
        let title = items.first { $0.name == "title" }?.value
        let body = items.first { $0.name == "body" }?.value
        XCTAssertEqual(title, "Crash on launch")
        XCTAssertTrue(body?.contains("It crashed while saving a job.") == true)
        XCTAssertTrue(body?.contains("iPhone 15 Pro") == true)
    }

    func testGithubURLPreservesPlusSignsInBody() throws {
        let url = try XCTUnwrap(
            BugReportComposer.githubIssueURL(
                userTitle: "Math bug",
                description: "2 + 2 shows 5 in C++ mode.",
                context: makeContext()
            )
        )
        // The raw query must escape "+" so it is not decoded back into a space.
        let rawQuery = try XCTUnwrap(url.query)
        XCTAssertFalse(rawQuery.contains("2 + 2".replacingOccurrences(of: " ", with: "+")))
        // Round-trip via URLComponents decoding restores the literal plus signs.
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let body = components.queryItems?.first { $0.name == "body" }?.value
        XCTAssertTrue(body?.contains("2 + 2 shows 5 in C++ mode.") == true)
    }

    func testGithubURLContainsNoSecretsOrTokens() throws {
        let url = try XCTUnwrap(
            BugReportComposer.githubIssueURL(
                userTitle: "x",
                description: "y",
                context: makeContext()
            )
        )
        let full = url.absoluteString.lowercased()
        XCTAssertFalse(full.contains("token"))
        XCTAssertFalse(full.contains("apikey"))
        XCTAssertFalse(full.contains("secret"))
        XCTAssertFalse(full.contains("authorization"))
    }
}
