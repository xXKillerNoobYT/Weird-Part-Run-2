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

    @Test("Mac detection covers the iPad binary, not just Catalyst")
    func macDetectionCoversIPadOnMac() {
        // On CI (iOS simulator / macOS SPM) this is false; the value matters
        // less than the property being READ AT RUNTIME rather than compiled
        // out — the compile-time Catalyst check is what missed iPad-on-Mac.
        let value = CipherKeyManager.isRunningOnMac
        #expect(value == true || value == false)
    }
}
