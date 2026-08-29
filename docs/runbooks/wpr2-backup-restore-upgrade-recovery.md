# WPR2 Beta Backup, Restore, and Upgrade Recovery Runbook

Status: Beta gate runbook for WEI-3989
Owner: CTO / data-safety operator
Applies to: WiredPart iOS beta builds using the shared Swift core and local SQLite database
Do not use for: Production destructive reset without manager approval

## Purpose

This runbook defines the safe operator procedure for protecting real beta data before upgrades, verifying that a backup is trustworthy, restoring onto a clean install/device/simulator, and validating that critical records survive restore plus migration.

Real beta data entry remains gated on the final WEI-3990 GO/NO-GO call. The related data-safety issues now provide backup/restore and cross-version migration evidence:

- WEI-3985: parent beta gate
- WEI-3986: automated backup/restore coverage for critical records
- WEI-3987: restored beta DB migrates forward across versions
- WEI-3988: phone/tablet user-like backup/restore smoke
- WEI-3989: this operator runbook
- WEI-3990: final real-data GO/NO-GO decision

## Backup locations and naming

There is one durable backup family in the current app/core code. Keep it separate from the bounded SQLCipher migration critical section when collecting evidence.

| Backup type | Trigger | Location | Filename pattern | Retention |
|---|---|---|---|---|
| Manual iOS backup | Settings -> Backups -> Create Backup Now | iOS app Documents directory: `WiredPart/Backups/` | `wiredpart-backup-YYYY-MM-DD-HHmmss.sqlite` plus optional matching `-wal` and `-shm` sidecars | UI says rolling local backups; current page copies files and reports stored count |
| SQLCipher migration critical section | Encryption upgrade fallback only | Canonical DB path with a temporary `.unencrypted.bak` suffix | `<database>.unencrypted.bak` plus optional sidecars | Removed after the promoted canonical DB passes a keyed SQLCipher recovery open; failed promotion restores this plaintext bundle only to the canonical path |

Expected iOS database path is obtained through `AppCore.databasePath()`: `Documents/WiredPart/wiredpart.sqlite` for normal app runs and `Documents/WiredPart/wiredpart-uitesting.sqlite` only for UI-test runs. The current app bundle identifier is `weirdtoo.Weird-Parts-IOS`; on simulator, use Xcode or `xcrun simctl get_app_container booted weirdtoo.Weird-Parts-IOS data` to locate the app data container, then inspect `Documents/WiredPart/Backups/`.

## What never to expose

Do not attach, paste, or commit any raw beta database, WAL, SHM, exported backup, `.env`, OAuth token, device key, SQLCipher key, provisioning profile, or credential file to GitHub, Paperclip, Slack, Telegram, or a PR.

Allowed evidence:

- Filename, size, timestamp, and SHA-256 hash.
- Row counts by table.
- Schema version.
- Redacted sample IDs/counts.
- Test command output with no customer/employee/job names unless explicitly approved.

## Create a backup safely

Preferred beta path: use the in-app backup action.

1. Confirm the user/device is allowed to manage settings (`manage_settings`).
2. Open Settings -> Backups.
3. Confirm the page shows the expected database size and stored backup count.
4. Tap Create Backup Now.
5. Wait for Backup Created or any visible error.
6. Record the backup filename, timestamp, size, and SHA-256 hash.
7. Copy the `.sqlite`, `.sqlite-wal`, and `.sqlite-shm` files together if WAL/SHM sidecars exist.

If using simulator/operator file access instead of the app UI:

1. Stop active writes first: close forms, wait for saves to finish, and put the app in a quiet state.
2. Prefer a SQLite online backup/checkpoint operation from app/core code where available.
3. If copying files directly, copy the main `.sqlite` and any matching `-wal` and `-shm` files as one set. Never copy only the main DB while WAL mode may contain recent committed pages.
4. Store the backup outside the repo or under ignored local scratch only. Do not place real beta data in tracked project paths.

## Verify a backup before trusting it

A backup is not trusted until all checks below pass.

1. Confirm the expected files exist:
   - Main `*.sqlite` exists and size is greater than 0.
   - If `*.sqlite-wal` or `*.sqlite-shm` existed at copy time, matching sidecars are present with the backup.
2. Record hashes:
   - `shasum -a 256 path/to/backup.sqlite`
   - repeat for WAL/SHM if present.
3. Open the backup read-only with SQLite tooling on an operator machine or in a disposable test harness.
4. Run integrity checks:
   - `PRAGMA quick_check;` must return `ok`.
   - `PRAGMA foreign_key_check;` must return no rows.
   - `PRAGMA user_version;` or the app schema-version table check must match the expected build evidence.
5. Collect critical table counts before restore:
   - parts and catalog tables
   - stock/inventory and stock movements
   - jobs, job materials, time/labor entries
   - orders, JPO, PO, receiving records
   - reports and pre-billing records
   - people/employees/customers used by those records
6. If any check fails, do not delete the source device data. Escalate immediately using the failure path below.

## Restore onto a clean install/device/simulator

Use a clean target only. Do not restore over the only copy of beta data.

1. Preserve the source device and its original backup files unchanged.
2. Install the target app build on a clean simulator/device.
3. Launch once if needed to create the app container, then quit the app completely.
4. Locate the target app database path with the same `AppCore.databasePath()`/container lookup used for backup collection.
5. Remove the target empty database files only:
   - `<db>.sqlite`
   - `<db>.sqlite-wal`
   - `<db>.sqlite-shm`
