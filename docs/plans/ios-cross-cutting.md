# Cross-Cutting Area Plan — iOS

> **Status:** In progress (AUTO GO iter 57+)
> **Area tag:** cross-cutting
> **Last updated:** 2026-04-20

---

## What This Does

The cross-cutting area is the program's foundational layer — what every other area sits on top of. It includes the app shell (AppCore, root navigation, theming), the auth/onboarding flow (PIN-based session, role-derived hat permissions, device key binding), the navigation system (87-page router, tab bar, sidebar config, deep linking), Multipeer sync (peer discovery, change-log replication, conflict resolution), Apple Foundation Models AI integration (page-context Q&A, action suggestions, conversation memory), the scanning subsystem (QR/barcode/camera + sticker validation), shared reusable components (ContentUnavailableView wrappers, FormSheet, ErrorStateView, EmptyStateView, MessageBubble, etc.), the entire DesignSystem/ (Components/Foundation/Styles/Tokens — 20 files), and the WebFallback (WKWebView for legacy URLs). Plus 5 core services that don't belong to a single feature: AuthService, FoundationModelsService, BackgroundTaskService, BadgeCountService, AIDispatchService.

## Why

This is the area where defects have amplified impact: a bug in auth breaks everyone's login; a sync regression silently corrupts data across the shop; a navigation mistake makes a whole feature unreachable; a theme break uglifies every page; a Foundation Models race condition crashes the AI panel from any page. Cross-cutting also owns the load-bearing security primitives — HMAC-signed tokens, CryptoKit-derived PIN hashes, Keychain-stored device salts, the future SQLCipher integration. So while feature areas can ship with polish gaps without breaking the world, cross-cutting can't. This area's checklist is run last in the rotation specifically so all the feature areas have settled their dependencies first; cross-cutting sweeps catch what those dependencies forced into the foundations. The area also bundles the DesignSystem (which doesn't belong to any feature) and the shared components library (used by everyone).

---

## Overview

The cross-cutting area covers the foundational layers that all 87 feature pages depend on: the app shell, auth/onboarding flow, navigation system, sync engine, AI integration, scanning subsystem, and all shared reusable components. Because everything else builds on top of this, quality issues here have amplified impact.

---

## iOS Files by Subdirectory (~91 files as of 2026-05-01; DesignSystem + Shared grew naturally past initial ~65 estimate)

### App/ (6 files)
| File | Purpose |
|------|---------|
| `WiredPartIOSApp.swift` | App entry point, AppCore initialization |
| `AppCore.swift` | Central service locator — inits all 22 services, manages session |
| `LoadingView.swift` | Initial loading screen |
| `GeofenceManager.swift` | GPS geofencing for clock-in/out radius |
| `GeofenceAlertView.swift` | Alert overlay for geofence events |
| `LocationManager.swift` | Core Location wrapper |

### Auth/ (12 files)
| File | Purpose |
|------|---------|
| `BootstrapView.swift` | First-launch decision: login or onboarding |
| `LoginView.swift` | PIN-based login |
| `CompanySetupWizard.swift` | Multi-step company setup (new install) |
| `AdminAccountSetupView.swift` | Create first admin account |
| `BusinessProfileSetupView.swift` | Company name/address setup step |
| `DevicePairingView.swift` | QR-based device pairing (sync) |
| `ModuleTourView.swift` | Feature tour for new users |
| `NewUserWelcomeView.swift` | Welcome screen for non-admin new users |
| `OnboardingCompleteView.swift` | Onboarding done confirmation |
| `OnboardingWalkthroughView.swift` | Step-by-step feature walkthrough |
| `OnboardingWelcomeView.swift` | Welcome to app screen |
| `SyncWaitingView.swift` | Waiting for sync/pairing screen |

