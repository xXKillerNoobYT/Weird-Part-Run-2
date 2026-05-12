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

    public init(route: OnboardAIRuntimeRoute, availability: AIAvailability? = nil) {
        self.route = route
        self.availability = availability
    }
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
        if isLowResource() {
            return OnboardAIRuntimeBootstrapResult(route: .lowResource)
        }

        let availability = await availabilityWithTimeout()
        guard let availability else {
            return OnboardAIRuntimeBootstrapResult(route: .timeout)
        }

        if availability == .available {
            return OnboardAIRuntimeBootstrapResult(route: .ready, availability: availability)
        }

        return OnboardAIRuntimeBootstrapResult(route: .modelUnavailable, availability: availability)
    }

    private func availabilityWithTimeout() async -> AIAvailability? {
        await withCheckedContinuation { continuation in
            let race = OnboardAIAvailabilityRace(continuation: continuation)

            DispatchQueue.global(qos: .userInitiated).async { [aiChecker] in
                race.resume(returning: aiChecker.checkAvailability())
            }

            let timeout = Int(min(timeoutNanoseconds, UInt64(Int.max)))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .nanoseconds(timeout)) {
                race.resume(returning: nil)
            }
        }
    }
}

private final class OnboardAIAvailabilityRace: @unchecked Sendable {
    private let continuation: CheckedContinuation<AIAvailability?, Never>
    private let lock = NSLock()
    private var hasResumed = false

    init(continuation: CheckedContinuation<AIAvailability?, Never>) {
        self.continuation = continuation
    }

    func resume(returning availability: AIAvailability?) {
        lock.lock()
        defer { lock.unlock() }

        guard !hasResumed else {
            return
        }

        hasResumed = true
        continuation.resume(returning: availability)
    }
}
