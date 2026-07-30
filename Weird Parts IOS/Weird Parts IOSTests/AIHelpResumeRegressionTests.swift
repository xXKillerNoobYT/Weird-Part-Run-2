import XCTest
@testable import Weird_Parts

/// Static source-policy coverage for AIHelpResumeRegressionTests moved to
/// docs/testing/xctest-source-policy-manifest.json and is evaluated by
/// scripts/validate-xctest-source-policy.py in a checkout-hosted context.
final class AIHelpResumeRegressionTests: XCTestCase {
    @MainActor
        func testHelpTitleLookupUsesDeclarationOrderForDuplicateNormalizedTitles() throws {
            let candidates = [
                HelpContentRegistry.HelpEntry(
                    pageId: "expected-context",
                    title: "Shared Help",
                    sections: [("Expected", "First declaration wins.")]
                ),
                HelpContentRegistry.HelpEntry(
                    pageId: "wrong-context",
                    title: "  shared help  ",
                    sections: [("Wrong", "Dictionary value order must not pick this duplicate.")]
                ),
            ]

            XCTAssertEqual(
                HelpContentRegistry.pageId(matchingTitle: "\nSHARED HELP\t", in: candidates),
                "expected-context"
            )
            XCTAssertNotEqual(
                HelpContentRegistry.pageId(matchingTitle: "shared help", in: candidates),
                "wrong-context",
                "Duplicate normalized titles must not hand the assistant the wrong page context."
            )
        }

    func testMarkdownRendererPreservesFencedCodeAndParagraphSpacing() {
            let markdown = """
            Before code.

            ```swift
            let first = 1

            let second = 2
            ```

            After code.
            """

            let rendered = AIAssistantMarkdownRenderer.plainText(fromMarkdown: markdown)

            XCTAssertEqual(
                rendered,
                "Before code.\n\nlet first = 1\n\nlet second = 2\n\nAfter code."
            )
            XCTAssertFalse(rendered.contains("```"))
        }

    func testMarkdownRendererPreservesBlankLineListAndIndentedCodeContent() {
            let markdown = """
            - First item

                  let first = 1

                  let second = 2

            - Second item
            """

            let rendered = AIAssistantMarkdownRenderer.plainText(fromMarkdown: markdown)

            XCTAssertEqual(
                rendered,
                "First item\n\nlet first = 1\n\nlet second = 2\n\nSecond item"
            )
            XCTAssertFalse(rendered.contains("- "))
        }
}
