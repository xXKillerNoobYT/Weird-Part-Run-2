# WEI-1985 Apple Ecosystem UX Audit Scope and Matrix

Issue: WEI-1985
Parent: WEI-1976
Created: 2026-05-23
Scope: planning/audit definition only; no app code changes.

## Purpose

WEI-1976 asks for a full audit across the Apple ecosystem surfaces currently used by Weird Parts. This document turns the merged WEI-180 artifacts into a concrete platform matrix so follow-on QA agents know which devices, orientations, feature areas, evidence packages, and exclusions count for sign-off.

This is not another broad redesign. It is a scoped verification plan for beta confidence.

## Source documents and issue links

Primary docs:

- `docs/plans/ux-audit-page-gap-list-2026-05-23.md`
- `docs/testing/wei-1944-full-app-usability-verification-matrix.md`
- `docs/testing/ai-page-context-coverage.md`
- `docs/plans/usability-hunter-plan.md`
- `docs/plans/ios-page-review-tracker.md`
- `docs/page-rebuild-tracker.md`

Existing GitHub issues that must stay linked from this audit:

- #649 — `[Docs][UX] Reconcile iOS page tracker with prompt-results-log completion evidence`
- #650 — `[AI][P1] Complete HelpContentRegistry and page-context freshness coverage`
- #651 — `[UX][P2] Triage placeholder and dead-text markers before beta`

Related UX/AI/Warehouse/Clock issues referenced by the WEI-180 artifacts:

- #599 — Clock in/out flow.
- #600 — Daily report flow.
- #572 — Receiving routing silently ignores damaged/used Unknown Part items.
- #567, #555, #501 — Warehouse floor-plan/audit/receiving QA holes.
- #561 — Settings build/runtime confidence.
- #571, #582, #569, #554 — AI help registry/page-context freshness gaps.
- #616, #612, #610 — Scheduling usability/date/preview gaps.
- #597 — Parts importing.
- #553 — Chat unread badge/security visibility.

## Platform support discovered

Current repo evidence shows:

- The active app target is `Weird Parts IOS/Weird Parts.xcodeproj` through `WiredPart-iOS.xcscheme`.
- `TARGETED_DEVICE_FAMILY = "1,2"`, so iPhone and iPad are in scope.
- `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"`, so iOS device/simulator is the primary supported runtime.
- `SUPPORTS_MACCATALYST = YES` appears in the iOS project settings, but there is no active standalone macOS project or scheme in the current repo checkout. Treat Mac/Catalyst as a conditional compatibility surface through the `WiredPart-iOS` scheme, not a full beta-blocking surface, until a build owner confirms a runnable Mac/Catalyst target.
- No watchOS, tvOS, visionOS, Android, Windows, or web/Tauri runtime is in scope for this Apple ecosystem audit.

## Target device and orientation matrix

