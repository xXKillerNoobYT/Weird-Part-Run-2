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
            .onAppear {
                NotificationCenter.default.post(
                    name: .settingsPageActive,
                    object: nil,
                    userInfo: ["context": settingsPageContext]
                )
            }
            .onDisappear {
                NotificationCenter.default.post(name: .settingsPageInactive, object: nil)
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
        case "settings-purchase-orders":
            IOSPurchaseOrderSettingsPage()
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
        case "settings-job-stage-templates":
            IOSJobStageTemplatesSettingsPage()
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

    private var settingsPageContext: String {
        let scope = SyncScope.scope(for: tabId)
        return "page=Settings; tab_id=\(tabId); sync_scope=\(scope.rawValue)"
    }
}

/// Company-wide purchase order drafting settings.
private struct IOSPurchaseOrderSettingsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var groupingMode: PurchaseOrderGroupingMode = .perSupplierMixed
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        Form {
            if isLoading {
                ProgressView("Loading purchase order settings...")
            } else {
                Section("PO Grouping") {
                    Picker("Grouping mode", selection: $groupingMode) {
                        Text("Mixed").tag(PurchaseOrderGroupingMode.perSupplierMixed)
                        Text("Per job").tag(PurchaseOrderGroupingMode.perSupplierPerJob)
                    }
                    .pickerStyle(.segmented)

                    modeSummary
                }

                Section {
                    Button {
                        saveSettings()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save Settings")
                        }
                    }
                    .disabled(isSaving)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if let successMessage {
                Section {
                    Text(successMessage)
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("Purchase Orders")
        .task { loadSettings() }
    }

    private var modeSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(groupingMode.displayName, systemImage: groupingMode == .perSupplierMixed ? "shippingbox.fill" : "folder.badge.gearshape")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(groupingMode == .perSupplierMixed
                 ? "Creates one draft PO per supplier. Job attribution stays on each line item."
                 : "Creates separate draft POs for each supplier and job. Job attribution still stays on each line item.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func loadSettings() {
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service not available"
            isLoading = false
            return
        }

        do {
            groupingMode = try service.getPurchaseOrderSettings().groupingMode
        } catch {
            errorMessage = userFriendlyError(error, context: "load purchase order settings")
        }
        isLoading = false
    }

    private func saveSettings() {
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service not available"
            return
        }

        isSaving = true
        errorMessage = nil
        successMessage = nil
        do {
            let saved = try service.updatePurchaseOrderSettings(
                SettingsService.PurchaseOrderSettings(groupingMode: groupingMode)
            )
            groupingMode = saved.groupingMode
            successMessage = "Purchase order settings saved."
        } catch {
            errorMessage = userFriendlyError(error, context: "save purchase order settings")
        }
        isSaving = false
    }
}
