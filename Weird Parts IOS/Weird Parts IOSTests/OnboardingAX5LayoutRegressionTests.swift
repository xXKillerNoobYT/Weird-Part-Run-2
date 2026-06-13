import XCTest

final class OnboardingAX5LayoutRegressionTests: XCTestCase {
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
