import Foundation
import LocalAuthentication
import os.log

// MARK: - BiometricEvaluator Protocol

/// Abstracts `LAContext` so that biometric evaluation can be replaced with a
/// controllable stub in unit tests without requiring a real device or simulator.
protocol BiometricEvaluator {
    /// Returns whether the given policy can currently be evaluated, plus any error.
    /// Side-effect: populates `biometryType`.
    func canEvaluate(policy: LAPolicy) -> (Bool, Error?)
    /// The biometry type detected after `canEvaluate` has been called.
    var biometryType: LABiometryType { get }
    /// Evaluates the given policy and returns `true` on OS-level acceptance.
    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String) async throws -> Bool
}

// MARK: - Live Evaluator (production)

/// Production implementation that delegates to a real `LAContext`.
final class LiveBiometricEvaluator: BiometricEvaluator {
    private let context = LAContext()

    func canEvaluate(policy: LAPolicy) -> (Bool, Error?) {
        var err: NSError?
        let ok = context.canEvaluatePolicy(policy, error: &err)
        return (ok, err)
    }

    var biometryType: LABiometryType { context.biometryType }

    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { cont in
            context.evaluatePolicy(policy, localizedReason: localizedReason) { result, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: result) }
            }
        }
    }
}

// MARK: - BiometricAuthService

/// Manages Face ID / Touch ID opt-in state and biometric evaluation for the login screen.
///
/// Responsibilities:
///   - Persists per-user biometric opt-in preference in `UserDefaults` (non-sensitive boolean).
///   - Evaluates an injectable `BiometricEvaluator` (defaults to `LiveBiometricEvaluator`
///     backed by `LAContext`) and returns a typed `BiometricResult`.
///   - Emits structured instrumentation events via `os_log` for each stage
///     (prompt shown, opt-in result, auth success/fallback).
///
/// **Testability:** inject a `MockBiometricEvaluator` to control availability and outcome
/// without any simulator interaction.
///
/// Call sites:
///   - `LoginView` — after first successful PIN login, prompts the user to opt in.
///   - `LoginView.onAppear` — if a user has opted in, triggers biometric automatically.
final class BiometricAuthService {

    // MARK: - Instrumentation Logger

    private static let logger = Logger(
        subsystem: "com.wiredpart.ios",
        category: "BiometricAuth"
    )

    // MARK: - Evaluator

    /// Replaced in tests with a `MockBiometricEvaluator`.
    let evaluator: BiometricEvaluator

    init(evaluator: BiometricEvaluator = LiveBiometricEvaluator()) {
        self.evaluator = evaluator
    }

    // MARK: - UserDefaults Keys

    private static func optInKey(userId: Int64) -> String {
        "biometric_opt_in_user_\(userId)"
    }
    private static let lastOptedInUserKey = "biometric_last_opted_in_user_id"

    // MARK: - Opt-In Persistence

    /// Whether the given user has opted in to biometric login on this device.
    func isOptedIn(userId: Int64) -> Bool {
        UserDefaults.standard.bool(forKey: Self.optInKey(userId: userId))
    }

    /// Persist the user's opt-in choice. Also records the userId as the most recently
    /// opted-in user so `preferredBiometricUserId` can surface them at launch.
    func setOptIn(userId: Int64, enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.optInKey(userId: userId))
        if enabled {
            UserDefaults.standard.set(userId, forKey: Self.lastOptedInUserKey)
        } else {
            // Clear the last-opted-in record only if this user was the one stored.
            let current = UserDefaults.standard.object(forKey: Self.lastOptedInUserKey) as? Int64
            if current == userId {
                UserDefaults.standard.removeObject(forKey: Self.lastOptedInUserKey)
            }
        }
        Self.logger.info(
            "biometricOptInResult: userId=\(userId, privacy: .private) enabled=\(enabled)"
        )
    }

    /// The userId of the user who last opted in on this device, if any.
    /// Used by `LoginView` to pre-select the user and trigger automatic biometric
    /// auth on subsequent launches.
    var preferredBiometricUserId: Int64? {
        guard let raw = UserDefaults.standard.object(forKey: Self.lastOptedInUserKey) else {
            return nil
        }
        // UserDefaults stores integers at the platform's native width; cast both paths safely.
        if let value = raw as? Int64 { return value }
        if let value = raw as? Int { return Int64(value) }
        return nil
    }

    // MARK: - Biometric Availability

    /// Describes what biometric hardware the device supports.
    enum BiometryKind: Equatable {
        case faceID
        case touchID
        case none
    }

    /// The biometric type available on the current device. Returns `.none` if the
    /// device has no enrolled biometrics or if the policy cannot be evaluated.
    var availableBiometry: BiometryKind {
        let (ok, _) = evaluator.canEvaluate(policy: .deviceOwnerAuthenticationWithBiometrics)
        guard ok else { return .none }
        switch evaluator.biometryType {
        case .faceID:   return .faceID
        case .touchID:  return .touchID
        default:        return .none
        }
    }

    /// Whether the device supports and has enrolled biometrics of any type.
    var isBiometryAvailable: Bool {
        availableBiometry != .none
    }

    // MARK: - Authentication

    /// The result of a biometric authentication attempt.
    enum BiometricResult: Equatable {
        /// OS accepted the biometric; `userId` is the opted-in user.
        case success(userId: Int64)
        /// OS rejected or the user cancelled; fall back to PIN for `userId` (if known).
        case fallback(userId: Int64?)
        /// No opted-in user or biometry not available; do nothing.
        case notAvailable
    }

    /// Attempt biometric authentication for the preferred opted-in user.
    ///
    /// - Parameter reason: The localised string shown in the system Face ID / Touch ID dialog.
    /// - Returns: A `BiometricResult` indicating success, fallback, or unavailability.
    func attemptBiometricAuth(reason: String = "Sign in to WiredPart") async -> BiometricResult {
        guard let userId = preferredBiometricUserId, isOptedIn(userId: userId) else {
            return .notAvailable
        }

        guard isBiometryAvailable else {
            Self.logger.info("biometricPromptSkipped: biometry unavailable, userId=\(userId, privacy: .private)")
            return .fallback(userId: userId)
        }

        Self.logger.info("biometricPromptShown: userId=\(userId, privacy: .private)")

        do {
            let ok = try await evaluator.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            if ok {
                Self.logger.info("biometricAuthSuccess: userId=\(userId, privacy: .private)")
                return .success(userId: userId)
            } else {
                Self.logger.info("biometricAuthFallback: result=false, userId=\(userId, privacy: .private)")
                return .fallback(userId: userId)
            }
        } catch {
            let laError = error as? LAError
            let isIntentional = laError?.code == .userCancel || laError?.code == .userFallback
            if isIntentional {
                Self.logger.info("biometricAuthFallback: userCancelled, userId=\(userId, privacy: .private)")
            } else {
                Self.logger.warning("biometricAuthFallback: error=\(error.localizedDescription), userId=\(userId, privacy: .private)")
            }
            return .fallback(userId: userId)
        }
    }
}
