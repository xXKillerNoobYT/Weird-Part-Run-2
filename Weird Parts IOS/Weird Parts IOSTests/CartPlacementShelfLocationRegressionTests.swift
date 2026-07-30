import XCTest

/// Regression coverage for issue #1253: warehouse cart placement destroyed
/// free-form part notes by writing a synthetic "Location: ..." string into
/// `parts.notes` while leaving real location metadata untouched.
///
/// Cart placement must record the destination in the dedicated
/// `shelf_location` column and must never write to the part notes field.
final class CartPlacementShelfLocationRegressionTests: XCTestCase {
    // Static source-policy coverage moved to
    // docs/testing/xctest-source-policy-manifest.json and is evaluated by
    // scripts/validate-xctest-source-policy.py in a checkout-hosted context.
}
