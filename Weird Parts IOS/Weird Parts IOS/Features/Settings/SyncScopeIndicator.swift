import SwiftUI

// MARK: - Sync Scope

/// Classification for how a setting syncs across devices.
///
/// Used to show users which settings will propagate to other devices
/// and which stay local. The actual sync filtering will be implemented
/// in the sync engine — this is currently visual-only.
enum SyncScope: String, CaseIterable {
    case company
    case personal
    case device

    var icon: String {
        switch self {
        case .company:  return "globe"
        case .personal: return "person.fill"
        case .device:   return "iphone"
        }
    }

    var label: String {
        switch self {
        case .company:  return "Syncs to all devices"
        case .personal: return "Syncs to your devices"
        case .device:   return "This device only"
        }
    }

    var shortLabel: String {
        switch self {
        case .company:  return "Company"
        case .personal: return "Personal"
        case .device:   return "Device"
        }
    }

    // MARK: - Classification Map

    /// Returns the sync scope for a given settings tab ID.
    static func scope(for tabId: String) -> SyncScope {
        switch tabId {
        // Company scope — propagate to all devices
        case "settings-company",
             "settings-billing",
             "settings-pdf",
             "settings-breaks", "settings-break-lunch",
             "settings-tool-policies",
             "settings-pretrip-checklists",
             "settings-dispatch-preferences",
             "settings-purchase-orders",
             "settings-forecast-config",
             "settings-org-thresholds",
             "settings-audit-settings",
             "settings-daily-report-templates",
             "settings-job-estimation-questions",
             "settings-report-templates",
             "settings-clockout", "settings-clock-out-questions",
             "settings-security",
             "settings-keys":
            return .company

        // Personal scope — syncs to current user's devices
        case "settings-themes",
             "settings-notifications",
             "settings-app-config",
             "settings-ai-config":
            return .personal

        // Device scope — local only
        default:
            return .device
        }
    }

    /// Returns the dominant scope for a group of tab IDs.
    static func dominantScope(for tabIds: [String]) -> SyncScope {
        let scopes = tabIds.map { scope(for: $0) }
        let companyCt = scopes.filter { $0 == .company }.count
        let personalCt = scopes.filter { $0 == .personal }.count
        let deviceCt = scopes.filter { $0 == .device }.count

        if companyCt >= personalCt && companyCt >= deviceCt { return .company }
        if personalCt >= deviceCt { return .personal }
        return .device
    }
}

// MARK: - Sync Scope Indicator View

/// A small pill badge showing the sync scope of a settings page.
///
/// Use as a banner at the top of individual settings pages, or inline
/// as a compact icon indicator in the settings list.
struct SyncScopeIndicator: View {
    let scope: SyncScope
    var compact: Bool = false

    var body: some View {
        if compact {
            Image(systemName: scope.icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        } else {
            HStack(spacing: 6) {
                Image(systemName: scope.icon)
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(scope.label)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
        }
    }
}

#Preview("All Scopes") {
    VStack(spacing: 16) {
        ForEach(SyncScope.allCases, id: \.self) { scope in
            SyncScopeIndicator(scope: scope)
        }
        Divider()
        HStack(spacing: 16) {
            ForEach(SyncScope.allCases, id: \.self) { scope in
                SyncScopeIndicator(scope: scope, compact: true)
            }
        }
    }
    .padding()
}
