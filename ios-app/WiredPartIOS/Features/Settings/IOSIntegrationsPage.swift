import SwiftUI
import GRDB
import WiredPartCore

/// Integration settings page for iOS.
///
/// Lists available third-party integrations with enable/disable toggles.
/// Integration configuration details are managed on desktop; this page
/// provides a quick overview and toggle capability.
struct IOSIntegrationsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

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
                    ContentUnavailableView(
                        "No Integrations",
                        systemImage: "puzzlepiece.extension",
                        description: Text("No integrations have been configured. Set up integrations from the desktop application.")
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
        .task { loadData() }
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
        guard let db = appCore.db else {
            errorMessage = "Database not available."
            isLoading = false
            return
        }
        do {
            integrations = try db.writer.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT id, name, description, is_enabled, last_sync_at
                    FROM integrations ORDER BY name ASC
                """)
                return rows.map { row in
                    Integration(
                        id: "\(row["id"] as Int64? ?? 0)",
                        name: row["name"] as? String ?? "Unknown",
                        description: row["description"] as? String ?? "",
                        isEnabled: (row["is_enabled"] as? Int64 ?? 0) == 1,
                        lastSyncAt: row["last_sync_at"] as? String
                    )
                }
            }
        } catch {
            if !error.localizedDescription.contains("no such table") {
                errorMessage = "Failed to load integrations: \(error.localizedDescription)"
            }
            integrations = []
        }
        isLoading = false
    }

    // MARK: - Toggle

    private func toggleIntegration(_ id: String, enabled: Bool) {
        guard let db = appCore.db else { return }
        do {
            try db.writer.write { db in
                try db.execute(
                    sql: "UPDATE integrations SET is_enabled = ? WHERE id = ?",
                    arguments: [enabled ? 1 : 0, id]
                )
            }
        } catch {
            errorMessage = "Failed to update: \(error.localizedDescription)"
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
