import XCTest

final class OnboardingAX5LayoutRegressionTests: XCTestCase {
    func testInitialGetStartedScreenWrapsAndScrollsAtAccessibilitySizes() throws {
        let source = try Self.readSource("Auth/OnboardingWelcomeView.swift")

        XCTAssertTrue(
            source.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"),
            "Initial Get Started screen should read Dynamic Type so it can adapt before labels truncate."
        )
        XCTAssertTrue(
            source.contains("ScrollView {"),
            "Initial Get Started content should scroll at AX5 instead of clipping the privacy footer."
        )
        XCTAssertTrue(
            source.contains("HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center"),
            "Onboarding action rows should top-align when titles and subtitles wrap at accessibility sizes."
        )
        XCTAssertTrue(
            source.contains(".lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)"),
            "Onboarding subtitles/footer should remove restrictive line clamps at accessibility sizes."
        )
        XCTAssertTrue(
            source.contains(".fixedSize(horizontal: false, vertical: true)"),
            "Wrapped onboarding copy should keep its full vertical height instead of compressing inside rows."
        )
    }

    func testWelcomeOverlayUsesScrollableWrappedAccessibilityRows() throws {
        let source = try Self.readSource("Auth/NewUserWelcomeView.swift")

        XCTAssertTrue(
            source.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"),
            "Welcome overlay should read Dynamic Type so AX5 layout can avoid compressed rows."
        )
        XCTAssertTrue(
            source.contains("ScrollView {"),
            "Welcome overlay should scroll at AX5 instead of forcing all tips into the visible height."
        )
        XCTAssertTrue(
            source.contains(".lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)"),
            "Welcome tip titles/details should remove clamps at accessibility sizes."
        )
    }

    func testModuleTourAllowsAccessibilityPageContentToGrowAwayFromPagination() throws {
        let source = try Self.readSource("Auth/ModuleTourView.swift")

        XCTAssertTrue(
            source.contains(".frame(height: dynamicTypeSize.isAccessibilitySize ? 430 : 220)"),
            "Quick Tour page height should grow at AX5 so body copy does not collide with pagination."
        )
        XCTAssertTrue(
            source.contains("if !dynamicTypeSize.isAccessibilitySize"),
            "Quick Tour should not spend scarce AX5 vertical space on centering spacers."
        )
        XCTAssertTrue(
            source.contains(".padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 56 : 24)"),
            "Quick Tour page content should reserve AX5 space above the page dots."
        )
        XCTAssertTrue(
            source.contains(".tabViewStyle(.page(indexDisplayMode: dynamicTypeSize.isAccessibilitySize ? .never : .always))"),
            "Quick Tour should hide SwiftUI page dots at AX5 so pagination cannot overlap wrapped body copy."
        )
        XCTAssertTrue(
            source.contains(".lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)"),
            "Quick Tour descriptions should wrap at accessibility sizes instead of truncating."
        )
    }

    func testActiveOnboardingBannerRowsWrapAtAccessibilitySizes() throws {
        let source = try Self.readSource("Shared/OnboardingBanner.swift")

        XCTAssertTrue(
            source.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"),
            "Onboarding banner should read Dynamic Type so task rows can adapt at AX5."
        )
        XCTAssertTrue(
            source.contains("HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center"),
            "Onboarding banner rows should top-align when task text wraps at accessibility sizes."
        )
        XCTAssertTrue(
            source.contains(".lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)"),
            "Onboarding banner task descriptions should wrap at accessibility sizes."
        )
    }

    func testPostLoginWalkthroughAdaptsToAccessibilityDynamicType() throws {
        let source = try Self.readSource("Auth/OnboardingWalkthroughView.swift")

        XCTAssertTrue(
            source.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"),
            "The post-login walkthrough should read Dynamic Type so it can adapt at AX sizes (issue #1311)."
        )

        let welcomeScreen = try Self.extractSection(
            from: source,
            startingAt: "private var welcomeScreen: some View {",
            upTo: "// MARK: - Step View"
        )

        XCTAssertTrue(
            welcomeScreen.contains("ScrollView {"),
            "The walkthrough welcome screen should scroll at AX5 instead of clipping copy and buttons (issue #1311)."
        )
        XCTAssertTrue(
            welcomeScreen.contains(".frame(minHeight: proxy.size.height)"),
            "The welcome screen should keep its centered layout at regular sizes while remaining scrollable."
        )
        XCTAssertTrue(
            welcomeScreen.contains("if !dynamicTypeSize.isAccessibilitySize {"),
            "The welcome screen should not spend scarce AX5 vertical space on centering spacers."
        )

        XCTAssertTrue(
            source.contains("HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 12)"),
            "Key-feature rows should top-align when text wraps at accessibility sizes."
        )
        XCTAssertTrue(
            source.contains(".fixedSize(horizontal: false, vertical: true)"),
            "Wrapped walkthrough copy should keep its full vertical height instead of compressing."
        )
        XCTAssertTrue(
            source.contains("navigationFooterButtons(module: module, fullWidth: true)"),
            "Back/Skip/Next should stack vertically at accessibility sizes so every control stays reachable."
        )
    }

    func testNotStartedFixtureSuppressesModuleTourForChecklistEvidence() throws {
        let source = try Self.readSource("App/AppCore.swift")

        XCTAssertTrue(
            source.contains("if args.contains(\"-UITestingWEI936NotStarted\")"),
            "The not-started fixture should branch explicitly so checklist visual evidence has deterministic launch state."
        )
        XCTAssertTrue(
            source.contains("UserDefaults.standard.set(true, forKey: \"hasSeenModuleTour\")"),
            "The not-started fixture should suppress the Quick Tour overlay before capturing Getting Started checklist rows."
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

    /// Slices `source` to the substring between `start` (inclusive) and the
    /// next occurrence of `end` after it, so assertions about a specific
    /// view/property can't be satisfied by unrelated code elsewhere in the
    /// file that happens to contain the same snippet.
    private static func extractSection(
        from source: String,
        startingAt start: String,
        upTo end: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        guard let startRange = source.range(of: start) else {
            XCTFail("Could not locate section start marker '\(start)'", file: file, line: line)
            return ""
        }
        let remainder = source[startRange.upperBound...]
        guard let endRange = remainder.range(of: end) else {
            XCTFail("Could not locate section end marker '\(end)' after '\(start)'", file: file, line: line)
            return ""
        }
        return String(remainder[..<endRange.lowerBound])
    }
}
