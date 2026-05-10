import Foundation

/// Rollout flag name for the onboarding local AI MVP path.
public enum OnboardAIFeatureFlag {
    public static let onboardingMVP = "feature_onboard_ai_mvp_enabled"
}

/// Deterministic runtime routing for onboarding local AI bootstrap.
public enum OnboardAIRuntimeRoute: String, Sendable {
    case ready
    case modelUnavailable
    case timeout
    case lowResource
}

/// Bootstrap output used by onboarding to choose a safe route.
public struct OnboardAIRuntimeBootstrapResult: Sendable {
    public let route: OnboardAIRuntimeRoute
    public let availability: AIAvailability?
    public let timeoutBudgetMs: Int

    public init(
        route: OnboardAIRuntimeRoute,
        availability: AIAvailability? = nil,
        timeoutBudgetMs: Int
    ) {
        self.route = route
        self.availability = availability
        self.timeoutBudgetMs = timeoutBudgetMs
    }

    public var availabilityLabel: String {
        guard let availability else { return "none" }
        return String(describing: availability)
    }

    public var didTimeout: Bool { route == .timeout }
    public var usedLowResourceFallback: Bool { route == .lowResource }
    public var usedModelUnavailableFallback: Bool { route == .modelUnavailable }
}

public protocol AIAvailabilityChecking: Sendable {
    func checkAvailability() -> AIAvailability
}

extension FoundationModelsService: AIAvailabilityChecking {}

/// Computes the local AI runtime route for first-run onboarding.
public actor OnboardAIRuntimeBootstrapper {
    private let aiChecker: any AIAvailabilityChecking
    private let timeoutNanoseconds: UInt64
    private let isLowResource: @Sendable () -> Bool

    public init(
        aiChecker: any AIAvailabilityChecking = FoundationModelsService(),
        timeoutNanoseconds: UInt64 = 800_000_000,
        isLowResource: @escaping @Sendable () -> Bool = {
            if ProcessInfo.processInfo.isLowPowerModeEnabled {
                return true
            }
            switch ProcessInfo.processInfo.thermalState {
            case .serious, .critical:
                return true
            default:
                return false
            }
        }
    ) {
        self.aiChecker = aiChecker
        self.timeoutNanoseconds = timeoutNanoseconds
        self.isLowResource = isLowResource
    }

    public func bootstrap() async -> OnboardAIRuntimeBootstrapResult {
        let timeoutBudgetMs = Int(timeoutNanoseconds / 1_000_000)
        if isLowResource() {
            return OnboardAIRuntimeBootstrapResult(
                route: .lowResource,
                timeoutBudgetMs: timeoutBudgetMs
            )
        }

        let availability = await availabilityWithTimeout()
        guard let availability else {
            return OnboardAIRuntimeBootstrapResult(
                route: .timeout,
                timeoutBudgetMs: timeoutBudgetMs
            )
        }

        if availability == .available {
            return OnboardAIRuntimeBootstrapResult(
                route: .ready,
                availability: availability,
                timeoutBudgetMs: timeoutBudgetMs
            )
        }

        return OnboardAIRuntimeBootstrapResult(
            route: .modelUnavailable,
            availability: availability,
            timeoutBudgetMs: timeoutBudgetMs
        )
    }

    private func availabilityWithTimeout() async -> AIAvailability? {
        // Run the checker on a real OS thread so a blocking implementation
        // cannot occupy a cooperative-thread-pool worker and delay the
        // timeout fallback. The current task blocks only for the fixed budget
        // instead of awaiting a continuation that must be rescheduled onto the
        // cooperative executor under test/runtime load.
        let waitBox = _AvailabilityWaitBox()
        let checker = aiChecker
        Thread.detachNewThread {
            waitBox.finish(with: checker.checkAvailability())
        }

        return waitBox.wait(timeoutNanoseconds: timeoutNanoseconds)
    }
}

// MARK: - Private timeout wait guard

/// Holds a single checker result behind a semaphore so the bootstrap timeout
/// does not depend on Swift task, actor, or dispatch queue scheduling.
private final class _AvailabilityWaitBox: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var result: AIAvailability?

    func finish(with value: AIAvailability) {
        lock.lock()
        result = value
        lock.unlock()

        semaphore.signal()
    }

    func wait(timeoutNanoseconds: UInt64) -> AIAvailability? {
        let timeout = DispatchTime.now() + .nanoseconds(Int(timeoutNanoseconds))
        guard semaphore.wait(timeout: timeout) == .success else {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }
        return result
    }
}