6. Copy the backup set into the target database path:
   - backup main file -> target database path
   - backup `-wal` -> target `-wal` if present
   - backup `-shm` -> target `-shm` if present
7. Launch the app on the target.
8. Let migrations run to completion. Do not force-quit during first open.
9. If the app fails to open the database or migration errors appear, preserve the target container and logs for diagnosis.

Note: the current iOS Backups page exposes backup creation but does not perform in-place restore from the UI. Treat restore as a controlled operator/developer procedure until an in-app restore flow is built and tested.

## Verify restored data after upgrade

After restore and first launch on the upgraded build, verify both technical integrity and business-critical data.

Technical checks:

1. App launches without `Failed to load database`.
2. Current schema version equals the app's latest migration target.
3. `PRAGMA quick_check;` returns `ok`.
4. `PRAGMA foreign_key_check;` returns no rows.
5. Critical table counts match the pre-restore counts unless a documented migration intentionally transforms data.
6. `_change_log` remains readable and does not show impossible timestamps/device IDs.

Business checks:

1. Parts catalog opens and sample parts are searchable.
2. Inventory/warehouse stock levels match the pre-restore count evidence.
3. Jobs list opens; at least one job detail opens with materials intact.
4. Time/labor entries still appear on labor/timesheet screens.
5. Orders/JPO/PO/receiving records open and keep line items/statuses.
6. Reports/pre-billing pages open and include the restored job/order data.
7. Settings -> Backups opens after restore and reports sane size/count data.
8. Phone and tablet smoke paths are run before real beta data entry is approved.

## What not to delete or reset during beta

Do not delete/reset any of the following until a verified backup and restore proof exists and a manager explicitly approves:

- Source device app container.
- Source device database, WAL, or SHM files.
- `Documents/WiredPart/Backups/` on the source device.
- Pre-migration `Backups/` directory.
- `.unencrypted.bak` safety file during its retention period.
- `_change_log`, device identity, auth/device reset tables, or sync metadata.
- Any Paperclip/GitHub issue evidence that records beta-gate status.

Do not use Database Reset as a substitute for restore testing. Reset is destructive and has different acceptance criteria.

## Failure and escalation path

Escalate immediately if any of these happen:

- Backup cannot be created.
- Backup exists but fails `quick_check` or `foreign_key_check`.
- Restore requires dropping WAL/SHM sidecars to open.
- App fails to open after restore.
- Migration fails, loops, or silently resets data.
- Critical row counts change without a documented migration reason.
- Phone and tablet restore results disagree.

Escalation comment must include:

- Paperclip issue identifier (WEI-3985/3986/3987/3989 as applicable).
- App build/commit under test.
- Source and target device/simulator identifiers.
- Backup filename, size, timestamp, and hashes.
- Integrity-check output.
- Critical table count diff.
- Redacted app logs/crash logs.
- Clear instruction: keep the source device untouched until reviewed.

## Evidence checklist for closing WEI-3989

This docs issue can close when:

- This runbook is linked from WEI-3989.
- This runbook is linked from `docs/RELEASE-READINESS-CHECKLIST.md`.
- Release checklist backup/restore rows are checked only after WEI-3986/WEI-3987/WEI-3988 attach end-to-end evidence.
- Any deviation found during testing is either patched into this runbook or filed as a follow-up issue.

## Current beta gate status

Runbook: documented and linked from the release checklist.
Automated critical-record backup/restore proof: complete via WEI-3986 evidence.
Cross-version migration proof: complete via WEI-3987 evidence.
Phone/tablet user-like restore smoke: complete via WEI-3988 evidence.
Real beta data entry: still requires the final WEI-3990 GO/NO-GO comment naming the tested candidate branch/SHA and this runbook revision.

## Shared-Mac backup retention (added 2026-07-31)

The CI Mac also hosts Paperclip and hermes; their backups repeatedly filled
the disk and tripped the beta-gate preflight. Standing policy:

- **Paperclip** (`~/.paperclip/instances/default/`): `database.backup.retentionDays = 7`
  in `config.json`. Known bug: backups run hourly despite `intervalMinutes: 1440`
  and retention does not enforce (Paperclip WEI-4801). If
  `data/backups` exceeds ~20 GB, thin to newest-6 plus one per day.
- **hermes** (`~/.hermes/`): keep the newest backup and newest state-snapshot;
  prune older sets. `state.db` VACUUM requires a quiet window (agents stopped)
  and free space equal to the DB size.
- **Gate preflight** threshold comes from `MINIMUM_FREE_GIB`, which is read at
  `scripts/ci/run-ios-beta-gate.sh:45` as `${MINIMUM_FREE_GIB:-30}`. The script's
  own `30` default is **inert in CI**: `.github/workflows/ios-beta-gate.yml:35`
  exports `MINIMUM_FREE_GIB: "60"`, so **60 GiB is the effective CI threshold**.
  Read the workflow for the live value rather than trusting the script default.
  The gate also reclaims stale local DerivedData before failing (see the
  preflight-cleanup change from #1537/#1536-era work); that reclaim has been
  measured freeing 8 GiB from a 52 GiB start, so a reading below the threshold
  is not by itself a blocked gate.
