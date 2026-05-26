import SwiftUI
import WiredPartCore

/// Integration settings page for iOS.
///
/// Lists available third-party integrations with enable/disable toggles.
/// Integration configuration details are managed on desktop; this page
/// provides a quick overview and toggle capability.
struct IOSIntegrationsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var activeSheet: ActiveSheet?
    @State private var isLoading = true
    @State private var integrations: [Integration] = []
    @State private var errorMessage: String?

    // MARK: - Body

    var body: some View {
        Form {
            if isLoading {
                Section {
                    ProgressView("Loading integrations...")
                }
            } else if integrations.isEmpty {
                Section {
                    EmptyStateView(
                        icon: "puzzlepiece.extension",
                        title: "No Integrations",
                        message: "No integrations have been configured. Set up integrations from the desktop application."
                    )
                }
            } else {
                Section("Available Integrations") {
                    ForEach($integrations) { $integration in
                        integrationRow(integration: $integration)
                    }
                }
            }

            configInfoSection

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .navigationTitle("Integrations")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Integrations Help", sections: [
                ("What This Page Does", "Lists available third-party integrations and their current status. Toggle integrations on or off from any device in the network."),
                ("How to Use It", "Enable or disable integrations using the toggles. API keys and credentials are configured on the desktop application. Sync runs automatically when an integration is enabled."),
            ])
        }
        .task { loadData() }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    // MARK: - Integration Row

    private func integrationRow(integration: Binding<Integration>) -> some View {
        Toggle(isOn: integration.isEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text(integration.wrappedValue.name)
                    .font(.body)
                Text(integration.wrappedValue.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lastSync = integration.wrappedValue.lastSyncAt {
                    Text("Last sync: \(lastSync)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .onChange(of: integration.wrappedValue.isEnabled) { _, newValue in
            toggleIntegration(integration.wrappedValue.id, enabled: newValue)
        }
    }

    // MARK: - Info Section

    private var configInfoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("API keys and credentials are configured on desktop", systemImage: "desktopcomputer")
                Label("Toggle integrations on/off from any device", systemImage: "switch.2")
                Label("Sync runs automatically when enabled", systemImage: "arrow.triangle.2.circlepath")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let settingsService = appCore.settingsService else {
            errorMessage = "Settings service not available."
            isLoading = false
            return
        }
        do {
            integrations = try settingsService.listIntegrations().map { row in
                Integration(
                    id: row.id,
                    name: row.name,
                    description: row.description,
                    isEnabled: row.isEnabled,
                    lastSyncAt: row.lastSyncAt
                )
            }
        } catch {
            errorMessage = userFriendlyError(error, context: "load integrations")
            integrations = []
        }
        isLoading = false
    }

    // MARK: - Toggle

    private func toggleIntegration(_ id: String, enabled: Bool) {
        guard let settingsService = appCore.settingsService else {
            errorMessage = "Service not available"
            return
        }
        do {
            try settingsService.toggleIntegration(id, enabled: enabled)
        } catch {
            errorMessage = userFriendlyError(error, context: "update")
        }
    }

    // MARK: - Model

    private struct Integration: Identifiable {
        let id: String
        let name: String
        let description: String
        var isEnabled: Bool
        let lastSyncAt: String?
    }
}