### Navigation/ (6 files)
| File | Purpose |
|------|---------|
| `IOSContentRouter.swift` | Root router — picks between auth flow and main app |
| `IOSMainView.swift` | Main tab bar + NavigationStack host |
| `NavigationConfig.swift` | Tab definitions, icons, feature toggles |
| `TabBarEditorView.swift` | User-customizable tab order |
| `TabBarPreferences.swift` | Persists tab order preferences |
| `UserMenuSheet.swift` | User menu (profile, log out) |

### AI/ (3 files)
| File | Purpose |
|------|---------|
| `IOSAIAssistantPanel.swift` | Floating AI chat panel |
| `IOSAIAvailabilityBanner.swift` | Foundation Models availability indicator |
| `IOSAITextEditor.swift` | AI-enhanced text editing component |

### Scanning/ (7 files)
| File | Purpose |
|------|---------|
| `IOSQRScanner.swift` | Camera QR code scanner |
| `QRScanSheet.swift` | Sheet wrapper for QR scanner |
| `QRLabelPrintSheet.swift` | QR label print/share sheet |
| `IOSOCRScanner.swift` | Vision framework OCR scanner |
| `IOSDocumentScanView.swift` | VisionKit document scanner |
| `IOSCameraMatchView.swift` | Camera-based part matching |
| `IOSAutoFillBanner.swift` | Banner for OCR autofill suggestions |
| `IOSImageFeatureAdapter.swift` | Vision framework feature extraction |

### Shared/ (~24 files)
Reusable components used across all 87 pages:
- `EmptyStateView.swift`, `ErrorStateView.swift` — standard empty/error displays
- `PageHelpSheet.swift` — standardized help sheet
- `PermissionGate.swift` — permission check wrapper
- `SmartFilterCard.swift`, `StandardFilterBar.swift` — filter UI components
- `UserFriendlyError.swift` — error message formatter
- `Formatters.swift` — date/currency/number formatters
- `BadgeCountManager.swift` — badge count coordination
- `DeviceContext.swift` — device type/capability detection
- `DataRefreshNotifier.swift` — cross-module data refresh signaling
- `ConfirmationSheet.swift`, `FormSheet.swift`, `SheetDismissWrapper.swift` — sheet wrappers
- `StatusBadge.swift`, `DeliveryTimelineBar.swift`, `JobStageProgressBar.swift` — shared UI
- `SearchableList.swift` — reusable searchable list
- `AIFilterRegistry.swift` — AI-powered filter suggestions
- `HelpContentRegistry.swift` — centralized help content
- `OnboardingBanner.swift`, `OnboardingProgress.swift`, `OnboardingProgressManager.swift`, `OnboardingTasks.swift`, `FirstVisitHint.swift`, `SkippedModuleHint.swift` — onboarding system

