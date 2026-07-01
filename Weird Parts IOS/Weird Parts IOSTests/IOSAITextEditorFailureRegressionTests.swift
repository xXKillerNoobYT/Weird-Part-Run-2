import XCTest

/// Regression coverage for GitHub #1078 / Paperclip WEI-4328.
///
/// The AI text editor must surface failed AI generation paths instead of
/// silently stopping its spinner and leaving the text unchanged.
final class IOSAITextEditorFailureRegressionTests: XCTestCase {
    func testAITextEditorSurfacesFailedEnhanceAndPreFill() throws {
        let source = try Self.readAITextEditorSource()

        XCTAssertTrue(
            source.contains("@State private var aiErrorMessage: String?"),
            "IOSAITextEditor should keep user-visible AI failure state."
        )
        XCTAssertTrue(
            source.contains(".alert(\"AI Request Failed\"") &&
                source.contains("showAIErrorAlert = true"),
            "User-triggered AI failures should open an explicit alert instead of silently no-oping."
        )
        XCTAssertTrue(
            source.contains("AI enhancement failed. Your original text was kept. Please try again."),
            "Enhance failures should explain that the original text was preserved and suggest retrying."
        )
        XCTAssertTrue(
            source.contains("AI pre-fill failed. Please try again or enter the text manually."),
            "Pre-fill failures should provide actionable fallback guidance."
        )
        XCTAssertFalse(
            source.contains("result.error?.trimmingCharacters"),
            "Provider/internal AI errors should not be shown directly in user-visible failure copy."
        )
    }

    func testAITextEditorSurfacesCompletionFailuresInlineAndAccessible() throws {
        let source = try Self.readAITextEditorSource()
        let completionSection = try Self.section(
            named: "private func onTextChange",
            in: source,
            endingBefore: "private func acceptSuggestion"
        )

        XCTAssertTrue(
            completionSection.contains("AI suggestion failed. Keep typing or try again in a moment."),
            "Autocomplete failures should set visible inline feedback instead of leaving suggestion empty with no explanation."
        )
        XCTAssertTrue(
            completionSection.contains("defer { isLoadingSuggestion = false }") &&
                completionSection.contains("let result = await aiService.generateCompletion") &&
                completionSection.contains("guard !Task.isCancelled else { return }"),
            "Autocomplete should reset loading with defer and ignore cancelled debounce completions before surfacing errors."
        )
        XCTAssertTrue(
            source.contains("accessibilityIdentifier(\"aiTextEditorErrorMessage\")") &&
                source.contains("accessibilityElement(children: .contain)") &&
                source.contains("accessibilityLabel(\"Dismiss AI error\")"),
            "The visible AI failure callout should expose the message and Dismiss control separately to VoiceOver users."
        )
    }

    func testAITextEditorUsesDeferToResetLoadingForAsyncActions() throws {
        let source = try Self.readAITextEditorSource()
        let enhanceSection = try Self.section(
            named: "private func enhance",
            in: source,
            endingBefore: "private func preFill"
        )
        let preFillSection = try Self.section(
            named: "private func preFill",
            in: source,
            endingBefore: "private func cancelSuggestionRequest"
        )

        XCTAssertTrue(
            enhanceSection.contains("defer { isEnhancing = false }") &&
                preFillSection.contains("defer { isEnhancing = false }"),
            "Enhance and pre-fill should reset loading with defer so failure branches cannot leave stale spinner state."
        )
        XCTAssertTrue(
            enhanceSection.contains("cancelSuggestionRequest()") &&
                preFillSection.contains("cancelSuggestionRequest()"),
            "User-triggered AI actions should cancel pending autocomplete work so stale suggestion failures cannot overwrite their feedback."
        )
        XCTAssertTrue(
            enhanceSection.contains("let result = await aiService.enhanceText") &&
                preFillSection.contains("let result = await aiService.generatePreFill") &&
                enhanceSection.contains("guard !Task.isCancelled else { return }") &&
                preFillSection.contains("guard !Task.isCancelled else { return }"),
            "Enhance and pre-fill should ignore cancelled AI results before mutating visible UI state."
        )
    }

    func testUserTriggeredAIRequestsCancelAutocompleteAndIgnoreCancellation() throws {
        let source = try Self.readAITextEditorSource()
        let enhanceSection = try Self.section(
            named: "private func enhance",
            in: source,
            endingBefore: "private func preFill"
        )
        let preFillSection = try Self.section(
            named: "private func preFill",
            in: source,
            endingBefore: "private func cancelSuggestionRequest"
        )
        let cancelSuggestionSection = try Self.section(
            named: "private func cancelSuggestionRequest",
            in: source,
            endingBefore: "private func failureMessage"
        )

        XCTAssertTrue(
            enhanceSection.contains("cancelSuggestionRequest()") &&
                preFillSection.contains("cancelSuggestionRequest()"),
            "User-triggered AI actions should cancel pending autocomplete so stale suggestion failures cannot overwrite the active alert."
        )
        XCTAssertTrue(
            enhanceSection.contains("guard !Task.isCancelled else { return }") &&
                preFillSection.contains("guard !Task.isCancelled else { return }"),
            "Enhance and pre-fill should ignore cancellation results before setting error state or showing alerts."
        )
        XCTAssertTrue(
            cancelSuggestionSection.contains("debounceTask?.cancel()") &&
                cancelSuggestionSection.contains("suggestion = \"\"") &&
                cancelSuggestionSection.contains("isLoadingSuggestion = false"),
            "Cancelling autocomplete should clear pending task, visible suggestion, and loading state together."
        )
    }

    func testAITextEditorDoesNotExposeRawAIServiceErrorsToUsers() throws {
        let source = try Self.readAITextEditorSource()
        let failureMessageSection = try Self.section(
            named: "private func failureMessage",
            in: source,
            endingBefore: "}\n}"
        )

        XCTAssertFalse(
            failureMessageSection.contains("result.error"),
            "Visible AI errors should use curated user-facing copy, not raw service/model error text."
        )
    }

    private static func section(named startMarker: String, in source: String, endingBefore endMarker: String) throws -> String {
        guard let start = source.range(of: startMarker) else {
            XCTFail("Missing section starting with \(startMarker)")
            return ""
        }
        let afterStart = source[start.lowerBound...]
        guard let end = afterStart.range(of: endMarker) else {
            XCTFail("Missing section ending before \(endMarker)")
            return ""
        }
        return String(afterStart[..<end.lowerBound])
    }

    private static func readAITextEditorSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("AI")
            .appendingPathComponent("IOSAITextEditor.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
