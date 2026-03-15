import SwiftUI
import WiredPartCore

/// Routes a settings tab ID to the appropriate settings page view.
///
/// Each settings sub-page is a standalone SwiftUI view. Pages that
/// can use existing SettingsService methods are fully functional;
/// pages that need services not yet implemented show informational
/// placeholders with descriptions of their future functionality.
struct SettingsRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        routedView
    }

    @ViewBuilder
    private var routedView: some View {
        switch tabId {
        case "settings-themes":
            ThemesPage()
        case "settings-app-config":
            AppConfigPage()
        case "settings-about":
            AboutPage()
        case "settings-company":
            CompanyProfilesPage()
        case "settings-pdf":
            PDFSettingsPage()
        case "settings-billing":
            BillingPayPage()
        case "settings-notifications":
            NotificationPrefsPage()
        case "settings-sync":
            SyncPage()
        case "settings-bluetooth":
            BluetoothPage()
        case "settings-clockout":
            ClockOutQuestionsPage()
        case "settings-backups":
            BackupsPage()
        case "settings-bootstrap":
            BootstrapAdminPage()
        case "settings-keys":
            KeyManagementPage()
        case "settings-security":
            SecurityAdminPage()
        case "settings-updates":
            UpdateProtocolPage()
        case "settings-export":
            DataExportPage()
        case "settings-integrations":
            IntegrationsPage()
        case "settings-audit":
            AuditLogPage()
        case "settings-supplier-bridge":
            SupplierBridgePage()
        default:
            Text("Unknown settings page: \(tabId)")
                .foregroundStyle(.secondary)
        }
    }
}