### DesignSystem/ (20 files — unplanned extras, correctly present)
Full design token + component library added outside the original plan scope:
- **Components/**: ActionIndicator, ActivityRow, AlertBanner, AvatarView, FilterChip, KPICard, LoadingState, QuickActionButton, SubTabPicker
- **Foundation/**: SystemIntegration (feature detection, environment bridging)
- **Styles/**: ButtonStyles, CardStyles, ListRowStyles, SectionHeaderStyle
- **Tokens/**: Animation, CornerRadius, Elevation, SemanticColors, Spacing, Typography

*C1b drift note (2026-04-20): DesignSystem was built alongside the app but never documented in any plan file. It's correctly implemented — it just needs to be tracked here going forward.*

### Sync/ (7 files)
| File | Purpose |
|------|---------|
| `IOSSyncManager.swift` | Multipeer Connectivity P2P sync orchestration |
| `IOSPeerBrowser.swift` | Peer discovery UI |
| `IOSSyncStatusView.swift` | Sync status indicator |
| `SyncConflictBanner.swift` | Conflict notification banner |
| `SyncConflictClassifier.swift` | Conflict severity classification |
| `SyncConflictReviewPage.swift` | User-facing conflict resolution |
| `AIConflictResolutionView.swift` | AI-assisted merge suggestion |

### WebFallback/ (1 file)
- `IOSWebFallbackView.swift` — WKWebView fallback for unsupported pages

---

## Core Services (in `core/Sources/WiredPartCore/Services/`)

| Service | Methods | Purpose |
|---------|---------|---------|
| `AuthService.swift` | ~12 | PIN auth, session management, device identity |
| `AIDispatchService.swift` | ~8 | Route AI requests to correct model/endpoint |
| `FoundationModelsService.swift` | ~6 | Apple Foundation Models integration |
| `BackgroundTaskService.swift` | ~5 | BGTask/BGProcessingTask scheduling |
| `BadgeCountService.swift` | ~8 | Unread counts for tabs/nav items |

---

## Current State

- **Auth flow:** PIN-based login complete. Company setup wizard complete. Device pairing UI present (sync not yet active — `isSyncAvailable = false`).
- **Navigation:** Tab bar system with customizable order. NavigationConfig controls which tabs show and their order. Feature-area routing via `SettingsRouter`, per-area routers.
- **Sync:** `IOSSyncManager` wired to Multipeer Connectivity framework. `SyncWaitingView` shows "Sync Not Available Yet" (Phase 13 — ON HOLD per architecture).
- **AI:** `FoundationModelsService` wired to Apple Foundation Models. `IOSAIAssistantPanel` functional. Availability check returns device + iOS version compatibility.
- **Scanning:** QR scanner (AVFoundation), OCR (Vision), document scan (VisionKit) all present.
- **Shared components:** `PageHelpSheet`, `PermissionGate`, `SmartFilterCard`, `EmptyStateView`, `ErrorStateView`, `UserFriendlyError` used across all areas.

---

## Design Decisions

1. **Auth model:** PIN-based (no username/password). Per-device identity. First user is admin; subsequent users added by admin.
2. **Sync:** Multipeer Connectivity (BT/Wi-Fi P2P). LWW + field-level merge. `_change_log` table. Pairing via QR. Currently `isSyncAvailable = false` pending implementation (Phase 13 ON HOLD).
3. **AI:** Apple Foundation Models only. `FoundationModelsService` wraps the framework. No external LLM server, no cloud calls, no LM Studio. Falls back gracefully on older iOS.
4. **Badge counts:** `BadgeCountService` + `BadgeCountManager` on iOS side. Cached in memory, refreshed on data change events via `DataRefreshNotifier`.
5. **Permission system:** `PermissionGate` view wraps protected content. `appCore.hasPermission()` is the single check point. Permissions stored in `user_permissions` table per user.
6. **Navigation:** Tab bar is user-customizable (`TabBarEditorView`). `NavigationConfig` defines all 14+ feature tabs with their icons and labels. IOSContentRouter routes between auth and main app.

---

## Security Notes

- PIN hashing: per-user salt + 10K iterations (fixed in Prompt 09).
- Local token: `generateLocalToken` returns nil not "invalid_token".
- No credentials stored in UserDefaults.

---

## Open Issues

- **#257** — Architecture drift in CLAUDE.md (dual-platform section not fully updated to iOS-only). Tracked for C12/CLAUDE.md update.
- **Q&A #221** — LWW + field-level merge conflict resolution design pending user decision.
- **Phase 13 ON HOLD** — Sync implementation blocked on architecture decision.

---

## Token Spec: Time-Based Priority Colors

> **Source:** WEI-810 / WEI-451 / GH#42 T2-03. Design-first deliverable from UXDesigner; engineering hand-off to CTO.
> **Status:** Spec — ready for implementation. Last revised 2026-05-12.

### Intent

Priority color is a **function of time remaining until the due date**, not a function of the priority label. A "High" task that is 10 days out is calmer than a "Low" task that is overdue. The chip color must reflect the real urgency the user feels — and it must update on its own as time passes. Labels (`urgent`, `high`, `normal`, `low`) remain a sorting/grouping concept, but they no longer drive color.

### Single Source of Truth

One helper. One file. One set of buckets. No duplicate color logic anywhere else in the iOS app.

- **File:** `Weird Parts IOS/Weird Parts IOS/Shared/TimelinePriorityColor.swift`
- **Naming decision:** The issue text proposes `PriorityColor.color(forDueDate:now:)`. We keep the existing type name `TimelinePriorityColor` instead — it more accurately describes the behavior (time-based, not label-based), and the symbol is already adopted by 17 call sites. Renaming would churn the codebase with zero user-visible benefit. The acceptance criterion "one helper, one source of truth" is what matters; the name is incidental.

### Required API (pure functions)

The helper must be **pure** — every input that affects the result is a parameter. No hidden reads of `Date()` inside the function body. This is what makes the four-bucket unit test reliable.

```swift
struct TimelinePriorityColor {
    /// Primary helper — pure function of (dueDate, now, isCompleted).
    static func color(
        forDueDate dueDate: Date?,
        now: Date = Date(),
        isCompleted: Bool = false
    ) -> Color
}
```

Existing convenience overloads (`color(for:isCompleted:)`, `color(priority:dueDate:)`, string-date variants, `urgencyLabel(...)`) remain, but each one MUST forward to the pure primary and accept an optional `now: Date = Date()` parameter so tests can inject a fixed clock.

### Bucket Boundaries (locked)

Half-open intervals on `hoursRemaining = (dueDate − now) / 3600`:

| Bucket  | Condition                       | Token                       | Raw fallback | Meaning                |
| ------- | ------------------------------- | --------------------------- | ------------ | ---------------------- |
| Overdue | `hoursRemaining < 0`            | `DS.SemanticColor.error`    | `.red`       | Past due date          |
| Soon    | `0 ≤ hoursRemaining < 24`       | `DS.SemanticColor.warning`  | `.orange`    | Due within 24 hours    |
| Watch   | `24 ≤ hoursRemaining < 96`      | `DS.SemanticColor.caution`  | `.yellow`    | Due within 4 days      |
| Safe    | `hoursRemaining ≥ 96`           | `DS.SemanticColor.success`  | `.green`     | More than 4 days out   |

Edge-case states (do **not** participate in the four-bucket scale):

| State        | Condition                           | Color                |
| ------------ | ----------------------------------- | -------------------- |
| Completed    | `isCompleted == true`               | `Color.gray`         |
| No deadline  | `dueDate == nil`                    | `Color.secondary`    |

Boundary contract for unit tests: `hoursRemaining == 24.0` is **Watch (yellow)**; `hoursRemaining == 96.0` is **Safe (green)**; `hoursRemaining == 0.0` is **Soon (orange)** (not overdue). These exact boundaries are what the WEI-810 unit test must cover (overdue/24h/4d/safe).

### Design-System Token Additions (required)

Add a `caution` token to `DesignSystem/Tokens/SemanticColors.swift` so the Watch bucket has a proper semantic anchor instead of a raw `Color.yellow`. Without this, dark mode and high-contrast users get an off-system yellow that fights the rest of the palette.

```swift
extension DS {
    enum SemanticColor {
        /// Time-pressure caution (between warning and success). Yellow.
        /// Use for the 1–4 day priority bucket and any "watch this" surface
        /// that's not yet at warning level.
        static let caution: Color = .yellow
        // existing: success, warning, error, info
    }
}
```

The existing `tint(_:)` and `muted(_:)` helpers automatically work with `caution` since they accept any `Color`. No new tint helper needed.

### Required Removals (no shadowing)

The acceptance criterion is "existing label-based colors removed (not just shadowed)." After CTO lands the change, the following must **not** exist anywhere in the iOS target:

1. **`DS.SemanticColor.priority(_ level: String) -> Color`** in `SemanticColors.swift` — the label→color mapper. Delete the function. Any caller that survives must route through `TimelinePriorityColor` instead.
2. **`TimelinePriorityColor.fallbackColor(priority:)`** — the legacy label fallback. Delete it. Items that have a priority label but no `dueDate` now render the chip in `Color.secondary` (gray) and rely on the text label / SF Symbol for differentiation, which is the correct outcome: if there's no deadline, there's no time-pressure to show.
3. Any inline `switch priority { case "urgent": .red ... }` blocks discovered during the sweep. CTO should grep for `"urgent".*\.red` and `priority.*\.orange` patterns and route survivors through the helper.

The 5 call sites currently annotated `// TODO: When X gains a dueDate field, replace fallback with TimelinePriorityColor.color(priority:dueDateString:)` (Questions, RFI, Escalation, Approvals, JPOs/JPODetail) lose their fallback when `fallbackColor` is removed. That's intended — those rows simply render `Color.secondary` until their model gains a `dueDate`. We **do not** add `dueDate` to those models as part of WEI-810; that's a separate model-level decision per area.

### Accessibility Requirements

Color alone is a WCAG fail. Every place this helper is used **must** also surface:

1. **A text urgency label.** `TimelinePriorityColor.urgencyLabel(for:)` already exists ("Overdue", "Due today", "Due in 3d", "No deadline", "Completed"). Pair it with the chip so VoiceOver and color-blind users get the same information.
2. **An SF Symbol** on the chip, paired with the color:
   - Overdue → `exclamationmark.triangle.fill`
   - Soon (<24h) → `clock.badge.exclamationmark`
   - Watch (1–4d) → `clock`
   - Safe (>4d) → `checkmark.circle`
   - Completed → `checkmark.circle.fill`
   - No deadline → `calendar.badge.minus`

This is not part of the helper's return value — it's a chip-component concern. But the spec calls it out so engineering doesn't ship a color-only chip and call it done.

### Light + Dark Mode + Viewport Verification

Required visual checks before WEI-810 closes:

| Viewport             | Light mode | Dark mode | Required surfaces                                      |
| -------------------- | ---------- | --------- | ------------------------------------------------------ |
| iPhone 375×812       | ✓          | ✓         | JobsList row, JPOsList row, RFI list row, dashboard KPI |
| Desktop 1280×800     | ✓          | ✓         | iPad sidebar layout, ManageJobs table, Approvals queue |

Specifically watch for:
- Yellow chip foreground vs. light gray card background — must hit ≥ 3:1 contrast.
- Orange and red chips in dark mode — verify they don't bloom against the dark card.
- Green at small sizes (chip icon at 12pt) — system green can read as gray in dark mode; check the SF Symbol stroke is visible.

### Unit-Test Contract (for CTO)

Four-bucket boundary tests using injected `now`:

```swift
let now = Date(timeIntervalSince1970: 1_700_000_000)
XCTAssertEqual(TimelinePriorityColor.color(forDueDate: now.addingTimeInterval(-3600), now: now), .red)     // overdue
XCTAssertEqual(TimelinePriorityColor.color(forDueDate: now.addingTimeInterval( 3600), now: now), .orange)  // 1h ahead
XCTAssertEqual(TimelinePriorityColor.color(forDueDate: now.addingTimeInterval( 24 * 3600), now: now), .yellow) // exactly 24h
XCTAssertEqual(TimelinePriorityColor.color(forDueDate: now.addingTimeInterval( 96 * 3600), now: now), .green)  // exactly 96h
```

Plus: completed → gray; nil dueDate → secondary.

### Hand-off Checklist

- [x] Spec landed in `docs/plans/ios-cross-cutting.md` (this section).
- [x] CTO: add `now: Date = Date()` to `TimelinePriorityColor.color(...)` primary and forward through convenience overloads.
- [x] CTO: add `DS.SemanticColor.caution` token and switch helper output to semantic tokens.
- [x] CTO: delete `DS.SemanticColor.priority(_:)`.
- [x] CTO: delete `TimelinePriorityColor.fallbackColor(priority:)`.
- [x] CTO: confirm all 17 known call sites compile; sweep for inline label→color switches.
- [x] CTO: add four-bucket unit test (above contract) plus completed/no-date cases.
- [x] QA: verify light + dark at iPhone 375×812 and iPad/desktop 1280×800.
