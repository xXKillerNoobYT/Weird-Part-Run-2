---
source: dev-improvement-scanner (2026-04-04)
severity: Medium
category: Security — PII Storage
status: open
github_issue: PENDING (gh not available, file manually)
---

# DIS-005: Company PII Stored in UserDefaults During Setup Wizard

## Problem
`CompanySetupWizard` stores company name, address, phone, and email in `UserDefaults` as wizard state (lines 715-720). `UserDefaults` is stored in an unencrypted plist — readable on unencrypted backups or jailbroken devices.

## File
`Auth/CompanySetupWizard.swift:715-720`

## Two Questions for Owner
1. Are the UserDefaults keys (`companySetup_name`, etc.) deleted after the wizard completes successfully?
2. Should we migrate this wizard state to the SQLite DB (which benefits from iOS Data Protection)?

## Suggested Fix
Verify that `UserDefaults.standard.removeObject(forKey:)` is called for all 4 keys when the wizard completes. If wizard state needs to persist across app restarts, store it in a `company_setup_draft` table in SQLite instead.

## Verification
1. Run the setup wizard
2. Complete it successfully
3. Check `UserDefaults` — confirm `companySetup_name` etc. are no longer present