| Surface | Required? | Device / destination | Orientation / size class | Why it matters | Evidence required |
| --- | --- | --- | --- | --- | --- |
| iPhone compact | Yes, P0 | Current iPhone simulator/device matching the project deployment target as closely as available | Portrait, compact width | Field workers will use clock, jobs, parts lookup, QR, receiving, staging, tools, fleet, chat, and forms one-handed. | Screenshot/video for each high-priority flow; pass/fail notes for usability categories C1-C6; keyboard evidence for form-heavy flows. |
| iPhone landscape | Spot-check | Same iPhone destination | Landscape, compact height | Catches toolbars, keyboard, sheets, scanners, and floor-plan overflow. | Spot-check screenshots for Dashboard, Clock, Parts, Jobs, Warehouse, Orders, Settings; file issues only for broken/unusable layouts. |
| iPad regular | Yes, P0/P1 | Current iPad simulator/device | Portrait and landscape, regular width | Office/warehouse users need larger navigation, split views, tables, floor plans, reports, procurement, and settings. | Screenshot/video for every high-priority area; route/navigation evidence; sheet/detent evidence for edit/create flows. |
| iPad small split-view | P1 | iPad simulator using narrow/split width when practical | Compact or medium width | Catches iPad-only assumptions that fail in multitasking. | At minimum route smoke and one form/sheet per major area. |
| Physical iPhone | P1 for native-only capabilities | Real device when available | Portrait primary, landscape spot-check | Required for camera, location, share sheet, file permissions, notifications, and realistic touch/keyboard. | Device name/iOS version, permission state, screenshot/video, failure links. Simulator is acceptable only when hardware is unavailable and the limitation is noted. |
| Physical iPad | P1 for warehouse/office workflows | Real device when available | Landscape primary, portrait spot-check | Warehouse floor plans, reports, procurement, settings, and office approvals are likely iPad-heavy. | Device name/iPadOS version, floor-plan/table/form evidence, failure links. |
| Mac Catalyst / Designed for iPad on Mac | Conditional P2 | Only if Xcode exposes a runnable Mac/Catalyst destination for the iOS target | Resizable desktop window | Project settings claim Catalyst support, but current repo evidence does not prove a full Mac runtime. | Build/run proof first. If runnable, capture launch, navigation, keyboard/mouse, window resizing, menu/share/file behavior. If not runnable, record exclusion with build evidence. |
| Standalone macOS scheme | Excluded unless restored | N/A | N/A | No standalone macOS project/scheme is active in the current checkout. | Exclusion note is enough unless a future PR restores a macOS target. |

## Feature-area matrix

Use this matrix with the WEI-1944 verification rows. Each area must be checked on iPhone compact and iPad regular unless explicitly marked as spot-check.

| Area | Priority | iPhone requirement | iPad requirement | Native/device trigger | Linked issues / docs | Evidence package |
| --- | --- | --- | --- | --- | --- | --- |
| Fresh install, bootstrap, login, logout, PIN error | High | Required | Required | Keyboard, migration failure, first-run persistence | WEI-1944 row 64 | Screens/video for empty DB bootstrap, wrong PIN, logout/login, restart persistence. |
| Global navigation/sidebar/account menu/edit tabs | High | Required | Required | Route/deep-link behavior | WEI-1944 row 65 | Route smoke for every module/subtab; note placeholder/dead route failures. |
| Dashboard overview | Medium | Required | Required | Cards/sheets/dynamic type | WEI-1944 row 66 | Main page + card detail/action evidence. |
| Clock in/out and daily report | High/P0 | Required | Required | Location, keyboard, questionnaire, submit states | #599, #600, #554 | Full clock-in → break/switch/todo → clock-out → daily report walkthrough; C1-C6 notes. |
| QR scanner and QR labels | High | Required | iPad spot-check | Camera, permission, print/share | WEI-1944 row 68 | Permission allow/deny/no-camera simulator notes; scan result navigation. |
| Parts catalog/categories/suppliers/pricing/companions/forecasting/import-export | High | Required | Required | Keyboard, file import/export, delete confirmations | #597, #651 | Search/filter/create/edit/delete/import evidence; invalid input and error states. |
| Jobs list/detail/labor/questionnaires/reports | High | Required | Required | Job tabs, forms, privacy, clock linkage | #599, #600, #569 | Job list/detail screenshots, required form validation, privacy/permission notes. |
| Warehouse dashboard/movements/locations/floor plan/staging/receiving/audit/inventory/returns/settings | High/P0 | Required | Required | Drag/drop, gestures, QR, numeric forms, physical-layout UI | #572, #567, #555, #501, #638, #651 | Warehouse movement/floor-plan/audit/receiving walkthrough with screenshots/video and failure links. |
| Orders JPO/PO/procurement/receiving/returns/wishlist/staging | High/P0 | Required | Required | Multi-step writes, receiving, native share/export if present | #572 | JPO create/approve → PO/procurement → receive/route/return evidence. |
| People/customers/contractors/contacts/teams/hats/permissions | High | Required | Required | Permission/privacy | WEI-1944 row 86 | CRUD + hat/permission changes; worker vs manager visibility notes. |
| Chat, Q&A, RFI, supplier bridge | High | Required | Required | Keyboard, attachments, permissions | #553 | Message send/fail/offline, unread badge, attachment/reference picker, RFI state transitions. |
| Scheduling calendar/dispatch/time off/config/pipeline | High | Required | Required | Drag/drop/fallback, date pickers, conflicts | #616, #612, #610 | 14-day preview, subcontractor dates, dispatch/time-off/config evidence. |
| Tools and Fleet | High/Medium | Required | Required | QR, forms, inspections, checkout/return | #582, WEI-1944 rows 89-90 | Checkout/return/trade/inspection/mileage evidence; dismiss-safety notes. |
| Reports and Office dashboards | Medium | Spot-check compact usability | Required | Tables, exports/share, financial permissions | WEI-1944 rows 91, 93 | iPad primary table/export/approval evidence; iPhone readability spot-check. |
| Notebooks and daily-report integration | High | Required | Required | Keyboard-heavy block editor, attachments, conflicts | #600, #651 | Block edit/template/job notebook/daily report pull-through evidence. |
| Settings grouped router/themes/company/sync/security/backups/export/reset/device/about/templates | High | Required | Required | Native file dialogs, dangerous resets, Bluetooth/device permissions | #561, #571, #650 | Every settings group opens; save/revert/reset/export evidence; Help/AI mapping. |
| AI assistant and page help | Medium/P1 | Representative pages required | Representative pages required | Context after navigation/search/filter/forms | #650, #571, #582, #569, #554 | Coverage table showing page, help registry result, context freshness result, linked fix/closure. |
| Sync/offline/device security/background jobs | High | Required where simulator can model it | Required where simulator can model it | Multi-device/network disconnect/native permissions | WEI-1944 row 96 | Offline/network/device evidence; document simulator limitations. |

