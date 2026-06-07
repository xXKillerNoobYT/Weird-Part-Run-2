# Copilot Coding Agent — Project Conventions

> This file is read automatically by the GitHub Copilot Coding Agent (`copilot-swe-agent`) for every assigned issue. It mirrors the most-referenced sections of `CLAUDE.md` so delegated issues need only acceptance-criteria comments, not full context re-statements.

---

## 1. Build & Test Commands

Before marking any PR ready for review, the following must pass without errors:

```bash
cd core && swift build && swift test
```

- All existing tests must continue to pass.
- Do not add a new failing test and leave it skipped.
- If `swift build` fails, fix the compile error before pushing.

### Local Mac Actions Runner For PR CI

For `xXKillerNoobYT/Weird-Part-Run-2`, PR build/test/QA work and repo-owned Actions automation should use the local self-hosted Mac runner before treating GitHub-hosted Actions billing, `macos-latest`, `ubuntu-latest`, or cloud queue capacity as a blocker.

Known runner:

- Directory: `/Users/IA/actions-runner/Weird-Part-Run-2`
- Service: `IA-Mac-WPR2`
- Labels: `self-hosted`, `macOS`, `ARM64`, `xcode`, `ios`, `local-mac`

Before marking CI blocked on cloud runner capacity, check:

```bash
gh api repos/xXKillerNoobYT/Weird-Part-Run-2/actions/runners --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'
gh run list -R xXKillerNoobYT/Weird-Part-Run-2 --limit 10
rg -n "runs-on:" .github/workflows
```

Use `runs-on: [self-hosted, macOS, ARM64, xcode, ios, local-mac]` for jobs that need macOS, iOS, Swift, or Xcode, required PR gates, and repo-owned automation jobs. If the runner is offline or missing labels, record that exact evidence in the PR/issue comment and name the owner/action needed to restore the runner.

---

## 2. Schema Is Canonical

The single source of truth for the database schema is:

```
core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift
```

- **Never assume a column exists.** Read the migration file first.
- All schema changes must be expressed as a numbered migration (e.g. `migration076`). Do **not** alter earlier migrations.
- New migrations must be additive only — never drop or rename columns in existing migrations.
- New agent-authored migrations are **out of scope** unless the issue explicitly requests one (see §8 — Agent Boundaries).

---

## 3. No Hardcoded `userId: 1`

User identity must always flow from the caller — never be hard-coded.

```swift
// ❌ Wrong
let userId = 1

// ✅ Correct
func doSomething(userId: Int64) { ... }
```

Any new function that touches user-owned data must accept `userId` as a parameter. Existing hard-coded `userId: 1` (or `userId: 0`) usages are tracked in `docs/DevTODO/` — do not introduce new ones.

---

## 4. Error Handling — `isTableNotFoundError` Guard

Before swallowing a GRDB `DatabaseError` (or any catch that could silently discard a table-missing error), check whether it is a table-not-found error first:

```swift
} catch {
    if !error.isTableNotFoundError {
        // only log / rethrow real errors
        throw error
    }
    // table doesn't exist yet — safe to return empty/nil
}
```

Do **not** use bare `catch { }` or `catch { return [] }` without this guard.

---

## 5. Soft-Delete Defense in Depth

Every query against a soft-deletable table **must** apply all applicable filters:

| Column present | Required filter |
|---|---|
| `is_active` | `is_active = 1` |
| `deleted_at` | `deleted_at IS NULL` |
| `status` (vehicles, assets) | `status IN ('active', ...)` — check the migration for valid values |

Both `is_active = 1` AND `deleted_at IS NULL` are required when the table has both columns. Omitting either is a bug.

```swift
// ✅ Correct example
try db.fetch(
    Vehicle
        .filter(Column("is_active") == 1)
        .filter(Column("deleted_at") == nil)
        .filter([Column("status") == "active"])
)
```

---

## 6. Branch & PR Conventions

| Rule | Value |
|---|---|
| Base branch | `main` |
| Branch name | `copilot/<short-slug>` or `fix/<short-slug>` |
| PR title format | `[Area][Type] Short description` |
| Issue reference | `Closes #N` must appear in the PR body |
| Draft PRs | Open as draft until `swift build && swift test` passes |

**PR title area prefixes:** `[Parts]`, `[Orders]`, `[Jobs]`, `[Warehouse]`, `[Scheduling]`, `[People]`, `[Fleet]`, `[Tools]`, `[Reports]`, `[Auth]`, `[Sync]`, `[Infra]`, `[AI]`.

**PR title type suffixes:** `[Bug]`, `[Feature]`, `[UX]`, `[Refactor]`, `[T1]`, `[T2]`, `[T3]`.

---

## 7. Issue Title Tier Tags

All issues use tier tags to signal priority/complexity:

| Tag | Meaning |
|---|---|
| `[T1]` | Critical — data loss, crash, security, broken core flow |
| `[T2]` | Important — process improvement, significant UX, performance |
| `[T3]` | Nice-to-have — polish, minor convenience, small cleanup |

When filing a follow-up issue from PR work, use the same `[Area][Type]` + tier format:

```
[Orders][Bug][T1] PO receiver FK not validated on save
```

---

## 8. Agent Boundaries

The following actions require explicit human approval and must **not** be performed autonomously:

1. **New schema migrations** — do not write `migration07X` blocks unless the issue title and body explicitly request a schema change.
2. **Security-sensitive merges** — changes to `AuthService`, `FieldEncryption`, `CipherKeyManager`, `SyncCrypto`, or any Keychain access path must be flagged for manual review before merging.
3. **Bypassing tests** — do not mark a PR ready, skip tests, or suppress compiler warnings with `@_silgen_name` / `@discardableResult` to make a build pass.
4. **Touching unrelated files** — keep changes scoped to the area described in the issue. If a fix requires touching a second area, call it out in the PR body and ask before proceeding.
5. **Deleting or archiving plans** — `docs/plans/` files are living documents. Do not delete or significantly truncate them.

---

## Quick Reference

```
Repo layout (active):
  core/Sources/WiredPartCore/          Swift core — services, models, DB
  core/Sources/WiredPartCore/Database/ Migrations (canonical schema)
  Weird Parts IOS/                     SwiftUI app (87 pages)
  docs/plans/                          Living plan documents
  docs/DevTODO/                        Tracked tech-debt items

Build:    cd core && swift build
Test:     cd core && swift test
Schema:   core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift
```
