# WEI-327 Profile Constraint Evidence (2026-05-09)

## Verdict

Accept for closure evidence.

## Environment

- Workspace: `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-125-adding-to-the-plan-mcp`
- Test target: Swift Package `core`
- Command run from: `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-125-adding-to-the-plan-mcp/core`
- Assumption: in-memory `AppDatabase.openInMemoryDatabase()` applies the current migration chain and represents one local computer database.

## Rerunnable Verification

```bash
cd /Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-125-adding-to-the-plan-mcp/core
swift test --filter SettingsServiceTests
```

## Observed Output

```text
Suite "SettingsService Tests" passed after 4.158 seconds.
Test run with 55 tests in 1 suite passed after 4.158 seconds.
```

Profile-specific passing tests from the run:

```text
Test "creating second active business profile fails without adding another active row" passed
Test "activating a second business profile fails without adding another active row" passed
```

## Constraint Matrix

| Scenario | Expected behavior | Evidence | Result |
|---|---|---|---|
| First active business profile on a local DB | Create succeeds and `hasBusinessProfile()` becomes true | `SettingsServiceTests.testBusinessProfileCreate` | PASS |
| Second active business profile create | Throws `SettingsError.activeBusinessProfileExists`; active count remains <= 1 | `SettingsServiceTests.testCreateSecondActiveBusinessProfileFails` | PASS |
| Activating an inactive second profile | Throws `SettingsError.activeBusinessProfileExists`; active count remains <= 1 | `SettingsServiceTests.testActivateSecondBusinessProfileFails` | PASS |
| Migration on existing DB with multiple active rows | Deactivates all but the first active row, then creates a filtered unique index | `registerMigration078SingleActiveBusinessProfile` | PASS |

## Code Evidence

- `createBusinessProfile` checks for another active profile before insert: `core/Sources/WiredPartCore/Services/SettingsService.swift:350`
- `updateBusinessProfile` checks for another active profile before activation/update: `core/Sources/WiredPartCore/Services/SettingsService.swift:362`
- `ensureNoOtherActiveBusinessProfile` throws `SettingsError.activeBusinessProfileExists` when another active row exists: `core/Sources/WiredPartCore/Services/SettingsService.swift:808`
- Migration 078 is registered in the migration chain: `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift:117`
- Migration 078 normalizes old data and creates `idx_business_profiles_single_active` where `is_active = 1`: `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift:4967`
- Regression test for second active create: `core/Tests/WiredPartCoreTests/SettingsServiceTests.swift:326`
- Regression test for second active activation: `core/Tests/WiredPartCoreTests/SettingsServiceTests.swift:346`

## Residual Risk

- The evidence is database/service-level. It proves the invariant that prevents multiple active profiles on a local computer database. It does not exercise a full iOS onboarding UI flow, but the UI writes through `SettingsService.createBusinessProfile`, so the invariant is enforced beneath the UI.
