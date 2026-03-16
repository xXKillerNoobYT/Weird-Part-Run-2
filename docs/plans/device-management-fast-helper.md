# Device Management Fast Helper (Setup Guide in-app)

> **Date:** 2026-03-07
> **Status:** ✅ Complete
> **Scope:** Add a fast, clear, device-specific setup helper inside Settings → Device Management
> **Primary source:** `docs/plans/sideloading-guide.md`

---

## Goal

Provide an in-app helper that quickly guides staff through install + pairing for the device they have, without needing to read the full long-form deployment docs first.

Location requirement from request:
- **Accessible from Device Manager in Settings**

Implemented location:
- **Settings → Device Management → Setup Helper tab**

---

## Plan

1. Reuse existing plan/instructions from `sideloading-guide.md`.
2. Add a new tab in Device Management called **Setup Helper**.
3. Provide fast platform chooser:
   - iPhone
   - iPad
   - Android
4. For each platform, show concise sections:
   - Before you start
   - Install + pair
   - Update later
   - Quick troubleshooting
5. Ensure mobile-friendly UI:
   - touch targets >= 44px
   - responsive grid and wrapped content
6. Validate frontend compiles/builds.

---

## Implementation

### File updated
- `frontend/src/features/settings/pages/DeviceManagementPage.tsx`

### What was added
- New tab ID: `setup`
- New tab in tab bar: **Setup Helper**
- New platform-specific helper data model (`SETUP_GUIDES`)
- New components:
  - `SetupHelperTab`
  - `HelperSection`
- Included concise guided flows for:
  - **iPhone** (Sideloadly + AltServer)
  - **iPad** (same as iPhone with tablet notes)
  - **Android** (APK sideload)
- Added quick troubleshooting bullets per platform.

### UX behavior
- User opens **Settings → Device Management**.
- Clicks **Setup Helper** tab.
- Selects platform (iPhone / iPad / Android).
- Follows numbered install/pairing/update checklist.

---

## Notes

- This helper is intentionally short-form and operational.
- Long-form reference remains in `docs/plans/sideloading-guide.md`.
- The helper focuses on first-time install and update flow with minimum friction for field rollout.
