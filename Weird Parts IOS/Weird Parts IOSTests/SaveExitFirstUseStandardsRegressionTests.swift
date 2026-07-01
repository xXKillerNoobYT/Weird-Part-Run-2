import XCTest

/// Regression coverage for GitHub #82's cross-cutting form and first-time-use primitives.
///
/// The parent issue is intentionally program-wide, so these tests lock down the shared
/// standards that individual pages and module lanes depend on: save/dismiss safety,
/// inline first-time guidance, and contextual help discoverability.
final class SaveExitFirstUseStandardsRegressionTests: XCTestCase {
    func testEmptyStateViewProvidesDedicatedHelpAffordanceSlot() throws {
        let source = try Self.readSharedSource("EmptyStateView.swift")

        XCTAssertTrue(
            source.contains("var helpLabel: String?") && source.contains("var helpAction: (() -> Void)?"),
            "EmptyStateView must expose a dedicated helpLabel/helpAction slot so zero-record lists can link to page-specific guidance."
        )
        XCTAssertTrue(
            source.contains("Label(label, systemImage: \"questionmark.circle\")"),
            "The help affordance should use the questionmark.circle symbol required by the page-help pattern."
        )
        XCTAssertTrue(
            source.contains(".buttonStyle(.borderless)"),
            "Empty-state help links should render as a secondary/documentation affordance, not compete with the primary create action."
        )
        XCTAssertTrue(
            source.contains(".accessibilityIdentifier(\"emptyStateHelpButton\")"),
            "The shared help link needs a stable accessibility identifier for iPhone/iPad QA."
        )
        XCTAssertTrue(
            source.contains(".frame(minHeight: 44)"),
            "Primary, secondary, and help empty-state actions must remain touch-friendly."
        )
        XCTAssertTrue(
            source.contains("(actionLabel != nil && action != nil)") &&
                source.contains("(secondaryActionLabel != nil && secondaryAction != nil)") &&
                source.contains("(helpLabel != nil && helpAction != nil)"),
            "The empty-state action container should render only when a label/action pair exists, avoiding blank padded action areas."
        )
    }

    func testEmptyStateHelpTaxonomyDocumentsOptionalInlineHelp() throws {
        let source = try Self.readPlanSource("empty-state-help-link-taxonomy.md")

        XCTAssertTrue(
            source.contains("optional GH #82 primitive"),
            "The empty-state taxonomy should describe inline help as optional, not a blanket scanner requirement."
        )
        XCTAssertTrue(
            source.contains("toolbar Help button remains the canonical Category A baseline"),
            "The taxonomy should keep page toolbar help as the default primary-list pattern."
        )
    }

    func testFormSheetPreservesSaveAndDirtyDismissStandards() throws {
        let formSheet = try Self.readSharedSource("FormSheet.swift")
        let dismissSafety = try Self.readSharedSource("DismissSafety.swift")

        XCTAssertTrue(
            formSheet.contains("var saveLabel: String = \"Save\""),
            "Shared form sheets must keep a configurable save label so create flows can opt into Save & Exit naming."
        )
        XCTAssertTrue(
            formSheet.contains(".disabled(!isValid || isSaving)"),
            "Save actions must stay disabled while invalid or saving."
        )
        XCTAssertTrue(
            formSheet.contains(".disabled(isSaving)"),
            "Cancel actions must be disabled while saving so in-flight writes cannot be interrupted."
        )
        XCTAssertTrue(
            formSheet.contains("DismissSafety.cancelOrConfirm") && formSheet.contains(".dismissSafety("),
            "Shared forms must route explicit Cancel and drag-dismiss through the same dirty-state protection."
        )
        XCTAssertTrue(
            dismissSafety.contains(".interactiveDismissDisabled(isDirty || isSaving)"),
            "Dirty or saving sheets must block drag-dismiss instead of silently dropping changes."
        )
        XCTAssertTrue(
            dismissSafety.contains("Discard Changes") && dismissSafety.contains("Keep Editing"),
            "Dirty cancel flows must show the required discard/keep-editing choice."
        )
    }

    func testHelpContentRegistryKeepsPageSpecificHelpQueryableByAI() throws {
        let source = try Self.readSharedSource("HelpContentRegistry.swift")

        XCTAssertTrue(
            source.contains("static let entries") && source.contains("static func formattedHelp(for pageId: String)"),
            "Page help content must remain centrally queryable for toolbar help and AI assistant context."
        )
        XCTAssertTrue(
            source.contains("static let notificationToPageId"),
            "Page-active notifications must map back to registry page IDs for contextual AI help."
        )
        XCTAssertTrue(
            source.contains("dashboard-home") && source.contains("jobs-list") && source.contains("orders-pos") && source.contains("warehouse-dashboard"),
            "The registry should continue covering representative core modules, not just a single page."
        )
    }

    private static func readSharedSource(_ filename: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Shared")
            .appendingPathComponent(filename)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func readPlanSource(_ filename: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let repoRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
            .deletingLastPathComponent() // repo root
        let sourceURL = repoRoot
            .appendingPathComponent("docs")
            .appendingPathComponent("plans")
            .appendingPathComponent(filename)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
