import XCTest
import WiredPartCore
@testable import Weird_Parts

/// Regression tests for GH#486: duplicate verification submit copy.
///
/// Asserts that `IOSVerificationSubmitSheet` maps the duplicate-submit
/// service error to the exact required operator-facing copy.
@MainActor
final class VerificationSubmitSheetRegressionTests: XCTestCase {

    func testDuplicateSubmitErrorMapsToExactRequiredCopy() {
        let message = VerificationSubmitSheetDuplicateSubmitCopy.message(
            for: WarehouseService.WarehouseError.sessionAlreadyCompleted
        )

        XCTAssertEqual(
            message,
            "You've already submitted a count for this part. Each counter can submit once."
        )
    }

    func testNonDuplicateSubmitErrorDoesNotUseDuplicateCopy() {
        struct SampleError: Error {}

        XCTAssertNil(
            VerificationSubmitSheetDuplicateSubmitCopy.message(for: SampleError()),
            "Only the duplicate-submit service error should use the GH#486 duplicate-copy path."
        )
    }

    func testMyVerificationsPageOpensSubmitSheet() throws {
        let source = try Self.readMyVerificationsPageSource()

        XCTAssertTrue(
            source.contains("IOSVerificationSubmitSheet("),
            "IOSMyVerificationsPage must open IOSVerificationSubmitSheet so both submit entry points share the same copy."
        )
    }

    func testAuditPageExposesMyVerificationsNavigationLink() throws {
        let source = try Self.readAuditPageSource()

        XCTAssertTrue(
            source.contains("IOSMyVerificationsPage()"),
            "IOSAuditPage must expose a navigation link to IOSMyVerificationsPage so the My Verification Assignments entry point is reachable from the audit hub."
        )
        XCTAssertTrue(
            source.contains("My Verification Assignments"),
            "IOSAuditPage must label the entry point 'My Verification Assignments'."
        )
    }

    // MARK: - Helpers

    private static func readVerificationSubmitSheetSource(
        file: StaticString = #filePath
    ) throws -> String {
        try readWarehouseSource(named: "IOSVerificationSubmitSheet.swift", file: file)
    }

    private static func readMyVerificationsPageSource(
        file: StaticString = #filePath
    ) throws -> String {
        try readWarehouseSource(named: "IOSMyVerificationsPage.swift", file: file)
    }

    private static func readAuditPageSource(
        file: StaticString = #filePath
    ) throws -> String {
        try readWarehouseSource(named: "IOSAuditPage.swift", file: file)
    }

    private static func readWarehouseSource(named filename: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Warehouse")
            .appendingPathComponent(filename)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
