import Foundation
import Security

/// The single answer to "is the keychain unusable in this environment?"
///
/// **Why this type exists.** Two places need this decision — `CipherKeyManager`
/// (database salt) and `AuthService` (session signing key) — and for three
/// consecutive bugs they answered it differently:
///
/// 1. **#1622** gave both an ALLOWLIST: `errSecMissingEntitlement ||
///    errSecNotAvailable`. The iPad-on-Mac keychain returns neither, so the
///    rescue never fired and **the app could not open its database at all**.
/// 2. **#1647** fixed `CipherKeyManager` to a denylist. `AuthService` was left
///    on the allowlist, so the Mac would start and then **force a login on every
///    launch** — the same bug, one layer up, shipped as a separate fix.
/// 3. **#1652** found the remaining gap in the other direction: the denylist
///    excluded only `errSecInteractionNotAllowed`, so a user who merely failed
///    or cancelled an auth prompt would mint a fallback salt while the real one
///    sat in the keychain — presenting to that user as **lost data**.
///
/// Every one of those came from the same root cause: the same question answered
/// independently in two files. One predicate, both call sites, is the fix. Do
/// not reintroduce a local copy.
///
/// **The rule.** Rescue when the keychain is genuinely unusable *here*. Never
/// rescue when the keychain works and this attempt simply did not get the item —
/// in that case a real key exists (or belongs) in the keychain, and writing a
/// sandbox key strands it: the database becomes undecryptable, or every live
/// session silently invalidates.
///
/// **The default is to rescue.** The excluded set is enumerated; everything else,
/// including statuses nobody has seen, counts as unusable. That direction is
/// deliberate and is the whole lesson of #1622 → #1647: we still have not
/// measured what the iPad-on-Mac keychain actually returns, and an allowlist
/// built from guesses failed in the field twice. Guessing wrong here costs a
/// re-login; guessing wrong the other way costs the app starting at all.
public enum KeychainAvailability {

    /// `true` when `status` means the keychain cannot be used in this
    /// environment and a sandbox fallback is the correct response.
    ///
    /// Excluded — the keychain is fine, so a fallback would strand the real key:
    /// - `errSecSuccess` — nothing failed; callers must not consult a fallback.
    /// - `errSecItemNotFound` — normal first run. Generate and store properly.
    /// - `errSecInteractionNotAllowed` — locked, no UI. Transient; retry later.
    /// - `errSecAuthFailed` — the user failed authentication. Transient.
    /// - `errSecUserCanceled` — the user dismissed the prompt. Transient.
    public static func isUnusable(_ status: OSStatus) -> Bool {
        !worksButAccessDenied.contains(status)
    }

    /// Statuses that mean "the keychain works, this attempt just did not get it".
    /// Kept as data rather than a boolean chain so the test can assert the exact
    /// membership, and so adding a case is a one-line, reviewable change.
    static let worksButAccessDenied: Set<OSStatus> = [
        errSecSuccess,
        errSecItemNotFound,
        errSecInteractionNotAllowed,
        errSecAuthFailed,
        errSecUserCanceled
    ]
}
