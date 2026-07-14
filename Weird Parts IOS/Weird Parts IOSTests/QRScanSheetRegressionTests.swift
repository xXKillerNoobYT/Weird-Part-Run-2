import XCTest
@testable import Weird_Parts

@MainActor
final class QRScanSheetRegressionTests: XCTestCase {
    func testScanResultCallbackRunsInsideMainActorDismissBlock() throws {
        let source = try Self.qrScanSheetSource()
        let normalized = normalizedSource(source)

        XCTAssertTrue(
            normalized.contains("awaitMainActor.run{"),
            "QRScanSheet should use MainActor.run for result-state and dismissal updates."
        )
        XCTAssertTrue(
            normalized.contains("ifshouldComplete{dismiss()onResult(result)}"),
            "QRScanSheet must invoke onResult(result) in the same MainActor block as dismiss()."
        )
        XCTAssertFalse(
            normalized.contains("awaitMainActor.run{dismiss()}onResult(result)"),
            "QRScanSheet must not invoke the parent state callback after leaving MainActor."
        )
    }

    func testDuplicateScanGuardPreventsOverlappingProcessing() throws {
        let source = try Self.qrScanSheetSource()
        let normalized = normalizedSource(source)

        XCTAssertTrue(
            normalized.contains("letshouldSkip=awaitMainActor.run{guarddeliveryGate.claim(payload)else{returntrue}"),
            "QRScanSheet should claim its processing slot on MainActor before async lookup work."
        )
        XCTAssertTrue(
            normalized.contains("ifshouldSkip{return}"),
            "Overlapping scans should return without starting another lookup."
        )
    }

    func testDeliveryGateInvokesCompletionOnceForDuplicatePayload() {
        var gate = QRScanDeliveryGate()
        var callbackCount = 0
        let payload = #"{"app":"wiredpart","version":2,"type":"po","id":42,"code":"PO-42"}"#

        for _ in 0..<2 {
            guard gate.claim(payload) else { continue }
            if gate.finish(payload, shouldComplete: true) {
                callbackCount += 1
            }
        }

        let isProcessing = gate.isProcessing
        let completedPayload = gate.completedPayload
        XCTAssertEqual(callbackCount, 1)
        XCTAssertFalse(isProcessing)
        XCTAssertEqual(completedPayload, payload)
    }

    func testDeliveryGateReleasesMismatchAndFailureForRetry() {
        var gate = QRScanDeliveryGate()

        XCTAssertTrue(gate.claim("JOB-1"))
        XCTAssertFalse(gate.finish("JOB-1", shouldComplete: false))
        XCTAssertTrue(gate.claim("JOB-1"), "A wrong-type or not-found result must remain retryable.")
        gate.fail("JOB-1")
        XCTAssertTrue(gate.claim("JOB-1"), "A failed lookup must release the processing slot.")
    }

    func testManualFallbackAndCameraBottomReuseOneStatusView() throws {
        let source = try Self.qrScanSheetSource()
        let bottom = try Self.braceBalancedBody(after: "private var bottomSection", in: source)
        let manual = try Self.braceBalancedBody(after: "private var manualOnlyView", in: source)

        XCTAssertTrue(
            source.contains("private var feedbackStatusView: some View"),
            "QRScanSheet should keep scan feedback in one reusable status view."
        )
        XCTAssertTrue(bottom.contains("feedbackStatusView"))
        XCTAssertTrue(manual.contains("feedbackStatusView"))
    }

    func testProcessingStateShowsAccessibleLookingUpAndDisablesLookup() throws {
        let source = try Self.qrScanSheetSource()
        let feedback = try Self.braceBalancedBody(after: "private var feedbackStatusView", in: source)
        let processingClaim = try Self.braceBalancedBody(after: "let shouldSkip = await MainActor.run", in: source)

        XCTAssertTrue(
            feedback.contains("ProgressView()") && feedback.contains("Text(\"Looking up…\")"),
            "Processing feedback must include both a spinner and visible Looking up text."
        )
        XCTAssertTrue(
            source.contains(".disabled(manualCode.isBlankRequiredText || isProcessing)"),
            "Look Up must remain disabled while processing."
        )
        XCTAssertTrue(
            feedback.contains(".accessibilityIdentifier(\"qrScanStatus\")")
                && feedback.contains(".accessibilityLabel(statusAccessibilityLabel)")
                && feedback.contains(".accessibilityAddTraits(.updatesFrequently)"),
            "The status view needs a stable accessibility identifier and update semantics for VoiceOver."
        )
        XCTAssertTrue(
            source.contains("UIAccessibility.post(notification: .announcement, argument: status)"),
            "Status changes should be announced to VoiceOver."
        )
        XCTAssertTrue(
            processingClaim.contains("resultTitle = nil")
                && processingClaim.contains("resultCode = nil")
                && processingClaim.contains("resultEntityType = nil"),
            "Starting a new lookup must clear stale prior results while Looking up is shown."
        )
        XCTAssertTrue(
            source.contains("await Task.yield()"),
            "QRScanSheet should yield once so SwiftUI can render and announce loading before synchronous lookup work."
        )
    }

