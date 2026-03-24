# Prompt 52F — Settings: Sync Scope Classification

> **Area:** Settings (cross-cutting)
> **Dependencies:** 52A (grouped navigation)
> **What the user sees:** No indication of which settings sync across devices and which are local-only.
> **What this fixes:** Add sync scope indicators to all settings and classification logic.

---

## Task

Add a sync scope classification system to settings. Each setting has a scope that determines how it syncs across devices.

## Sync Scopes

| Scope | Icon | Label | Behavior |
|-------|------|-------|----------|
| Company | 🌐 | "Syncs to all devices" | Changes propagate to every device in the company |
| Personal | 👤 | "Syncs to your devices" | Changes propagate only to the current user's devices |
| Device | 📱 | "This device only" | Never syncs, stays on this device |

## Classification by Settings Page

### Company Scope (🌐)
- Company Profiles
- Billing/Pay
- PDF Settings
- Payment Tracking
- Break/Lunch Policy
- Tool Policies
- Pre-Trip Checklists
- Dispatch Preferences
- Forecast Config
- Organization Thresholds
- Audit Settings
- Daily Report Templates
- Job Estimation Questions
- Report Templates
- Clock-Out Questions
- Security Admin
- Key Management

### Personal Scope (👤)
- Themes
- Notifications
- App Config (display preferences)
- AI Config (personal AI preferences)

### Device Scope (📱)
- About (device info)
- Sync (device sync config)
- Bluetooth (device pairing)
- Device Management
- Bootstrap
- Backups (local files)
- Export (local files)
- Database Reset
- Update Protocol
- Remote Sync
- Shared Channels
- Integrations (device-specific API keys)
- Supplier Bridge (device-specific)
- Audit Log (local audit trail)

## UI Implementation

### Sync Indicator Component

Create a reusable `SyncScopeIndicator` view:

```swift
struct SyncScopeIndicator: View {
    let scope: SyncScope

    enum SyncScope: String {
        case company, personal, device

        var icon: String {
            switch self {
            case .company: return "🌐"
            case .personal: return "👤"
            case .device: return "📱"
            }
        }

        var label: String {
            switch self {
            case .company: return "Syncs to all devices"
            case .personal: return "Syncs to your devices"
            case .device: return "This device only"
            }
        }
    }

    var body: some View {
        // Small pill badge: icon + label
        // Gray background, small font
    }
}
```

### Where to Show

1. **Settings list page (SettingsRouter):** Each NavigationLink row shows the sync scope icon (just the emoji, no label) as a trailing element
2. **Individual settings pages:** Show `SyncScopeIndicator` at the top of the page as a small banner below the navigation title
3. **Group headers in settings list:** Show most common scope for the group (e.g., "Company" group → 🌐)

### Scope Metadata

Add a static dictionary mapping settings page routes to their sync scope:

```swift
extension SettingsRoute {
    var syncScope: SyncScopeIndicator.SyncScope {
        switch self {
        case .companyProfiles, .billingPay, .pdfSettings, .paymentTracking,
             .breakLunchPolicy, .toolPolicies, .preTripChecklists, .dispatchPreferences,
             .forecastConfig, .organizationThresholds, .auditSettings,
             .dailyReportTemplates, .jobEstimationQuestions, .reportTemplates,
             .clockOutQuestions, .securityAdmin, .keyManagement:
            return .company
        case .themes, .notifications, .appConfig, .aiConfig:
            return .personal
        default:
            return .device
        }
    }
}
```

### Sync Engine Integration

**Do NOT modify the sync engine.** This prompt only adds visual indicators. The actual sync filtering (company vs personal vs device) will be handled by the sync engine when it's built — this classification just makes the intent visible to users now.

Add a comment in `SettingsService` or `IOSSyncManager`:
```swift
// TODO: When sync is implemented, filter settings by SyncScope:
// - .company → include in company-wide sync
// - .personal → include in per-user sync
// - .device → exclude from sync
```

## Build target

iOS only. Must compile. This is the last prompt in the Settings series.
