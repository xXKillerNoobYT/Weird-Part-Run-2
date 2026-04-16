# Issue Closure Audit Tracker

> **Purpose:** Log every weekly audit run by the `issue-closure-verifier` scheduled task. Each run appends a dated section. Used to track premature-close incidents over time and surface patterns.
>
> **Meta-issue:** #233 — see its comment history for the incident that triggered this routine (#221 prematurely closed 2026-04-15 while active in dev-qa.md Pending Q13).

---

## Audit Run 2026-04-16

- **Scanned:** 160 issues closed in last 30 days (since 2026-03-17)
- **Reopened:** 2 issues (#148, #146)
- **Left closed (spot-checked deep):** 8 issues verified genuinely fixed
- **Left closed (pattern-scanned only):** ~150 issues — no suspicious patterns found
- **Flagged for manual review:** 0

### Reopened this run

- `#148` — `[Usability] Scanner 1: IOSMovementWizard missing Save & Exit button` — **Check A**: `docs/dev-qa.md` Pending Questions (lines 23–48) has 4 unanswered design questions for this issue (priority, scope, storage approach, draft lifetime). An automated agent implemented Save & Exit using UserDefaults without owner ratification. Q&A entry still shows all answers as `_pending_`. Design source of truth: `docs/dev-qa.md` lines 23–48.

- `#146` — `[Performance] Formatters.swift is dead code — 99 inline DateFormatter() instantiations` — **Check D**: The last comment on the issue (2026-04-15T04:46:19Z) explicitly says *"Reopening per user policy: not 100% done"* — but the `gh issue reopen` call apparently silently failed, leaving the issue CLOSED. 57 inline `DateFormatter()`/`ISO8601DateFormatter()` instantiations still remain in `core/Sources/WiredPartCore/Services/`. Close comment rationale directly contradicts closed state.

### Left closed (deep-verified)

- `#221` — Already OPEN prior to this run (correctly reopened 2026-04-15 after previous premature auto-close). Not in scope of this audit.
- `#223` — `[Performance] BaseRepository.findAll() has no default limit` — Check E: Phase 1 fix (LIMIT 1000 default) confirmed shipped per `docs/plans/pagination-cutover.md` Phase 1 status. Reported bug (no limit on findAll) is resolved. Remaining phases (audit + cursor pagination) tracked separately in plan file.
- `#224` — `[Parts][Info] Forecasting ADU includes transfer movements` — Check B: `docs/plans/april-2026-audit-closures.md` Decision 1 status is "Code already in working tree (2026-04-14)." Close comment confirms all 6 ADU/APW query blocks patched. Plan status and close are consistent.
- `#227` — `[Parts][Performance] Service-layer pagination missing — Parts catalog` — Check D: Closed as "false positive" because `listCatalogParts`, `listParts`, `searchParts`, `listForecastData` all already accept `limit/offset` parameters with `LIMIT ? OFFSET ?` in SQL. The close cites specific line numbers. Legitimate false positive.
- `#152` — `[Chat] IOSMessageThreadView: photo + reference picker buttons are dead` — Check E: Commit `7024173` verified to exist (`git cat-file -e` returned 0). Commit message confirms both PhotosPicker and ReferencePickerSheet are wired. PE-043 archived to done/.
- `#232` — `[Jobs][Bug] IOSJobDetailTabView progress bar crashes when job has only 1 stage` — Check E: Close comment cites specific file:line (`IOSJobDetailTabView.swift:1185`) with exact fix. Guard prevents division by zero. Genuine.
- `#231` — `[Security][Medium] Keychain signing key uses AfterFirstUnlock accessibility` — Check E: Fixed by upgrading to `WhenUnlockedThisDeviceOnly` + SecItemUpdate migration path. Genuine.
- `#225` — `[Sync][Info] DeviceIdentity.current should be let instead of var` — Check E: Changed from `nonisolated(unsafe) var` to `let`. Swift lazy static-let is thread-safe by design. Genuine.

### Pattern scan results

- **Check D suspicious patterns scanned**: 7 issues flagged by keyword search (`"false positive"`, `"not a bug"`, `"documented as known limitation"`, etc.). All 7 investigated:
  - `#227` — false positive, legitimate (see above)
  - `#158` — "not a bug" + "Clarification from Owner" — legitimate owner clarification
  - `#147` — partial fix (2/3), 1 was false positive — legitimate  
  - `#142` — verified all 11 catch blocks individually, none empty — legitimate
  - `#118` — `deleteTeam()` is synchronous, await is on MainActor only — legitimate
  - `#113` — CascadePriceEditSheet intentionally stays open for multi-edit — by design
  - `#5` — JPO button empty action is intentional per code comment — legitimate

- **Check C (Xcode prompt queue)**: PE-044 (🔲 NEXT) references #143/#123. Both issues confirmed still OPEN — no Check C violation.

- **Check A broad scan**: Only #148 references an active Pending Questions entry. The April 2026 Audit cluster (#221/#223/#224/#227) is inside an HTML comment block in dev-qa.md (archived 2026-04-14) — not active pending.

---

*Next run scheduled: Sunday 2026-04-23 at 07:03 AM local.*
