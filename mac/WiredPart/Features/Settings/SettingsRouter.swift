import SwiftUI

/// Routes a `/settings/*` path to the appropriate settings page view.
struct SettingsRouter: View {
    @EnvironmentObject private var appCore: AppCore
    let path: String

    /// Extract the tab ID from the path, e.g. "/settings/themes" -> "themes"
    private var tabId: String {
        let components = path.split(separator: "/")
        // Path is "/settings/tab-id" so the tab ID is the last component
        guard components.count >= 2 else { return "app-config" }
        return String(components.last ?? "app-config")
    }

    var body: some View {
        switch tabId {
        case "app-config":
            AppConfigPage()
        case "about":
            AboutPage()
        case "themes":
            ThemesPage()
        case "notification-prefs":
            NotificationPrefsPage()
        case "company-profiles":
            CompanyProfilesPage()
        case "pdf-settings":
            PDFSettingsPage()
        case "billing-pay-settings":
            BillingPayPage()
        case "supplier-bridge":
            SupplierBridgePage()
        case "sync":
            SyncPage()
        case "bluetooth":
            BluetoothPage()
        case "clock-out-questions":
            ClockOutQuestionsPage()
        case "backups":
            BackupsPage()
        case "bootstrap-admin":
            BootstrapAdminPage()
        case "key-management":
            KeyManagementPage()
        case "security-admin":
            SecurityAdminPage()
        case "update-protocol":
            UpdateProtocolPage()
        case "data-export":
            DataExportPage()
        case "integrations":
            IntegrationsPage()
        case "audit-log":
            AuditLogPage()
        default:
            AppConfigPage()
        }
    }
}
