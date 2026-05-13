//
//  Weird_Parts_IOSTests.swift
//  Weird Parts IOSTests
//
//  Created by Isaac Aznoe on 3/15/26.
//

import Testing
import LocalAuthentication
@testable import Weird_Parts

private enum QuestionnaireBreakTestError: Error {
    case autoFillFailed
}

// MARK: - Mock Evaluator

/// Test double for `BiometricEvaluator` — lets tests control availability and outcome
/// without any device interaction or simulator setup.
final class MockBiometricEvaluator: BiometricEvaluator {
    var canEvaluateResult: Bool = true
    var canEvaluateError: Error? = nil
    var stubbedBiometryType: LABiometryType = .faceID
    /// When `nil`, `evaluatePolicy` throws `LAError.authenticationFailed`.
    var evaluateShouldSucceed: Bool? = true

    func canEvaluate(policy: LAPolicy) -> (Bool, Error?) {
        (canEvaluateResult, canEvaluateError)
    }

    var biometryType: LABiometryType { stubbedBiometryType }

    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String) async throws -> Bool {
        guard let result = evaluateShouldSucceed else {
            throw LAError(.authenticationFailed)
        }
        return result
    }
}

// MARK: - Questionnaire Break Compliance

@Suite("Questionnaire break compliance auto-fill")
@MainActor
struct QuestionnaireBreakComplianceTests {