    func testWrongTypeWarningIsOrangeAndPrecedesSuccessRendering() throws {
        let source = try Self.qrScanSheetSource()
        let feedback = try Self.braceBalancedBody(after: "private var feedbackStatusView", in: source)

        guard let mismatchRange = feedback.range(
            of: "typeMismatch, let got = resultEntityType, let expected = expectedType"
        ), let resultRange = feedback.range(of: "else if let title = resultTitle") else {
            XCTFail("Expected type mismatch to branch before generic result rendering.")
            return
        }

        XCTAssertLessThan(mismatchRange.lowerBound, resultRange.lowerBound)
        XCTAssertTrue(
            feedback.contains("Text(\"Expected \\(expected.rawValue), got \\(got.rawValue)\")")
                && feedback.contains(".foregroundStyle(.orange)"),
            "Wrong-type results must show an orange Expected/got warning."
        )
    }

    func testNotFoundMessageIncludesCodeAndDoesNotDismiss() throws {
        let source = try Self.qrScanSheetSource()
        let feedback = try Self.braceBalancedBody(after: "private var feedbackStatusView", in: source)

        XCTAssertTrue(
            feedback.contains("\"Not found: \\(resultCode ?? \"\")\""),
            "Not-found feedback must include the entered/scanned code."
        )
        XCTAssertTrue(
            source.contains("let shouldAutoComplete = result.isFound\n                && (expectedType == nil || result.entityType == expectedType)"),
            "Only found matching results may auto-complete."
        )
    }

    func testMatchingSuccessUsesSingleMainActorCompletionPath() throws {
        let source = try Self.qrScanSheetSource()
        let processPayload = try Self.methodBody(named: "processPayload", in: source)

        XCTAssertTrue(
            processPayload.contains("guard deliveryGate.claim(payload) else { return true }")
                && processPayload.contains("if shouldSkip { return }"),
            "QR payload processing must atomically claim the delivery gate."
        )
        XCTAssertTrue(
            processPayload.contains("let shouldAutoComplete = result.isFound\n                && (expectedType == nil || result.entityType == expectedType)"),
            "Only found results matching the expected type may auto-complete."
        )
        XCTAssertTrue(
            processPayload.contains("if shouldComplete {\n                    dismiss()\n                    onResult(result)\n                }"),
            "Matching success should dismiss and invoke the callback from one MainActor branch."
        )
        XCTAssertEqual(processPayload.components(separatedBy: "onResult(result)").count - 1, 1)
    }

    func testCancelDoesNotInvokeCallbackAndManualFieldsAreNamedQRCode() throws {
        let source = try Self.qrScanSheetSource()
        let toolbar = try Self.braceBalancedBody(after: ".toolbar", in: source)

        XCTAssertTrue(toolbar.contains("Button(\"Cancel\") { dismiss() }"))
        XCTAssertFalse(toolbar.contains("onResult"))
        XCTAssertEqual(
            source.components(separatedBy: ".accessibilityLabel(\"QR code\")").count - 1,
            2,
            "Both manual QR entry fields must expose the explicit accessible name QR code."
        )
    }

    private func normalizedSource(_ source: String) -> String {
        source.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }

    private static func qrScanSheetSource(file: StaticString = #filePath) throws -> String {
        let sourceURL = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Scanning")
            .appendingPathComponent("QRScanSheet.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func braceBalancedBody(after anchor: String, in source: String) throws -> String {
        try TestSourceSlicer.braceBalancedBody(after: anchor, in: source)
    }

    private static func methodBody(named methodName: String, in source: String) throws -> String {
        try braceBalancedBody(after: "func \(methodName)(", in: source)
    }
}
