# WEI-327 QA Closure Evidence Review (2026-05-09)

## 1. Verdict
Revise

## 2. Findings by severity

### Critical
- None.

### High
- **Per-user-per-computer profile constraint is not proven and appears unenforced.**
  - The onboarding flow always creates a new active business profile (`isActive: 1`) with no pre-check or upsert path, so repeated onboarding attempts can create multiple active rows.

### Medium
- **Capability-gate matrix closure evidence is incomplete.**
  - Permission gating exists in navigation definitions and inline view modifiers, but there is no explicit QA artifact showing a capability matrix execution result (roles x capabilities with pass/fail evidence) tied to this closure.

### Low
- **Tests validate existence/update only, not the uniqueness constraint claim.**
  - Existing tests cover `hasBusinessProfile` and CRUD basics, but none assert that only one active business profile can exist per user/device/computer.

## 3. Evidence

- High finding evidence:
  - `createBusinessProfile` inserts directly with no uniqueness/replace logic: `core/Sources/WiredPartCore/Services/SettingsService.swift:349`.
  - Active profile lookup is `fetchOne` on `is_active = 1`, which does not enforce single-row integrity: `core/Sources/WiredPartCore/Services/SettingsService.swift:340`.
  - Onboarding always writes a new active profile: `Weird Parts IOS/Weird Parts IOS/Auth/BusinessProfileSetupView.swift:171` and `Weird Parts IOS/Weird Parts IOS/Auth/BusinessProfileSetupView.swift:192`.

- Medium finding evidence:
  - Capability gating is represented in config (`permission` on modules/tabs): `Weird Parts IOS/Weird Parts IOS/Navigation/NavigationConfig.swift:9`, `Weird Parts IOS/Weird Parts IOS/Navigation/NavigationConfig.swift:58`.
  - No WEI-327-specific matrix artifact found in docs search (`WEI-327`, `capability-gate matrix`, `closure evidence`) during this review heartbeat.

- Low finding evidence:
  - Business profile tests cover create/update/has-profile paths only: `core/Tests/WiredPartCoreTests/SettingsServiceTests.swift:267`, `core/Tests/WiredPartCoreTests/SettingsServiceTests.swift:298`, `core/Tests/WiredPartCoreTests/SettingsServiceTests.swift:311`.

## 4. Required follow-ups and owner

1. **Owner: Implementation (Core/Settings)**
   - Add an explicit invariant for active business profile uniqueness (DB constraint and/or service-level transactional guard/upsert semantics).

2. **Owner: QA**
   - Produce a capability-gate matrix artifact for closure (minimum: role/hat x gated module/tab/action, expected gate, observed result, evidence reference).

3. **Owner: QA + Tests**
   - Add regression tests proving the profile uniqueness constraint behavior (attempt second active create, verify deterministic outcome and no multi-active state).