    @Test("all taken without break buttons propagates auto-fill failure")
    func testAllTakenAutoFillFailureBlocksSubmit() {
        var autoFillAttempts = 0

        do {
            try QuestionnaireBreakComplianceSubmitter.submit(
                verification: .allTaken,
                hadBreakButtons: false,
                missedBreaks: []
            ) {
                autoFillAttempts += 1
                throw QuestionnaireBreakTestError.autoFillFailed
            }
            Issue.record("Expected auto-fill failure to propagate")
        } catch QuestionnaireBreakTestError.autoFillFailed {
            #expect(autoFillAttempts == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("forgot break path runs required auto-fill successfully")
    func testForgotBreakAutoFillSuccess() throws {
        var autoFillAttempts = 0

        try QuestionnaireBreakComplianceSubmitter.submit(
            verification: .forgot,
            hadBreakButtons: false,
            missedBreaks: ["morning_break", "lunch", "afternoon_break"]
        ) {
            autoFillAttempts += 1
        }

        #expect(autoFillAttempts == 1)
    }

    @Test("all taken with existing break buttons does not auto-fill")
    func testExistingBreakButtonsSkipAutoFill() throws {
        var autoFillAttempts = 0

        try QuestionnaireBreakComplianceSubmitter.submit(
            verification: .allTaken,
            hadBreakButtons: true,
            missedBreaks: []
        ) {
            autoFillAttempts += 1
        }

        #expect(autoFillAttempts == 0)
    }
}

// MARK: - Helpers

/// Isolates UserDefaults mutations to a named suite so tests don't pollute the
/// real standard suite and can be reliably cleaned up.
private struct BiometricTestDefaults {
    static let suiteName = "com.wiredpart.tests.biometric"
    static var suite: UserDefaults { UserDefaults(suiteName: suiteName)! }

    static func reset() {
        suite.removePersistentDomain(forName: suiteName)
        suite.synchronize()
    }
}

// MARK: - Tests

@Suite("BiometricAuthService — Opt-In Persistence", .serialized)
@MainActor
struct BiometricOptInPersistenceTests {

    private func makeService() -> BiometricAuthService {
        BiometricTestDefaults.reset()
        return BiometricAuthService(defaults: BiometricTestDefaults.suite)
    }

    @Test("setOptIn(enabled:true) marks the user as opted in")
    func testSetOptInTrue() {
        let svc = makeService()
        defer { svc.setOptIn(userId: 99, enabled: false) }

        svc.setOptIn(userId: 99, enabled: true)
        #expect(svc.isOptedIn(userId: 99) == true)
    }

    @Test("setOptIn(enabled:false) clears the opt-in flag")
    func testSetOptInFalse() {
        let svc = makeService()
        svc.setOptIn(userId: 42, enabled: true)
        svc.setOptIn(userId: 42, enabled: false)
        #expect(svc.isOptedIn(userId: 42) == false)
    }

    @Test("isOptedIn returns false for a user who never opted in")
    func testIsOptedInDefaultFalse() {
        let svc = makeService()
        #expect(svc.isOptedIn(userId: 777) == false)
    }

    @Test("preferredBiometricUserId returns the last opted-in userId")
    func testPreferredUserIdSetOnOptIn() {
        let svc = makeService()
        defer { svc.setOptIn(userId: 55, enabled: false) }

        svc.setOptIn(userId: 55, enabled: true)
        #expect(svc.preferredBiometricUserId == 55)
    }

    @Test("preferredBiometricUserId is cleared when the opted-in user disables biometric")
    func testPreferredUserIdClearedOnDisable() {
        let svc = makeService()
        svc.setOptIn(userId: 33, enabled: true)
        svc.setOptIn(userId: 33, enabled: false)
        #expect(svc.preferredBiometricUserId == nil)
    }

    @Test("preferredBiometricUserId is NOT cleared when a different user disables their opt-in")
    func testPreferredUserIdPreservedWhenDifferentUserDisables() {
        let svc = makeService()
        defer {
            svc.setOptIn(userId: 10, enabled: false)
            svc.setOptIn(userId: 20, enabled: false)
        }

        svc.setOptIn(userId: 10, enabled: true)  // userId 10 is now last opted-in
        svc.setOptIn(userId: 20, enabled: false) // disabling userId 20 should not wipe userId 10
        #expect(svc.preferredBiometricUserId == 10)
    }

    @Test("preferredBiometricUserId returns nil when no user has ever opted in")
    func testPreferredUserIdNilByDefault() {
        let svc = makeService()
        #expect(svc.preferredBiometricUserId == nil)
    }
}

// MARK: - Availability + Fallback Branch Tests

@Suite("BiometricAuthService — Availability & Fallback Branches", .serialized)
@MainActor
struct BiometricAvailabilityTests {

    @Test("availableBiometry returns .faceID when evaluator reports Face ID")
    func testAvailabilityFaceID() {
        let mock = MockBiometricEvaluator()
        mock.canEvaluateResult = true
        mock.stubbedBiometryType = .faceID
        let svc = BiometricAuthService(evaluator: mock)
        #expect(svc.availableBiometry == .faceID)
    }

    @Test("availableBiometry returns .touchID when evaluator reports Touch ID")
    func testAvailabilityTouchID() {
        let mock = MockBiometricEvaluator()
        mock.canEvaluateResult = true
        mock.stubbedBiometryType = .touchID
        let svc = BiometricAuthService(evaluator: mock)
        #expect(svc.availableBiometry == .touchID)
    }

    @Test("availableBiometry returns .none when canEvaluate returns false")
    func testAvailabilityNone() {
        let mock = MockBiometricEvaluator()
        mock.canEvaluateResult = false
        let svc = BiometricAuthService(evaluator: mock)
        #expect(svc.availableBiometry == .none)
    }

    @Test("isBiometryAvailable is true when Face ID is available")
    func testIsBiometryAvailableTrue() {
        let mock = MockBiometricEvaluator()
        mock.canEvaluateResult = true
        mock.stubbedBiometryType = .faceID
        let svc = BiometricAuthService(evaluator: mock)
        #expect(svc.isBiometryAvailable == true)
    }

    @Test("isBiometryAvailable is false when biometry is not enrolled")
    func testIsBiometryAvailableFalse() {
        let mock = MockBiometricEvaluator()
        mock.canEvaluateResult = false
        let svc = BiometricAuthService(evaluator: mock)
        #expect(svc.isBiometryAvailable == false)
    }
}

// MARK: - attemptBiometricAuth Branch Tests

@Suite("BiometricAuthService — attemptBiometricAuth Branches", .serialized)
@MainActor
struct BiometricAttemptTests {

    /// Creates a service pre-configured with an opted-in user and a controllable evaluator.
    private func makeService(
        userId: Int64 = 1,
        canEval: Bool = true,
        biometryType: LABiometryType = .faceID,
        evaluateShouldSucceed: Bool? = true
    ) -> BiometricAuthService {
        let mock = MockBiometricEvaluator()
        mock.canEvaluateResult = canEval
        mock.stubbedBiometryType = biometryType
        mock.evaluateShouldSucceed = evaluateShouldSucceed
        BiometricTestDefaults.reset()
        let svc = BiometricAuthService(evaluator: mock, defaults: BiometricTestDefaults.suite)
        svc.setOptIn(userId: userId, enabled: true)
        return svc
    }

    @Test("returns .success when OS accepts biometric for opted-in user")
    func testAuthSuccess() async {
        let svc = makeService(userId: 1, canEval: true, evaluateShouldSucceed: true)
        defer { svc.setOptIn(userId: 1, enabled: false) }

        let result = await svc.attemptBiometricAuth()
        #expect(result == .success(userId: 1))
    }

    @Test("returns .fallback when OS rejects biometric (evaluatePolicy returns false)")
    func testAuthFailsWithFalseResult() async {
        let svc = makeService(userId: 2, canEval: true, evaluateShouldSucceed: false)
        defer { svc.setOptIn(userId: 2, enabled: false) }

        let result = await svc.attemptBiometricAuth()
        #expect(result == .fallback(userId: 2))
    }

    @Test("returns .fallback when evaluatePolicy throws (e.g. authenticationFailed)")
    func testAuthFallbackOnError() async {
        let svc = makeService(userId: 3, canEval: true, evaluateShouldSucceed: nil)
        defer { svc.setOptIn(userId: 3, enabled: false) }

        let result = await svc.attemptBiometricAuth()
        #expect(result == .fallback(userId: 3))
    }

    @Test("returns .fallback when biometry hardware is not available (canEvaluate false)")
    func testFallbackWhenBiometryUnavailable() async {
        let svc = makeService(userId: 4, canEval: false, evaluateShouldSucceed: true)
        defer { svc.setOptIn(userId: 4, enabled: false) }

        let result = await svc.attemptBiometricAuth()
        // When canEvaluate fails, biometry is unavailable → .fallback with userId preserved.
        #expect(result == .fallback(userId: 4))
    }

    @Test("returns .notAvailable when no user has opted in")
    func testNotAvailableWhenNoOptIn() async {
        let mock = MockBiometricEvaluator()
        mock.canEvaluateResult = true
        BiometricTestDefaults.reset()
        let svc = BiometricAuthService(evaluator: mock, defaults: BiometricTestDefaults.suite)
        // Do not call setOptIn — no one has opted in.
        let result = await svc.attemptBiometricAuth()
        #expect(result == .notAvailable)
    }

    @Test("returns .notAvailable when opted-in user's flag is cleared")
    func testNotAvailableAfterOptOut() async {
        let mock = MockBiometricEvaluator()
        mock.canEvaluateResult = true
        BiometricTestDefaults.reset()
        let svc = BiometricAuthService(evaluator: mock, defaults: BiometricTestDefaults.suite)

        svc.setOptIn(userId: 5, enabled: true)
        svc.setOptIn(userId: 5, enabled: false) // clear it

        let result = await svc.attemptBiometricAuth()
        #expect(result == .notAvailable)
    }
}

// MARK: - Settings Validation Tests

@Suite("Organization Threshold Settings Validation")
struct OrganizationThresholdSettingsValidationTests {
    @Test("accepts non-zero in-range threshold settings")
    func testValidThresholdSettings() {
        #expect(OrganizationThresholdSettingsValidation.isValid(
            baseDecayRate: 0.1,
            movementDecayFactor: 0.5,
            auditThreshold: 80,
            maxRecsPerDay: 1,
            recCooldownDays: 60,
            votingTimeoutDays: 7,
            minVotesRequired: 2,
            targetScore: 85
        ))
    }

