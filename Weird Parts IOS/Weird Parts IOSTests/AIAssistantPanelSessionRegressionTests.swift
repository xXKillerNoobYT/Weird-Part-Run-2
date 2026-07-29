import XCTest

/// Regression coverage for issue #724: the AI assistant panel must never
/// substitute user id 0 for a missing session when invoking tool-backed chat.
/// With a nil user id, the core companion-poll and voting tools fail closed
/// with an explicit not-signed-in message instead of querying as user 0.
final class AIAssistantPanelSessionRegressionTests: XCTestCase {
    // Static source-policy coverage moved to
    // docs/testing/xctest-source-policy-manifest.json and is evaluated by
    // scripts/validate-xctest-source-policy.py in a checkout-hosted context.
}
