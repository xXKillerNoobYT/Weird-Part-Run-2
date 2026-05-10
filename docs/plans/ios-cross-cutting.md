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
