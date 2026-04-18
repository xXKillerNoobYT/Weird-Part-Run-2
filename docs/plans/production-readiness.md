# Production-Readiness Scanner

> **Part of:** AUTO GO unified loop (see `auto-go-unified-loop.md`)
> **SKILL.md:** `~/.claude/scheduled-tasks/production-readiness/SKILL.md`

## What This Does (Plain English)

Walks the deployment checklist and verifies every task the WiredPart beta needs to ship as a production product. Catches stale signing configs, outdated version numbers, missing App Store metadata, incomplete deployment-plan items.

## Why We Need This

The project has a `docs/plans/deployment-master-plan.md` with 23 tasks, 19 done, 5 remaining (Mac + physical-device gated). Nothing regularly checks "are we still on track to ship?" — this task does.

## Current State

- `docs/plans/deployment-master-plan.md` exists with 23 tasks. 5 remaining.
- Project uses Tauri 2.0 for macOS/iOS and Windows builds.
- iOS bundle ID, version number, signing cert known but not regularly verified.
- No automated check for App Store metadata (screenshots, description, privacy labels).

## Proposed Changes

### SKILL.md content

Scanner phases:

**Phase A — Deployment plan alignment**
- Read `docs/plans/deployment-master-plan.md`.
- For each task marked incomplete: verify the reason (needs Mac, needs device, needs Apple Developer account).
- If a task should be doable in the current environment but hasn't been done, log to `docs/production-readiness-tracker.md` and surface in next `dev-pipeline-manager` run.

**Phase B — Signing and identity verification**
- Check `Weird Parts IOS/Weird Parts IOS.xcodeproj/project.pbxproj` for:
  - `PRODUCT_BUNDLE_IDENTIFIER` matches expected value.
  - `CURRENT_PROJECT_VERSION` and `MARKETING_VERSION` present and synced.
  - `DEVELOPMENT_TEAM` set (required for archive).
- Check `src-tauri/tauri.conf.json` for:
  - `productName`, `version`, `identifier` present.
  - `bundle.macOS.signingIdentity` and `bundle.windows.certificateThumbprint` present on release config.

**Phase C — App Store metadata readiness**
- `docs/app-store/screenshots/` — count required screenshots (iPhone 6.7", 6.1", iPad 12.9"). Log gaps.
- `docs/app-store/description.md` — verify exists, > 100 chars.
- `docs/app-store/privacy-labels.md` — verify exists, lists data collected.
- If any missing: file a DevTODO item with what's needed.

**Phase D — Build verification**
- `cd core && swift build` must succeed.
- `npm run build` (in project root, if applicable) must succeed.
- If Tauri: `npm run tauri build` in dry-run mode succeeds.
- Zero compile warnings on release config.

**Phase E — File findings**
- Each failing check → GitHub issue with label `production-readiness` (check for duplicates first).
- Each passing check → logged to `docs/production-readiness-tracker.md` with timestamp.
- Heartbeat logs "production-readiness: N gaps, M fixes applied".

## Files to Create

- `~/.claude/scheduled-tasks/production-readiness/SKILL.md`
- `docs/production-readiness-tracker.md` (seeded on first run)
- `docs/app-store/` directory (created if missing, with stub files for screenshots/description/privacy-labels)

## Test Plan

1. First run: creates tracker and app-store stub files if missing, reports baseline gaps.
2. Subsequent runs: only reports new gaps or resolved items.
3. Idempotent: running twice in an hour skips second run (checks tracker for last-run timestamp).

## User Roles Affected

- **Owner:** sees a concrete "5 things left before we ship" list updated regularly.
- **Developer:** gets specific Xcode prompts for signing/version-bumping fixes.

## Security Considerations

- Never logs the actual signing cert or private key. Only presence/absence.
- Team ID and bundle ID are fine to log (they're in public `Info.plist`).

## Apple HIG Notes

N/A (this is a meta-check, not a UI change).
