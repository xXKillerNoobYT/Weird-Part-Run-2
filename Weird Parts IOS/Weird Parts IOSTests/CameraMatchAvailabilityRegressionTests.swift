import XCTest

/// Regression coverage for GH #1080: the Part Match camera flow must never
/// present a `.camera` UIImagePickerController without first checking
/// `UIImagePickerController.isSourceTypeAvailable(.camera)`. On Simulator,
/// camera-less iPads, and restricted devices the unguarded flow crashed or
/// presented a dead system picker.
final class CameraMatchAvailabilityRegressionTests: XCTestCase {
    // Static source-policy coverage moved to
    // docs/testing/xctest-source-policy-manifest.json and is evaluated by
    // scripts/validate-xctest-source-policy.py in a checkout-hosted context.
}
