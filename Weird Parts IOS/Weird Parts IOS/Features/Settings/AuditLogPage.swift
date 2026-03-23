import SwiftUI
import WiredPartCore

/// Activity and audit log viewer.
///
/// Displays recent entries from the `_change_log` table showing entity
/// changes with timestamps, entity types, actions, and users. This is
/// a read-only informational page on mobile.
struct AuditLogPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var isLoading = true
    @State private var entries: [SettingsService.AuditLogEntry] = []
    @State private var errorMessage: String?
    @State private var limit = 50
    @State private var searchText = ""

    private var filteredEntries: [SettingsService.AuditLogEntry] {
        guard !searchText.isEmpty else { return entries }
        let query = searchText.lowercased()
        return entries.filter {
            $0.entityType.lowercased().contains(query) ||
            $0.action.lowercased().contains(query) ||
            $0.timestamp.lowercased().contains(query)
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading audit log...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "No Audit Entries",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("No recent changes have been recorded.")
                )
            } else {
                List {
                    ForEach(filteredEntries) { entry in
                        auditRow(entry)
                    }

                    if entries.count >= limit {
                        Section {
                            Button("Load More") {
                                limit += 50
                                Task { loadData() }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    if let errorMessage {
                        Section {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.callout)
                        }
                    }
                }
            }
        }
        .navigationTitle("Audit Log")
        .searchable(text: $searchText, prompt: "Filter by table or action...")
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Row View

    private func auditRow(_ entry: SettingsService.AuditLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconForAction(entry.action))
                    .foregroundStyle(colorForAction(entry.action))
                    .font(.caption)
                Text(entry.entityType.capitalized)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(entry.action.uppercased())
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colorForAction(entry.action).opacity(0.15))
                    .clipShape(Capsule())
            }
            HStack {
                if let deviceId = entry.deviceId {
                    Label(String(deviceId.prefix(12)), systemImage: "desktopcomputer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(entry.timestamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func iconForAction(_ action: String) -> String {
        switch action.lowercased() {
        case "insert", "create": return "plus.circle.fill"
        case "update", "edit":   return "pencil.circle.fill"
        case "delete", "remove": return "trash.circle.fill"
        default:                 return "circle.fill"
        }
    }

    private func colorForAction(_ action: String) -> Color {
        switch action.lowercased() {
        case "insert", "create": return .green
        case "update", "edit":   return .blue
        case "delete", "remove": return .red
        default:                 return .secondary
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
            entries = try settingsService.listAuditLog(limit: limit)
        } catch {
            errorMessage = "Failed to load audit log: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