    @Test("rejects zero threshold settings")
    func testRejectsZeroThresholdSettings() {
        #expect(!OrganizationThresholdSettingsValidation.isValid(
            baseDecayRate: 0,
            movementDecayFactor: 0.5,
            auditThreshold: 80,
            maxRecsPerDay: 1,
            recCooldownDays: 60,
            votingTimeoutDays: 7,
            minVotesRequired: 2,
            targetScore: 85
        ))

        #expect(!OrganizationThresholdSettingsValidation.isValid(
            baseDecayRate: 0.1,
            movementDecayFactor: 0.5,
            auditThreshold: 0,
            maxRecsPerDay: 1,
            recCooldownDays: 60,
            votingTimeoutDays: 7,
            minVotesRequired: 2,
            targetScore: 85
        ))

        #expect(!OrganizationThresholdSettingsValidation.isValid(
            baseDecayRate: 0.1,
            movementDecayFactor: 0.5,
            auditThreshold: 80,
            maxRecsPerDay: 1,
            recCooldownDays: 60,
            votingTimeoutDays: 7,
            minVotesRequired: 2,
            targetScore: 0
        ))
    }
}

// MARK: - Type Brand Selection Tests

@Suite("Type brand selection")
@MainActor
struct TypeBrandSelectionTests {
    @Test("General is the default type brand selection")
    func generalBrandSelectedByDefault() {
        #expect(TypeBrandSelectionDefaults.isGeneralSelectedOnLoad)
    }

    @Test("brand removal confirmation names the brand and destructive consequence")
    func brandRemovalConfirmationMessage() {
        let confirmation = BrandRemovalConfirmation(brandId: 42, brandName: "Southwire")

        #expect(confirmation.message == "Are you sure you want to remove brand Southwire from this type? This may affect linked parts and colors.")
    }
}
