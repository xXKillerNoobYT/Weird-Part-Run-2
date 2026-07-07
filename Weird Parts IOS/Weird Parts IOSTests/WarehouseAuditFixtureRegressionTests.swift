import XCTest

/// Guards the audit page's UITest fixture surface.
///
/// History: the original test asserted a `fixtureFallbackItem` mechanism
/// (pending-assignment-derived fallback, added in #817). PR #812 then moved
/// multi-user verification submits into the shared `IOSVerificationSubmitSheet`
/// (guarded by `VerificationSubmitSheetRegressionTests`) and removed both the
/// fallback plumbing and the UITest scheme hooks that consumed it — no UI test
/// references `UITEST-MUV-001` anymore. What remains, and what this test now
/// guards, is the launch-flag-gated fixture lookup used to surface the QA
/// Verify control deterministically when the fixture flag is passed.
final class WarehouseAuditFixtureRegressionTests: XCTestCase {
    func testFixtureVerificationLookupStaysFlagGatedAndDeterministic() throws {
        let source = try Self.readAuditPageSource()

        XCTAssertTrue(
            source.contains("private static let multiUserFixturePartCode = \"UITEST-MUV-001\""),
            "IOSAuditPage should keep the deterministic fixture part code so flag-gated QA runs can find the seeded part."
        )
        XCTAssertTrue(
            source.contains("ProcessInfo.processInfo.arguments.contains(Self.multiUserFixtureFlag)"),
            "The fixture path must stay behind its launch flag — it must never activate for real users."
        )
        XCTAssertTrue(
            source.contains("private var fixtureVerificationItem: CountingItem?"),
            "IOSAuditPage should resolve the fixture item so the QA Verify control can be shown under the fixture flag."
        )
        XCTAssertTrue(
            source.contains("$0.partCode == Self.multiUserFixturePartCode"),
            "Fixture lookup should match by the deterministic part code, not display-name only."
        )
    }

    private static func readAuditPageSource(
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Warehouse")
            .appendingPathComponent("IOSAuditPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
