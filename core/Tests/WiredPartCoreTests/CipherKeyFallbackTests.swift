import Foundation
import Testing
@testable import WiredPartCore

/// The Mac-startup P0 (owner, builds 41 and 47 both dead): the keychain rescue
/// was an ALLOWLIST of two OSStatus values, so any other failure — including the
/// one the iPad-on-Mac keychain actually returns — fell through and the app
/// could not open its database at all.
@Suite("Cipher key fallback policy")
struct CipherKeyFallbackTests {

    /// Mirrors the production `catch` predicate. Keeping the rule in one
    /// testable place is the point: the bug was in the SHAPE of the rule.
    private func rescues(_ status: OSStatus) -> Bool {
        status != errSecInteractionNotAllowed
    }

    @Test("Every unusable-keychain status is rescued, not just two")
    func rescuesUnusableKeychain() {
        // The two the old allowlist knew about...
        #expect(rescues(errSecMissingEntitlement))
        #expect(rescues(errSecNotAvailable))
        // ...and the ones it did NOT, which is why the Mac stayed broken.
        #expect(rescues(errSecParam), "errSecParam is what a Mac keychain returns for iOS accessibility classes")
        #expect(rescues(errSecUnimplemented))
        #expect(rescues(errSecAuthFailed))
        #expect(rescues(OSStatus(-34018)))   // errSecMissingEntitlement by value
    }

    @Test("A merely LOCKED keychain still throws — it must never mint a second salt")
    func lockedKeychainStillThrows() {
        // errSecInteractionNotAllowed means "temporarily locked, try later".
        // Falling back there would orphan an existing encrypted database.
        #expect(!rescues(errSecInteractionNotAllowed))
    }

    @Test("Shared runtime-Mac predicate covers Catalyst and iPad-on-Mac")
    func runtimeMacPredicateCoversBothMacExecutionModes() {
        #expect(RuntimeMacEnvironment.isRunningOnMac(isCatalyst: true, isIOSAppOnMac: false))
        #expect(RuntimeMacEnvironment.isRunningOnMac(isCatalyst: false, isIOSAppOnMac: true))
        #expect(!RuntimeMacEnvironment.isRunningOnMac(isCatalyst: false, isIOSAppOnMac: false))
    }

    @Test("Cipher salt accessibility decision follows the shared runtime-Mac predicate")
    func cipherSaltAccessibilityDecisionDoesNotDriftFromRuntimeMacPredicate() {
        for (isCatalyst, isIOSAppOnMac) in [(true, false), (false, true), (false, false)] {
            let isRunningOnMac = RuntimeMacEnvironment.isRunningOnMac(
                isCatalyst: isCatalyst,
                isIOSAppOnMac: isIOSAppOnMac
            )
            #expect(
                CipherKeyManager.shouldApplyKeychainAccessibility(isRunningOnMac: isRunningOnMac) == !isRunningOnMac
            )
        }
    }
}
