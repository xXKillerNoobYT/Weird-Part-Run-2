import Foundation
import Security
import Testing

@testable import WiredPartCore

/// Guards the single shared answer to "is the keychain unusable here?".
///
/// This predicate has been got wrong three times (#1622 allowlist → app would
/// not start; #1647 fixed one caller and not the other → login every launch;
/// #1652 the denylist was one status too wide → fallback salt written over a
/// working keychain, presenting as lost data). Each regression was invisible to
/// the tests that existed at the time, so these assert the *shape* of the rule,
/// not just a few sampled values.
@Suite("KeychainAvailability")
struct KeychainAvailabilityTests {

    @Test("unrecognised failures rescue — the default must be to fall back")
    func testUnknownStatusesAreTreatedAsUnusable() {
        // The whole reason the denylist exists. We have still never measured
        // what the iPad-on-Mac keychain returns, so a status nobody enumerated
        // MUST rescue. An allowlist built from guesses failed in the field twice.
        #expect(KeychainAvailability.isUnusable(OSStatus(-77777)))
        #expect(KeychainAvailability.isUnusable(OSStatus(-88888)))
        #expect(KeychainAvailability.isUnusable(OSStatus(-99999)))

        // Known-unusable states, named so a future edit cannot quietly drop them.
        #expect(KeychainAvailability.isUnusable(errSecMissingEntitlement))
        #expect(KeychainAvailability.isUnusable(errSecNotAvailable))
        // errSecParam is the documented status for iOS accessibility classes on
        // Mac, and the prime suspect for the field failure.
        #expect(KeychainAvailability.isUnusable(errSecParam))
    }

    @Test("a working keychain that merely denied access must NOT rescue")
    func testTransientDenialsDoNotRescue() {
        // In every one of these a real key exists or belongs in the keychain.
        // Writing a sandbox key strands it: the database becomes undecryptable
        // (CipherKeyManager) or every live session invalidates (AuthService).
        #expect(!KeychainAvailability.isUnusable(errSecSuccess))
        #expect(!KeychainAvailability.isUnusable(errSecItemNotFound))
        #expect(!KeychainAvailability.isUnusable(errSecInteractionNotAllowed))

        // #1652 specifically: these two were being rescued. A user who failed or
        // dismissed a single auth prompt got a fallback salt written while the
        // real one sat in the keychain — which reads to that user as lost data.
        #expect(!KeychainAvailability.isUnusable(errSecAuthFailed))
        #expect(!KeychainAvailability.isUnusable(errSecUserCanceled))
    }

    @Test("the excluded set is exactly these five — additions must be deliberate")
    func testExcludedSetMembershipIsPinned() {
        // Pinning the set makes widening it a visible, reviewable diff rather
        // than a silent behaviour change. Widening is how #1652 happened.
        #expect(KeychainAvailability.worksButAccessDenied == [
            errSecSuccess,
            errSecItemNotFound,
            errSecInteractionNotAllowed,
            errSecAuthFailed,
            errSecUserCanceled
        ])
    }

    @Test("AuthService delegates rather than keeping its own copy")
    func testAuthServiceAgreesWithSharedPredicate() {
        // The divergence between two independent copies is the root cause of all
        // three bugs. This fails the moment AuthService regains its own logic.
        for status in [errSecSuccess, errSecItemNotFound, errSecInteractionNotAllowed,
                       errSecAuthFailed, errSecUserCanceled, errSecMissingEntitlement,
                       errSecNotAvailable, errSecParam, OSStatus(-77777)] {
            #expect(AuthService.canUseSigningKeyFallback(for: status)
                    == KeychainAvailability.isUnusable(status),
                    "AuthService diverged from KeychainAvailability on \(status)")
        }
    }
}
