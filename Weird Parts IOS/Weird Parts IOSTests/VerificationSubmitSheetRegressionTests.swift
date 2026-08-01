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

}
