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
            .safeAreaInset(edge: .top, spacing: 0) {
                SyncScopeIndicator(scope: SyncScope.scope(for: tabId))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }
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
        case "settings-reset":
            IOSDatabaseResetPage()
        case "settings-security":
            SecurityAdminPage()
        case "settings-audit":
            AuditLogPage()
        case "settings-backups":
            IOSBackupsPage()
        case "settings-keys":
            IOSKeyManagementPage()
        case "settings-bootstrap":
            IOSBootstrapAdminPage()
        case "settings-integrations":
            IOSIntegrationsPage()
        case "settings-export":
            IOSDataExportPage()
        case "settings-updates":
            IOSUpdateProtocolPage()
        case "settings-supplier-bridge":
            IOSSupplierBridgePage()
        case "settings-clockout", "settings-clock-out-questions":
            IOSClockOutQuestionsPage()
        case "settings-breaks", "settings-break-lunch":
            IOSBreakSettingsPage()
        case "settings-ai-config":
            IOSAIConfigPage()
        case "settings-device-management":
            IOSDeviceManagementPage()
        case "settings-remote-sync":
            IOSRemoteSyncPage()
        case "settings-shared-channels":
            IOSSharedChannelsPage()

        // Operations pages — implemented in 52B
        case "settings-tool-policies":
            IOSToolPoliciesPage()
        case "settings-pretrip-checklists":
            IOSPreTripChecklistPage()
        case "settings-dispatch-preferences":
            IOSDispatchPreferencesPage()
        // Warehouse pages — implemented in 52C
        case "settings-forecast-config":
            IOSForecastSettingsPage()
        case "settings-org-thresholds":
            IOSOrganizationThresholdsPage()
        case "settings-audit-settings":
            IOSAuditSettingsPage()
        // Template pages — implemented in 52D
        case "settings-daily-report-templates":
            IOSDailyReportTemplatesPage()
        case "settings-job-estimation-questions":
            IOSEstimationSettingsPage()
        case "settings-report-templates":
            IOSReportTemplatesPage()
        case "settings-payment-tracking":
            comingSoonPage("Payment Tracking", icon: "banknote.fill")

        default:
            Text("Unknown settings page: \(tabId)")
                .foregroundStyle(.secondary)
        }
    }

    private func comingSoonPage(_ title: String, icon: String) -> some View {
        EmptyStateView(icon: icon, title: title, message: "This page is being built.")
            .navigationTitle(title)
    }
}
