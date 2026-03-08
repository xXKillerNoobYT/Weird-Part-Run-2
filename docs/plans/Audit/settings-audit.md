# Settings Audit

> **Date:** 2026-03-06
> **Status:** ✅ Updated (2026-03-07) — 7/8 tabs functional. AiConfigPage (LM Studio config + feature toggles) and DeviceManagementPage (devices/history/conflicts tabs using live sync API) fully implemented. 1 remaining stub: SyncPage (future Bluetooth mesh phase). AboutPage added via M4 gap closure (GAP-043).
> **Scope:** Full audit of the Settings module — theme, app config, company profiles, staging zones, notifications, sync, AI, devices

---

## Table of Contents

1. [Backend Inventory](#1-backend-inventory)
2. [Frontend Inventory](#2-frontend-inventory)
3. [Feature Completeness](#3-feature-completeness)
4. [Cross-References](#4-cross-references)
5. [Issues & TODOs](#5-issues--todos)

---

## 1. Backend Inventory

### Router: `backend/app/routers/app_settings.py` (~346 lines)

Mounted in `main.py` as `app.routers.app_settings`.

| # | Method | Path | Auth | Description | Status |
|---|--------|------|------|-------------|--------|
| 1 | `GET` | `/api/settings/theme` | any user | Get theme settings (mode, color, font) | ✅ Functional |
| 2 | `PUT` | `/api/settings/theme` | any user | Update theme settings | ✅ Functional |
| 3 | `GET` | `/api/settings/company-profiles` | `manage_settings` | List all company profiles | ✅ Functional |
| 4 | `GET` | `/api/settings/company-profiles/{id}` | `manage_settings` | Get single company profile | ✅ Functional |
| 5 | `POST` | `/api/settings/company-profiles` | `manage_settings` | Create company profile | ✅ Functional |
| 6 | `PUT` | `/api/settings/company-profiles/{id}` | `manage_settings` | Update company profile | ✅ Functional |
| 7 | `DELETE` | `/api/settings/company-profiles/{id}` | `manage_settings` | Delete company profile | ✅ Functional |
| 8 | `GET` | `/api/settings/staging-zones` | `manage_settings` | List staging zones | ✅ Functional |
| 9 | `POST` | `/api/settings/staging-zones` | `manage_settings` | Create staging zone | ✅ Functional |
| 10 | `PUT` | `/api/settings/staging-zones/{id}` | `manage_settings` | Update staging zone | ✅ Functional |
| 11 | `GET` | `/api/settings/` | `manage_settings` | Get all settings grouped by category | ✅ Functional |
| 12 | `PUT` | `/api/settings/bulk` | `manage_settings` | Bulk update multiple settings | ✅ Functional |
| 13 | `GET` | `/api/settings/{key}` | `manage_settings` | Get single setting by key | ✅ Functional |
| 14 | `PUT` | `/api/settings/{key}` | `manage_settings` | Update single setting by key | ✅ Functional |

**Total endpoints: 14**

**⚠️ Route ordering note:** Company profiles and staging zones routes are registered BEFORE the `/{key}` catch-all. This is critical — otherwise FastAPI would match "company-profiles" as a key parameter. The code has explicit comments about this.

### Repository: `backend/app/repositories/settings_repo.py` (~105 lines)

Extends `BaseRepo`. Methods:

| Method | Description |
|--------|-------------|
| `get_by_key(key)` | Get single setting value, JSON-decoded |
| `set_value(key, value, category)` | Upsert a setting (INSERT ... ON CONFLICT DO UPDATE) |
| `get_by_category(category)` | Get all settings in a category as dict |
| `get_all_settings()` | Get all settings grouped by category |
| `bulk_update(updates)` | Update multiple settings at once |

Settings are stored as JSON key-value pairs in the `settings` table with categories: `general`, `theme`, `sync`, `ai`, `procurement`, `device`.

### Models: `backend/app/models/settings.py` (~35 lines)

| Model | Fields |
|-------|--------|
| `SettingItem` | `key`, `value` (JSON string), `category` |
| `SettingUpdate` | `value` (JSON string) |
| `ThemeSettings` | `theme_mode`, `primary_color`, `font_family` |
| `SettingsBulkUpdate` | `settings` (dict of key → JSON value) |

### Additional Dependencies

- `StagingZoneRepo` — manages staging zones (imported from orders domain)
- `CompanyProfileCreate` / `CompanyProfileUpdate` — Pydantic models from `models/company.py`

### API Client: `frontend/src/api/settings.ts` (~105 lines)

| Function | Endpoint | Returns |
|----------|----------|---------|
| `getTheme()` | `GET /settings/theme` | `ThemeSettings` |
| `updateTheme(theme)` | `PUT /settings/theme` | `ThemeSettings` |
| `getAllSettings()` | `GET /settings` | `Record<string, unknown>` |
| `getWarrantyLengthDays()` | `GET /settings/warranty_length_days` | `number` |
| `updateWarrantyLengthDays(days)` | `PUT /settings/warranty_length_days` | `void` |
| `listCompanyProfiles()` | `GET /settings/company-profiles` | `CompanyProfile[]` |
| `getCompanyProfile(id)` | `GET /settings/company-profiles/{id}` | `CompanyProfile` |
| `createCompanyProfile(profile)` | `POST /settings/company-profiles` | `{ id: number }` |
| `updateCompanyProfile(id, profile)` | `PUT /settings/company-profiles/{id}` | `StatusMessage` |
| `deleteCompanyProfile(id)` | `DELETE /settings/company-profiles/{id}` | `StatusMessage` |

**Note:** Staging zone API calls are NOT in `settings.ts` — they may be in the warehouse/orders API client.

---

## 2. Frontend Inventory

### Directory: `frontend/src/features/settings/`

| File | Lines | Type | Status |
|------|-------|------|--------|
| `pages/ThemesPage.tsx` | ~120 | Theme selection page | ✅ Functional |
| `pages/AppConfigPage.tsx` | ~105 | App configuration (warranty settings) | ✅ Functional |
| `pages/CompanyProfilePage.tsx` | ~411 | Company profile CRUD | ✅ Functional |
| `pages/NotificationPrefsPage.tsx` | ~230 | Notification preferences | ✅ Functional |
| `pages/ClockOutQuestionsPage.tsx` | ~321 | Clock-out question management | ✅ Functional (but lives in Office nav) |
| `pages/SyncPage.tsx` | ~18 | Sync settings | ❌ Stub |
| `pages/AiConfigPage.tsx` | ~18 | AI configuration | ❌ Stub |
| `pages/DeviceManagementPage.tsx` | ~18 | Device management | ❌ Stub |

**Total: 8 files, ~1,241 lines**

### Supporting: `frontend/src/stores/theme-store.ts` (~95 lines)

Zustand store managing theme state:
- `mode` — "light" | "dark" | "system"
- `isDark` — resolved boolean
- `primaryColor` — hex color (default #3B82F6)
- `fontFamily` — font name (default Inter)
- `initialize(settings?)` — loads from backend or localStorage
- `setMode(mode)` — saves to localStorage + applies DOM class
- `applyTheme()` — toggles `dark` class on `<html>`
- Listens for OS `prefers-color-scheme` changes in system mode

### Navigation Config (`frontend/src/lib/navigation.ts`)

```typescript
{
  id: 'settings',
  label: 'Settings',
  icon: 'Settings',
  path: '/settings',
  tabs: [
    { id: 'app-config',       label: 'App Config',        path: '/settings/app-config',       permission: 'manage_settings' },
    { id: 'company-profile',  label: 'Company',           path: '/settings/company-profile',  permission: 'manage_settings' },
    { id: 'themes',           label: 'Themes',            path: '/settings/themes' },
    { id: 'notifications',    label: 'Notifications',     path: '/settings/notifications' },
    { id: 'sync',             label: 'Sync',              path: '/settings/sync',             permission: 'manage_settings' },
    { id: 'ai-config',        label: 'AI Config',         path: '/settings/ai-config',        permission: 'manage_settings' },
    { id: 'devices',          label: 'Device Management', path: '/settings/devices',          permission: 'manage_devices' },
  ],
}
```

No top-level permission — visible to all authenticated users.
Admin-only tabs gated by: `manage_settings`, `manage_devices`.
Open tabs (no permission): Themes, Notifications.

### Route Registration (`App.tsx`)

```
/settings                → Redirect to /settings/themes
/settings/app-config     → AppConfigPage
/settings/company-profile → CompanyProfilePage
/settings/themes         → ThemesPage
/settings/notifications  → NotificationPrefsPage
/settings/questions      → Redirect to /office/clock-out-questions
/settings/sync           → SyncPage
/settings/ai-config      → AiConfigPage
/settings/devices        → DeviceManagementPage
```

**Note:** ClockOutQuestionsPage is registered in settings features directory but is routed under `/office/clock-out-questions` (in the Office module). The `/settings/questions` path redirects there.

### Page Details

#### ThemesPage (✅ Functional — ~120 lines)
- Three radio-style cards: Light, Dark, System
- Each shows icon, label, description, active indicator
- Uses `useThemeStore` for state management
- Shows "current resolved theme" indicator
- Quick-toggle buttons at bottom

#### AppConfigPage (✅ Functional — ~105 lines)
- Currently only has: **Warranty Settings**
  - Default warranty length in days (numeric input)
  - Quick-set preset buttons: 90 days, 6 months, 1 year, 2 years
  - Save button with success feedback
  - Reads/writes via `getWarrantyLengthDays()` / `updateWarrantyLengthDays()`
- Docstring notes future sections: company info, default units, tax rates, feature flags

#### CompanyProfilePage (✅ Functional — ~411 lines)
- Full CRUD for company profiles (used on PO PDFs)
- List view with cards showing: name, branch, address, phone, email, website, primary badge
- Inline edit form with all fields
- Add new profile form
- Primary profile designation (auto-unsets previous primary)
- Delete with confirmation dialog

#### NotificationPrefsPage (✅ Functional — ~303 lines)
- Toggle switches for 13 notification types across 4 categories:
  - **Orders** (7): JPO submitted/approved/rejected, PO submitted/acknowledged/shipped/received
  - **Inventory** (2): Low stock alert, Reorder suggestions
  - **Returns** (2): Return submitted/approved
  - **Jobs** (1): Job status changes
- **Opt-out model**: All notifications default to ON — users toggle OFF what they don't need
- **Permission-gated locking**: If user's hat doesn't grant the required permission for a notification type, the toggle is locked off with a Lock icon and amber "Requires X permission" text
- **Color-coded toggles**: Green (`bg-green-500`) for enabled, Red (`bg-red-400`) for disabled — provides instant visual clarity
- **Color-coded icons**: Green Bell for enabled, Red BellOff for disabled, gray Lock for permission-locked
- Per-user preferences (stored in `notification_preferences` table)
- Save button with confirmation feedback
- **E2E verified (2026-03-07)**: Responsive at mobile/tablet/desktop, toggle interaction confirmed

#### ClockOutQuestionsPage (✅ Functional — ~321 lines)
- **Lives in settings directory but navigated from Office module**
- Admin page for managing global clock-out questions
- Add/edit/deactivate questions
- Question types: Text, Yes/No, Photo
- Required/optional toggle
- Sort order with up/down arrow buttons
- Deactivated questions section (collapsed)

#### SyncPage (❌ Stub — ~18 lines)
- Shows `<EmptyState>` with "Coming soon" message
- Will handle: sync status, conflict resolution, offline storage

#### AiConfigPage (❌ Stub — ~18 lines)
- Shows `<EmptyState>` with "Coming soon" message
- Will handle: AI model selection, prompt tuning, automation rules

#### DeviceManagementPage (❌ Stub — ~18 lines)
- Shows `<EmptyState>` with "Coming soon" message
- Will handle: registered devices, session management, remote wipe

---

## 3. Feature Completeness

| Tab/Feature | Frontend Status | Backend Status | Notes |
|-------------|----------------|----------------|-------|
| App Config (Warranty) | ✅ Functional | ✅ Functional | Only warranty length implemented; placeholder for more |
| Company Profiles | ✅ Functional | ✅ Functional | Full CRUD with primary designation |
| Themes | ✅ Functional | ✅ Functional | Light/Dark/System, persists to backend + localStorage |
| Notifications | ✅ Functional | ✅ Functional | 13 types across 4 categories |
| Clock-Out Questions | ✅ Functional | ✅ Functional | In settings dir but navigated from Office |
| Sync | ❌ Stub | ❌ No backend | Planned for future (offline-first mesh networking) |
| AI Config | ❌ Stub | ❌ No backend | Planned for future (LM Studio local LLM) |
| Device Management | ❌ Stub | ❌ No backend | Planned for future (device policies, remote wipe) |
| Staging Zones | ✅ Backend only | ✅ Functional | Backend in settings router, no dedicated settings UI (managed elsewhere) |

**Functional: 5/8 tabs (62.5%)**
**Stubs: 3/8 tabs (37.5%)**

The 3 stubs (Sync, AI Config, Devices) are all Future Phase features — not part of the current development roadmap.

---

## 4. Cross-References

### Backend Dependencies

| Settings Feature | External Service/Repo | Table(s) |
|-----------------|----------------------|-----------|
| Theme settings | `SettingsRepo` | `settings` (category: theme) |
| General settings | `SettingsRepo` | `settings` (all categories) |
| Company profiles | Direct SQL | `company_profiles` |
| Staging zones | `StagingZoneRepo` | `staging_zones` |
| Notifications | `notifications` router | `notification_preferences` |
| Clock-out questions | `jobs` router | `clock_out_questions` |

### Frontend Dependencies

| Settings Feature | API Client | Store | Shared Components |
|-----------------|------------|-------|-------------------|
| Themes | `api/settings.ts` | `stores/theme-store.ts` | `Card`, `Button` |
| App Config | `api/settings.ts` | — | `Card`, `CardHeader`, `Input`, `Button` |
| Company Profiles | `api/settings.ts` | — | `EmptyState` |
| Notifications | `api/notifications.ts` | — | — (custom toggle switches) |
| Clock-Out Questions | `api/jobs.ts` | — | `PageSpinner`, `Button`, `EmptyState` |

### Cross-Module Connections

- **Company Profiles** → Used by PO PDF generation (orders module)
- **Staging Zones** → Used by warehouse module for pull areas
- **Theme Store** → Used globally by every page (via `<html>` dark class)
- **Clock-Out Questions** → Used by jobs module during clock-out flow
- **Notification Prefs** → Control which push notifications the user receives
- **Warranty Length** → Used by jobs module for warranty end-date calculation

---

## 5. Issues & TODOs

### No TODO/FIXME Comments Found

Zero TODO, FIXME, HACK, or TEMP comments in any settings file.

### Architectural Notes

1. **AppConfigPage is sparse** — Currently only has warranty settings. The docstring mentions "Future sections: company info, default units, tax rates, feature flags." This page should be the central configuration hub but is currently skeletal.

2. **Clock-Out Questions page location** — The file lives in `features/settings/pages/` but is navigated from the Office module (`/office/clock-out-questions`). The old `/settings/questions` path redirects to Office. This is intentional (questions are an "office management" concern) but the file location is misleading.

3. **No staging zone UI in settings** — The backend has staging zone CRUD in the settings router, but there's no UI for it in the settings pages. Staging zone management may live elsewhere (warehouse config).

4. **Theme sync is local-first** — Theme is saved to both `localStorage` AND the backend. The `theme-store.ts` initializes from backend (on login) but then uses localStorage for instant application. If the backend changes (e.g., another device), it won't sync until next login/refresh.

5. **Bulk settings update is wired but unused** — The `PUT /api/settings/bulk` endpoint exists and the repo supports it, but no frontend page uses bulk update. Individual settings are updated one at a time.

### Stub Analysis

| Stub Page | Backend Exists? | Planned Phase | Complexity |
|-----------|----------------|---------------|------------|
| SyncPage | ❌ No | Sync & Bluetooth (Future) | High — offline-first mesh networking |
| AiConfigPage | ❌ No | AI Integration (Future) | Medium — LM Studio config |
| DeviceManagementPage | ❌ No | Deployment/Security (Future) | Medium — device registry, session mgmt |

All three stubs are **intentionally deferred** to future phases and are not blocking V1.0 deployment. They serve as navigation placeholders so the tab structure is ready when the features are built.

### Missing Features

- **No user profile/account page** — There's no page for the logged-in user to see/edit their own profile (name, password, etc.). This might be expected to live in Settings but doesn't exist. *(Self-service profile page added in V1.0 Hotfix Pack — `/settings/profile`)*
- ~~**No about/version page**~~ — ✅ **RESOLVED**: AboutPage added via M4 gap closure (GAP-043). Shows app version, build info, tech stack, and system status.
- **No backup/restore settings** — No mechanism to export/import settings configuration.
- **Primary color and font family** — The `ThemeSettings` model supports `primary_color` and `font_family`, but the ThemesPage UI only exposes mode (light/dark/system). Color and font customization are not surfaced.

---

## 6. E2E Test Results (2026-03-07)

### Bugs Found & Fixed

| Bug | File | Fix |
|-----|------|-----|
| BUG-001: Competing `vite.config.mjs` | `frontend/vite.config.mjs` | Deleted duplicate file (only `vite.config.ts` should exist) |
| BUG-002: Migration 033 table name mismatch | `backend/app/migrations/033_attachments_photos.sql` | Fixed CREATE TABLE name to match referenced table |
| BUG-003: EmptyState crash with forwardRef icons | `frontend/src/components/ui/EmptyState.tsx` | Added check for `$$typeof` property to handle forwardRef components |
| Notification defaults were opt-in | `NotificationPrefsPage.tsx` + `notification_repo.py` | Changed to opt-out model (ON by default), backend `is_enabled()` defaults to `True` |
| Toggle colors unclear | `NotificationPrefsPage.tsx` | Changed from brand-primary/gray to green/red for clear ON/OFF visual |
| Permission-locked notifications not visible | `NotificationPrefsPage.tsx` | Added Lock icon + amber text showing required permission |

### Responsive Validation

| Breakpoint | Status | Notes |
|------------|--------|-------|
| Mobile (375×812) | ✅ Pass | Toggle text wraps, Save button icon-only, scrollable categories |
| Tablet (768×1024) | ✅ Pass | Sidebar as overlay, full content width, all toggles visible |
| Desktop (1400×900) | ✅ Pass | Persistent sidebar, all tabs visible, green/red toggles clearly distinguishable |

### Final Regression

| Check | Result |
|-------|--------|
| TypeScript `npx tsc --noEmit` | 0 errors |
| Python AST parse (97 files) | All pass |
| pytest (119 tests) | All pass |


This page here needs to be completed properly and intelligently.

A note on the page that says devices. I want that to be a version one. This whole thing, everything in the plans, all that, that's all version one as far as I'm concerned, despite what other papers may say.