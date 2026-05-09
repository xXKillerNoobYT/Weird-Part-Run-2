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
        // timeout sentinel. The `_AvailabilityResumeOnce` actor serialises
        // the race and guarantees the continuation is resumed exactly once.
        return await withCheckedContinuation { continuation in
            let once = _AvailabilityResumeOnce(continuation)

            // Timeout sentinel — cooperative, does not hold a thread.
            Task { [timeoutNanoseconds] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                await once.resume(with: nil)
            }

            // Checker on a real OS thread. Blocking calls here cannot starve
            // the cooperative thread pool and delay the timeout above.
            let checker = aiChecker
            Thread.detachNewThread {
                let value = checker.checkAvailability()
                Task { await once.resume(with: value) }
            }
        }
    }
}

// MARK: - Private one-shot continuation guard

/// Serialises the race between the timeout sentinel and the availability
/// checker so that `CheckedContinuation.resume` is called exactly once.
private actor _AvailabilityResumeOnce {
    private var pending: CheckedContinuation<AIAvailability?, Never>?

    init(_ continuation: CheckedContinuation<AIAvailability?, Never>) {
        self.pending = continuation
    }

    func resume(with value: AIAvailability?) {
        guard let c = pending else { return }
        pending = nil
        c.resume(returning: value)
    }
}
