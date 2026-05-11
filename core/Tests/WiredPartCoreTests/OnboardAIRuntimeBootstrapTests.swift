import Foundation
import Testing
@testable import WiredPartCore

@Suite("Onboard AI Runtime Bootstrap")
struct OnboardAIRuntimeBootstrapTests {
    private struct StubChecker: AIAvailabilityChecking {
        let value: AIAvailability
        let delayNs: UInt64

        func checkAvailability() -> AIAvailability {
            if delayNs > 0 {
                Thread.sleep(forTimeInterval: TimeInterval(delayNs) / 1_000_000_000)
            }
            return value
        }
    }

    @Test("ready route when model is available")
    func testReadyRoute() async {
        let bootstrapper = OnboardAIRuntimeBootstrapper(
            aiChecker: StubChecker(value: .available, delayNs: 0),
            timeoutNanoseconds: 500_000_000,
            isLowResource: { false }
        )

        let result = await bootstrapper.bootstrap()
        #expect(result.route == .ready)
        #expect(result.availability == .available)
        #expect(result.timeoutBudgetMs == 500)
        #expect(result.didTimeout == false)
        #expect(result.usedLowResourceFallback == false)
        #expect(result.availabilityLabel == "available")
    }

    @Test("model unavailable route when model is not available")
    func testModelUnavailableRoute() async {
        let bootstrapper = OnboardAIRuntimeBootstrapper(
            aiChecker: StubChecker(value: .modelNotReady, delayNs: 0),
            timeoutNanoseconds: 500_000_000,
            isLowResource: { false }
        )

        let result = await bootstrapper.bootstrap()
        #expect(result.route == .modelUnavailable)
        #expect(result.availability == .modelNotReady)
        #expect(result.usedModelUnavailableFallback == true)
        #expect(result.didTimeout == false)
        #expect(result.availabilityLabel == "modelNotReady")
    }

    @Test("timeout route when availability check exceeds timeout")
    func testTimeoutRoute() async {
        let bootstrapper = OnboardAIRuntimeBootstrapper(
            aiChecker: StubChecker(value: .available, delayNs: 250_000_000),
            timeoutNanoseconds: 10_000_000,
            isLowResource: { false }
        )

        let result = await bootstrapper.bootstrap()
        #expect(result.route == .timeout)
        #expect(result.availability == nil)
        #expect(result.didTimeout == true)
        #expect(result.availabilityLabel == "none")
    }

    @Test("low resource route short-circuits availability check")
    func testLowResourceRoute() async {
        let bootstrapper = OnboardAIRuntimeBootstrapper(
            aiChecker: StubChecker(value: .available, delayNs: 0),
            timeoutNanoseconds: 500_000_000,
            isLowResource: { true }
        )

        let result = await bootstrapper.bootstrap()
        #expect(result.route == .lowResource)
        #expect(result.availability == nil)
        #expect(result.usedLowResourceFallback == true)
        #expect(result.didTimeout == false)
        #expect(result.availabilityLabel == "none")
    }
}
