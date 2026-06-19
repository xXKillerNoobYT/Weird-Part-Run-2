import XCTest

/// Regression coverage for GitHub #853 / WEI-3828.
///
/// The current onboarding walkthrough must not write the legacy
/// `hasSeenWelcome` trigger because `WiredPartIOSApp.init()` still migrates
/// that key into `hasCompletedCompanySetup` for true legacy installs.
final class OnboardingLegacyWelcomeMigrationTests: XCTestCase {
    func testWalkthroughCompletionDoesNotWriteLegacyWelcomeMigrationTrigger() throws {
        let walkthroughSource = try Self.readAppSource(
            components: "Auth", "OnboardingWalkthroughView.swift"
        )
        let finishBody = try Self.functionBody(named: "finishOnboarding", in: walkthroughSource)

        XCTAssertTrue(
            finishBody.contains("hasCompletedOnboarding = true"),
            "The current walkthrough should still complete the modern onboarding flag."
        )
        XCTAssertTrue(
            finishBody.contains("UserDefaults.standard.set(true, forKey: \"hasSeenModuleTour\")"),
            "The current walkthrough should still suppress the legacy module tour overlay."
        )
        XCTAssertFalse(
            finishBody.contains("UserDefaults.standard.set(true, forKey: \"hasSeenWelcome\")"),
            "The current walkthrough must not write hasSeenWelcome; startup migrates that legacy key into company setup completion."
        )
    }

    func testStartupStillConsumesLegacyWelcomeForTrueLegacyInstalls() throws {
        let appSource = try Self.readAppSource(
            components: "App", "WiredPartIOSApp.swift"
        )
        let initBody = try Self.functionBody(named: "init", in: appSource)

        XCTAssertTrue(
            initBody.contains("UserDefaults.standard.bool(forKey: \"hasSeenWelcome\")"),
            "Startup should still detect the legacy welcome key for users who completed the old flow."
        )
        XCTAssertTrue(
            initBody.contains("UserDefaults.standard.set(true, forKey: \"hasCompletedCompanySetup\")"),
            "True legacy installs should continue to skip the new company setup wizard."
        )
        XCTAssertTrue(
            initBody.contains("UserDefaults.standard.removeObject(forKey: \"hasSeenWelcome\")"),
            "Startup should consume the legacy trigger so it cannot re-fire on a later fresh database."
        )
    }

    private static func readAppSource(components: String..., file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = components.reduce(projectRoot.appendingPathComponent("Weird Parts IOS")) { partial, component in
            partial.appendingPathComponent(component)
        }
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func functionBody(named name: String, in source: String) throws -> String {
        let signatures = [
            "private func \(name)() {",
            "func \(name)() {",
            "\(name)() {",
        ]
        guard let range = signatures.compactMap({ source.range(of: $0) }).first else {
            XCTFail("Could not find function \(name)")
            return ""
        }

        var depth = 0
        var endIndex = range.lowerBound
        var hasEnteredBody = false
        var index = range.lowerBound
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
                hasEnteredBody = true
            } else if character == "}" {
                depth -= 1
                if hasEnteredBody && depth == 0 {
                    endIndex = source.index(after: index)
                    break
                }
            }
            index = source.index(after: index)
        }

        return String(source[range.lowerBound..<endIndex])
    }
}
