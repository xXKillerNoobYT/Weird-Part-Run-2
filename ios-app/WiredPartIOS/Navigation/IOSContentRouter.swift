import SwiftUI
import WiredPartCore

/// Routes a URL-style path to the appropriate native view.
///
/// Paths that have fully implemented native views are routed directly.
/// All other paths show a placeholder indicating the feature is coming soon.
struct IOSContentRouter: View {
    let path: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        routedView
    }

    @ViewBuilder
    private var routedView: some View {
        switch path {
        // Dashboard
        case "/dashboard":
            DashboardView()

        // Parts sub-routes
        case "/parts/categories":
            PartsRouter(tabId: "parts-categories")
        case "/parts/catalog":
            PartsRouter(tabId: "parts-catalog")
        case "/parts/brands":
            PartsRouter(tabId: "parts-brands")
        case "/parts/suppliers":
            PartsRouter(tabId: "parts-suppliers")
        case "/parts/pricing":
            PartsRouter(tabId: "parts-pricing")
        case "/parts/companions":
            PartsRouter(tabId: "parts-companions")
        case "/parts/forecasting":
            PartsRouter(tabId: "parts-forecasting")
        case "/parts/import-export":
            PartsRouter(tabId: "parts-import-export")

        // Settings sub-routes
        case "/settings/themes":
            SettingsRouter(tabId: "settings-themes")
        case "/settings/app-config":
            SettingsRouter(tabId: "settings-app-config")
        case "/settings/about":
            SettingsRouter(tabId: "settings-about")
        case "/settings/company":
            SettingsRouter(tabId: "settings-company")
        case "/settings/pdf":
            SettingsRouter(tabId: "settings-pdf")
        case "/settings/billing":
            SettingsRouter(tabId: "settings-billing")
        case "/settings/notifications":
            SettingsRouter(tabId: "settings-notifications")
        case "/settings/sync":
            SettingsRouter(tabId: "settings-sync")
        case "/settings/bluetooth":
            SettingsRouter(tabId: "settings-bluetooth")
        case "/settings/clockout":
            SettingsRouter(tabId: "settings-clockout")
        case "/settings/backups":
            SettingsRouter(tabId: "settings-backups")
        case "/settings/bootstrap":
            SettingsRouter(tabId: "settings-bootstrap")
        case "/settings/keys":
            SettingsRouter(tabId: "settings-keys")
        case "/settings/security":
            SettingsRouter(tabId: "settings-security")
        case "/settings/updates":
            SettingsRouter(tabId: "settings-updates")
        case "/settings/export":
            SettingsRouter(tabId: "settings-export")
        case "/settings/integrations":
            SettingsRouter(tabId: "settings-integrations")
        case "/settings/audit":
            SettingsRouter(tabId: "settings-audit")
        case "/settings/supplier-bridge":
            SettingsRouter(tabId: "settings-supplier-bridge")

        // Jobs sub-routes
        case "/jobs/list":
            JobsRouter(tabId: "jobs-list")
        case "/jobs/labor":
            JobsRouter(tabId: "jobs-labor")
        case "/jobs/reports":
            JobsRouter(tabId: "jobs-reports")

        // Warehouse sub-routes
        case "/warehouse/dashboard":
            WarehouseRouter(tabId: "warehouse-dashboard")
        case "/warehouse/movements":
            WarehouseRouter(tabId: "warehouse-movements")
        case "/warehouse/locations":
            WarehouseRouter(tabId: "warehouse-locations")

        // Everything else — placeholder for future native views
        default:
            PlaceholderView(path: path)
        }
    }
}

// MARK: - Placeholder

/// Informational placeholder shown for routes that don't yet have
/// a native SwiftUI implementation.
struct PlaceholderView: View {
    let path: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Coming Soon")
                .font(.title2)
                .fontWeight(.semibold)
            Text(path)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospaced()
            Text("This feature is being built as a native SwiftUI view.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .background(Color(.systemBackground))
        #elseif os(macOS)
        .background(Color(.windowBackgroundColor))
        #endif
    }
}
