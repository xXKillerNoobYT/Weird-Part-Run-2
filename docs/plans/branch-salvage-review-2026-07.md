# Branch Salvage Review — 2026-07

> **Date:** 2026-07-02
> **Issue:** [#1374](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/1374) — Disposition for 3 keep-live branches
> **Author:** Paperclip / Claude beta-completion pass
> **Status:** Findings + recommendations. **The owner makes the final delete/keep call** — this review does not close #1374.
> **Related:** [AI-Assisted Universal Import Architecture](ai-assisted-universal-import-architecture.md) (WEI-2812 plan of record)

---

## Summary

The 2026-07-02 branch drain (#513, decided in #1348) kept three branches alive pending a real disposition. This review diffs each against `main` (`fc35d6dd1` at review time) and categorizes what is **unlanded and still-relevant** vs **already-landed / superseded**.

| Branch | Tip | Verdict | Action |
|---|---|---|---|
| `WEI-2953-…-universal-import-architecture-and-staged-delivery-plan` | `bc22c43a1` | Landed by this PR | Plan doc moved into `docs/plans/`. **Branch can be archived-tag + deleted.** |
| `WEI-2958-…-stage-3-add-digital-pdf-and-ocr-import-preview-adapters` | `6c3eaaffc` | **Unique work, but does NOT apply cleanly** | Re-implement Stage 3 on current `main`; do not merge the branch as-is. **Keep as archive tag until re-implemented, then delete.** |
| `codex/wei-1028-auth-hardening-local-sync-20260513` | `2c1d45cde` | **~99% landed / superseded; one live gap** | Salvage only the sync `#385` decrypt-propagation fix (re-implement); auth-hardening is already on `main` and further-evolved. **Archive-tag + delete after the sync gap is filed.** |

---

## 1. WEI-2953 — universal-import plan doc

**What it is:** a single 188-line plan doc, `docs/plans/ai-assisted-universal-import-architecture.md`, the WEI-2812 architecture/staged-delivery plan.

**Status vs main:** the doc did not exist anywhere on `main`.

**Disposition:** **Landed by the PR that adds this review.** The doc was copied verbatim into `docs/plans/` (repo rule: plans live there) with an added status header and a refreshed "Delivery Constraints" note reflecting the 2026-07-02 cleanup. Stage markers were annotated to show Stages 1–2 have since landed on `main` and Stage 3 is the WEI-2958 concern below.

**Recommendation:** the branch has no further unique content. Tag `archive/WEI-2953-…-20260702` (if not already) and delete the remote head.

---

## 2. WEI-2958 — Stage-3 digital PDF + OCR preview adapters

**What it is:** one commit (`6c3eaaffc`) touching two files:

- `core/Sources/WiredPartCore/Services/PartsService+OCRImportPreview.swift` (+203/−4)
- `core/Tests/WiredPartCoreTests/PartsOCRImportPreviewTests.swift` (+94)

**Unique, still-relevant capability the branch adds (none of this is on `main`):**

- `previewPartsImportDigitalPDF(pages:chunkLineLimit:)` — a digital-PDF text-layer table extraction adapter (`extractDigitalPDFTables`) that emits `PartsImportExtractedTable` / `PartsImportDraftRow` with per-row `PartsImportSourceEvidence`, sourced as `.digitalPDFText`.
- A chunks/candidates **bridge overload** `previewPartsImportOCR(chunks:candidates:errors:quarantineThreshold:)` that lets platform-side OCR feed the shared preview model.
- A **quarantine flow**: `PartsOCRImportCandidate` gains `isQuarantined` / `quarantineReason` / `sourceKind` / `sourceEvidence`; `PartsOCRImportPreview` gains `tables`, `reviewReadyCandidates`, `quarantinedCandidates`; low-confidence OCR rows (`< OCRConfidence.medium`) are quarantined and blocked from commit (`isCommitAllowed` stays `false`).
- Header parsing improvement: treats a `description` column as `name` when no explicit `name` column exists.
- Three new tests covering digital-PDF table extraction with page evidence, the OCR bridge, and low-confidence quarantine (asserting no parts are written).

This directly implements Stage 3 of the WEI-2812 plan and remains genuinely desirable post-beta.

**Why it must NOT be merged as-is:** the branch was cut from the Stage-1 merge base (`550bbe5a5`, PR #928) **before** the OCR file reached its current shape on `main`. The signatures have since diverged:

- On the **branch**, the pages-based prototype is one of *three* preview entry points and the chunks-based `previewPartsImportOCR` is an added overload.
- On **`main`**, `previewPartsImportOCR(pages:chunkLineLimit:)` is the *only* preview entry point (it takes `pages:`, not `chunks:`), and the candidate/preview structs do **not** carry `sourceKind`, `sourceEvidence`, `isQuarantined`, `tables`, or the review/quarantine computed properties.

Merging or cherry-picking `6c3eaaffc` onto `main` would collide on the struct definitions and the `previewPartsImportOCR` shape. It needs a **re-implementation**, not a merge.

**Recommendation:**

1. Open a fresh Stage-3 issue under WEI-2812 (or reuse WEI-2958's tracker) and re-apply the four capabilities above onto current `main`, keeping the existing `previewPartsImportOCR(pages:)` entry point and *adding* the digital-PDF adapter + quarantine fields alongside it.
2. Port the three tests (they are well-formed and assert the no-write invariant).
3. Keep commit blocked (`isCommitAllowed == false`) until the Stage-4 audit/commit consolidation and a security review land — consistent with the plan.
4. Until re-implemented, retain an `archive/WEI-2958-…-20260702` tag so the reference implementation is not lost, then delete the remote head.

---

## 3. codex/wei-1028-auth-hardening-local-sync-20260513

**What it is:** a long-lived (182-commit) parallel branch with **no merge base** to `main` (unrelated history). Its #278 slices were already rescued and re-landed via PR #1370. This review checked the two auth/sync-specific commits it was kept alive for.

### 3a. Auth hardening (`17975cb03` "Harden local auth sessions") — **LANDED / SUPERSEDED**

The commit added local session tokens, refresh-token rotation, revocation, PIN lockout/throttle, and PBKDF2 PIN verification to `core/Sources/WiredPartCore/Services/AuthService.swift` (+ app-layer `BiometricAuthService.swift` + tests).

Direct symbol comparison against `main`'s `AuthService.swift` (branch = 1110 lines, main = 1614 lines):

| Symbol | Branch | main |
|---|---|---|
| `auth_token_sessions` (table) | 5 | **8** |
| `issueSessionTokens` | 4 | 3 |
| `refreshLocalSession` | 1 | 1 |
| `revokeLocalSession` | 1 | 1 |
| `sessionRevoked` | 3 | 3 |
| `iteratedSHA256Pin` | present | present |
| `isPBKDF2Hash` (private helper) | 2 | **0** |

`main` is a strict superset+: it already has all of the branch's session-token/rotation/revocation/lockout/PBKDF2 hardening **and goes further** — transparent legacy-hash upgrades and multiple SHA-256 verification tiers (`verifyPBKDF2`, `pbkdf2$…` prefix detection at `AuthService.swift` ~L871–L888). The only branch-unique symbol, the private `isPBKDF2Hash` helper, is functionally replaced by `main`'s prefix-based detection. **Nothing to salvage here.** `BiometricAuthService` also already exists on `main` (at the app path `Weird Parts IOS/Weird Parts IOS/Auth/BiometricAuthService.swift`).

### 3b. Sync silent-fallback fix (`ac2a1e3c7` "fix(sync): propagate encryption/decode failures instead of silent fallback (#385)") — **STILL UNLANDED, still relevant**

This is the one genuinely-unlanded, still-relevant item on the entire codex branch. It rewrote `core/Sources/WiredPartCore/Sync/PeerManager.swift` so that key derivation, encryption, decryption, and decode **throw on failure** instead of using `try?` and silently continuing — closing a data-loss / silent-plaintext-downgrade hole.

`main` has evolved this file differently — it landed related fixes #197 (peer key handling no longer silently falls back) and #191 (X-Company-ID gating) — **but it did not adopt #385.** As of `main`, the anti-pattern the fix targets is still present:

```swift
// core/Sources/WiredPartCore/Sync/PeerManager.swift  (main, ~L719)
private func decrypt(_ data: Data, sharedKeyData: Data?) -> Data {
    guard let keyData = sharedKeyData,
          let plain = try? SyncCrypto.decryptAESGCM(data: data, keyData: keyData) else {
        return data   // <-- silently returns ciphertext-as-plaintext when a key WAS present but decryption failed
    }
    return plain
}
```

When `sharedKeyData == nil` this is intentional plaintext backward-compat. The concern is the case where a key **was** negotiated but `decryptAESGCM` throws: `try?` swallows the error and the raw (still-encrypted or corrupt) bytes are handed downstream as if they were valid plaintext, which can corrupt or drop synced changes without any signal. `main`'s `resolveSharedKey` (`try?` on `deriveSharedKeyData`) and the push/pull decode paths have the same swallow-and-continue shape.

**Recommendation:** do **not** try to merge the codex branch (unrelated history, and `main`'s PeerManager has moved on with #197/#191). Instead:

1. File a focused issue: *"PeerManager silently downgrades on decryption/decode failure — propagate errors (was #385)."*
2. Re-implement the narrow fix on current `main`: make `decrypt`/`resolveSharedKey`/push+pull decode throw when a key was present but crypto/decode fails, distinguishing that from the legitimate `sharedKeyData == nil` plaintext path. Port the branch's `PeerManagerTests` cases that assert propagation.
3. This is a data-integrity/security fix and should be treated as higher priority than the Stage-3 import work.

**Disposition for the branch:** once 3b is filed, tag `archive/codex-wei-1028-…-20260702` and delete the remote head. Its bundle is already preserved per #1374; see the issue comments for the operator-local archive location.

---

## Net recommendations for the owner (final call is yours)

1. **WEI-2953:** done — delete the branch (plan is now in `docs/plans/`).
2. **WEI-2958:** keep an archive tag; open/keep a Stage-3 issue to **re-implement** the digital-PDF + OCR-quarantine adapters on current `main` (the branch will not merge cleanly). Delete the head after re-implementation.
3. **codex/wei-1028:** auth-hardening is fully landed/superseded — nothing to salvage. **Salvage only the `#385` sync decrypt-propagation fix** (still a live gap on `main`); file it as its own issue and re-implement. Then archive-tag + delete the head.

No branch should be deleted until its archive tag exists and (for WEI-2958 / #385) its follow-up issue is filed, so nothing is lost.
