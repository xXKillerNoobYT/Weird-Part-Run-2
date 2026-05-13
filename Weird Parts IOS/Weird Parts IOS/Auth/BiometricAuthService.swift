import Foundation
import LocalAuthentication

protocol BiometricEvaluator {
    func canEvaluate(policy: LAPolicy) -> (Bool, Error?)
    var biometryType: LABiometryType { get }
    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String) async throws -> Bool
}

struct LocalAuthenticationBiometricEvaluator: BiometricEvaluator {
    private let context: LAContext

    init(context: LAContext = LAContext()) {
        self.context = context
    }

    func canEvaluate(policy: LAPolicy) -> (Bool, Error?) {
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(policy, error: &error)
        return (canEvaluate, error)
    }

    var biometryType: LABiometryType {
        context.biometryType
    }

    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String) async throws -> Bool {
        try await context.evaluatePolicy(policy, localizedReason: localizedReason)
    }
}

enum BiometricAuthResult: Equatable {
    case success(userId: Int64)
    case fallback(userId: Int64)
    case notAvailable
}

@MainActor
final class BiometricAuthService {
    private enum Keys {
        static let preferredUserId = "biometric.preferredUserId"

        static func optIn(_ userId: Int64) -> String {
            "biometric.optIn.\(userId)"
        }
    }

    private let evaluator: BiometricEvaluator
    private let defaults: UserDefaults

    init(
        evaluator: BiometricEvaluator = LocalAuthenticationBiometricEvaluator(),
        defaults: UserDefaults = .standard
    ) {
        self.evaluator = evaluator
        self.defaults = defaults
    }

    var preferredBiometricUserId: Int64? {
        guard let value = defaults.object(forKey: Keys.preferredUserId) as? NSNumber else {
            return nil
        }
        let userId = value.int64Value
        return isOptedIn(userId: userId) ? userId : nil
    }

    var availableBiometry: LABiometryType {
        let result = evaluator.canEvaluate(policy: .deviceOwnerAuthenticationWithBiometrics)
        return result.0 ? evaluator.biometryType : .none
    }

    var isBiometryAvailable: Bool {
        availableBiometry != .none
    }

    func setOptIn(userId: Int64, enabled: Bool) {
        let optInKey = Keys.optIn(userId)
        if enabled {
            defaults.set(true, forKey: optInKey)
            defaults.set(userId, forKey: Keys.preferredUserId)
        } else {
            defaults.removeObject(forKey: optInKey)
            if preferredBiometricUserId == userId {
                defaults.removeObject(forKey: Keys.preferredUserId)
            }
        }
    }

    func isOptedIn(userId: Int64) -> Bool {
        defaults.bool(forKey: Keys.optIn(userId))
    }

    func attemptBiometricAuth() async -> BiometricAuthResult {
        guard let userId = preferredBiometricUserId else {
            return .notAvailable
        }

        guard isBiometryAvailable else {
            return .fallback(userId: userId)
        }

        do {
            let success = try await evaluator.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Use biometrics to unlock WiredPart."
            )
            return success ? .success(userId: userId) : .fallback(userId: userId)
        } catch {
            return .fallback(userId: userId)
        }
    }
}
