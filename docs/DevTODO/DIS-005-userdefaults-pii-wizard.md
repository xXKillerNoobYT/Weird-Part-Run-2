---
source: dev-improvement-scanner (2026-04-04)
severity: Medium
category: Security — PII Storage
status: DONE — Migration 072 adds company_setup_draft table. SettingsService: loadSetupDraft/saveSetupDraft/deleteSetupDraft implemented. CompanySetupWizard fully migrated from UserDefaults to SQLite draft in commits a7ed218 + 5135ee2. Cleanup called on completion.
github_issue: PENDING (gh not available, file manually)
---

# DIS-005: Company PII Stored in UserDefaults During Setup Wizard

## Problem
`CompanySetupWizard` stores company name, address, phone, and email in `UserDefaults` as wizard state (lines 715-720). `UserDefaults` is stored in an unencrypted plist — readable on unencrypted backups or jailbroken devices.

## File
`Auth/CompanySetupWizard.swift:715-720`

## Owner Answers (2026-04-04)

**Q1: Are the UserDefaults keys (`companySetup_name`, etc.) deleted after the wizard completes?**
> No — they are NOT deleted. Confirmed by code audit: no `removeObject` calls exist for any `companySetup_` keys. All 8 keys (including 4 PII keys) persist in the unencrypted plist indefinitely after wizard completion. This IS a security issue.

**Q2: Option A (removeObject on completion) or Option B (migrate to SQLite draft table)?**
> **Option B** — migrate wizard draft state to a `company_setup_draft` SQLite table. SQLite benefits from iOS Data Protection (encryption at rest). Delete the draft row after wizard completion. This eliminates PII from the unencrypted UserDefaults plist entirely.

## Implementation Plan

1. Add `company_setup_draft` table to AppDatabase+Migrations.swift (new migration)
2. Replace all `UserDefaults.standard.set(_, forKey: "companySetup_*")` writes in `CompanySetupWizard.swift` with SQLite inserts/updates to `company_setup_draft`
3. Replace all `UserDefaults.standard.string(forKey: "companySetup_*")` reads with SQLite reads
4. On wizard completion (when data is saved to `company_profile`), delete the `company_setup_draft` row
5. On wizard cancel/dismiss (if user starts but doesn't finish), leave draft row (allows resuming later)

## Verification
1. Run the setup wizard
2. Confirm no `companySetup_*` keys appear in UserDefaults during or after wizard
3. Confirm wizard state persists to SQLite correctly across app restarts mid-wizard
4. Confirm draft row is deleted after wizard completes