## Evidence requirements per area

Every verification packet should include:

1. Device and OS: simulator/device name, iOS/iPadOS version, and orientation.
2. App/build identity: branch/commit or PR, scheme, and whether it was simulator or physical hardware.
3. Main page screenshot or video.
4. At least one representative detail/sheet/wizard screenshot or video.
5. C1-C6 checklist from WEI-1944:
   - C1 dismiss and sheet safety.
   - C2 silent failure visibility.
   - C3 save/delete feedback.
   - C4 navigation exits.
   - C5 form validation.
   - C6 keyboard/touch/accessibility basics.
6. Pass/PARTIAL/FAIL status.
7. Links to any GitHub/Paperclip issues opened, updated, or closed.
8. Explicit note when existing automated/static evidence is enough and no manual retest is required.

## Explicit exclusions

- Standalone macOS app audit is excluded until the missing `mac/` container is restored or a build owner confirms a runnable macOS target.
- Mac Catalyst / Designed for iPad on Mac is conditional, not a beta blocker, until a runnable destination is proven.
- Android, Windows, Tauri desktop/web, watchOS, tvOS, and visionOS are out of scope for WEI-1985.
- Deep external integration QA is out of scope unless the flow is already present in the iOS app.
- Full end-to-end two-device sync is not required for every feature area; it belongs to the Sync/offline/device security row and should note hardware availability.
- This matrix does not close #649, #650, or #651; it links and scopes them for follow-on implementation/QA.

## Recommended execution order

1. Resolve coordination/documentation clarity first: #649.
2. Confirm build/navigation health and settings confidence: #561 and Settings matrix row.
3. Run iPhone + iPad P0/P1 walkthroughs: Clock/daily report, Warehouse, Orders/Receiving, Jobs, Parts, Settings.
4. Run AI/help coverage: #650, linking #571/#582/#569/#554.
5. Run placeholder/dead-text triage: #651.
6. Run remaining P1/P2 polish: Scheduling, Chat/RFI, Tools/Fleet, Reports/Office, Notebooks.
7. If a runnable Mac/Catalyst destination is confirmed, run a narrow compatibility pass and append results to this matrix; otherwise keep Mac explicitly excluded.

## Completion criteria for WEI-1985

WEI-1985 is complete when this matrix exists in the repo and the parent/related issues can use it to start focused verification work. It does not claim that every Apple surface passed; it defines what must be tested, what evidence is required, and which Apple surfaces are currently in or out of beta scope.
