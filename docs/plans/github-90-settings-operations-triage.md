# GitHub #90 Settings Operations Triage

Date: 2026-05-13
Owner: BugHunter
Source: GitHub #90, `[Settings] Operations - Break/Lunch Policy, Tool Policies, Pre-Trip, Dispatch`

## Scope

GitHub #90 is a broad program-review issue covering Operations settings:

- Break/Lunch Policy
- Tool Policies
- Pre-Trip Checklist Config
- Dispatch Preferences
- Company settings sync rules
- Help buttons

This triage converts the broad checklist into implementation-ready slices and records what is already shipped.

## Shipped

- `IOSBreakSettingsPage` exists with a 4-section policy UI, bonus controls, auto-fill settings, save button, help sheet, dirty-state dismissal protection, and state selector.
- `IOSToolPoliciesPage` exists with checkout duration, overdue threshold, condition checks, maintenance interval, trade timeout, help sheet, and dirty-state dismissal protection.
- `IOSPreTripChecklistPage` exists with default sections, custom sections/items, vehicle-type selection, critical item flag, help sheet, and dirty-state dismissal protection.
- `IOSDispatchPreferencesPage` exists with AI suggestions, AI learning, confidence scores, flex self-assign, manager approval, pipeline targets, scheduling preferences, help sheet, and dirty-state dismissal protection.
- `SyncScopeIndicator` classifies break/lunch, tool policies, pre-trip checklists, and dispatch preferences as company-wide settings.

## Gaps And Bugs

### 1. Break policy saves are not idempotent

`BreakService.savePolicy(...)` always inserts a new `break_policies` row. `IOSBreakSettingsPage.loadCompanyPolicies()` then reads the first matching `company_extra_paid` and `company_extra_offered` policies. Repeated saves can accumulate stale rows and reload old values after a save.

Evidence:

- `core/Sources/WiredPartCore/Services/BreakService.swift`: `savePolicy` inserts at lines 59-68.
- `Weird Parts IOS/Weird Parts IOS/Features/Settings/IOSBreakSettingsPage.swift`: `loadCompanyPolicies()` reads the first matching company policy at lines 491-504.

Impact: admins can believe they saved a company break policy, but a later load may show an older policy row.

### 2. State labor-law presets are incomplete

The UI lists 50 states, but not DC. The database seeds only Wyoming, only `state_required_paid`, and only an 8-hour work-day policy.

Evidence:

- `IOSBreakSettingsPage.swift`: `stateOptions` has 50 state codes and no `DC` at lines 54-60.
- `AppDatabase+Migrations.swift`: migration 042 seeds only `WY` at lines 509-513.
- `IOSBreakSettingsPage.swift`: the UI has no separate 8-hour vs 10-hour editor; it shows whichever single policy row matches `selectedState`.

Impact: the #90 requirement for 50 states + DC and separate 8-hour/10-hour values is not met.

### 3. Pre-trip checklist config is not the requested configurable inspection template system

The page stores a JSON blob in the `settings` table, while migration 053 already created normalized `inspection_templates` with section, item, critical flag, and sort order. The UI allows custom sections/items but does not provide drag reorder, expandable/collapsible sections, vehicle/trailer tabs, or a per-item "required" toggle.

Evidence:

- `IOSPreTripChecklistPage.swift`: JSON setting storage at lines 355-382.
- `AppDatabase+Migrations.swift`: normalized `inspection_templates` table with `sort_order` exists at lines 4383-4397.
- `IOSPreTripChecklistPage.swift`: no `onMove`/reorder path; item flag is `isCritical`, not the requested required toggle.

Impact: checklist settings may drift from the actual inspection template tables, and admins cannot reorder or configure requiredness as specified.

### 4. Tool policy settings are saved but not wired into tool workflows

Status: FIXED by WEI-1103 / GitHub #438 on 2026-05-13.

`IOSToolPoliciesPage` persists key-value settings, but `ToolsService` has no reads of the `tool_policy_*` keys. Tool workflows already have lost/stolen reporting and pending verification support, but #90's policy controls for lost/stolen rules and edit-permission behavior are not exposed in the policy page or enforced from saved settings.

Evidence:

- `IOSToolPoliciesPage.swift`: saves `tool_policy_*` keys at lines 228-241.
- `ToolsService.swift`: no references to those `tool_policy_*` keys.
- `ToolsService.swift`: pending verification and lost/stolen flows exist, but they are not governed by policy settings.

Impact: admins can change tool policies in Settings without those choices affecting checkout, return, maintenance, trade, lost/stolen, or edit verification behavior.

Resolution:

- `SettingsService.ToolPolicySettings` now provides typed defaults, typed reads, and typed updates for every `tool_policy_*` key.
- `ToolsService` reads saved policies inside checkout, return, maintenance threshold, trade, lost/stolen, and edit-verification workflows.
- `IOSToolPoliciesPage` exposes the missing lost/stolen report controls and edit-verification behavior picker.
- Focused validation: `swift test --package-path core --filter 'SettingsServiceTests|ToolsServiceTests'` passed with 178 tests.

### 5. Dispatch preferences are saved but not wired into dispatch behavior

`IOSDispatchPreferencesPage` persists dispatch settings, but `AIDispatchService` always generates three suggestions and always exposes learning APIs independently of the saved toggles. The flex self-assign setting is also not visible in the service searches used during this triage.

Evidence:

- `IOSDispatchPreferencesPage.swift`: saves `dispatch_*` keys at lines 243-256.
- `AIDispatchService.swift`: `generateSuggestions(date:)` unconditionally returns up to three ranked options at lines 94-153.
- Repository search found no service-side reads of `dispatch_ai_suggestions_enabled`, `dispatch_ai_learning_enabled`, or `dispatch_flex_self_assign_enabled`.

Impact: dispatch settings can be saved but ignored by the operational workflows they are supposed to govern.

## Recommended Executable Slices

1. Fix break policy persistence and tests.
2. Add complete break/lunch state preset data for 50 states + DC with 8-hour and 10-hour policy rows.
3. Move pre-trip checklist settings onto `inspection_templates`, with reorder and required/critical semantics clarified.
4. ~~Wire tool policy settings into Tools workflows and expose missing lost/stolen/edit-permission policy controls.~~ Fixed by WEI-1103 / GitHub #438.
5. Wire dispatch preference settings into AI dispatch, flex pool, and pipeline behavior.

## Closeout Rule

GitHub #90 should remain open until the child implementation slices are complete or explicitly accepted as out of scope. The broad issue can then be closed with links to the concrete child issues and verification commands.
