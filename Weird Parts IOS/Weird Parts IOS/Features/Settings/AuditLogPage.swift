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

    @State private var activeSheet: ActiveSheet?
    @State private var isLoading = true
    @State private var entries: [SettingsService.AuditLogEntry] = []
    @State private var errorMessage: String?
    @State private var limit = 50
    @State private var searchText = ""
    @State private var dateRange: ReportDateRange = .thisWeek
    @State private var customStart: Date = Date().addingTimeInterval(-7 * 86400)
    @State private var customEnd: Date = Date()

    private var filteredEntries: [SettingsService.AuditLogEntry] {
        var result = entries.filter {
            StandardFilterBarDateFilter.contains(
                $0.timestamp,
                selectedRange: dateRange,
                customStart: customStart,
                customEnd: customEnd
            )
        }

        guard !searchText.isEmpty else { return result }
        let query = searchText.lowercased()
        result = result.filter {
            $0.entityType.lowercased().contains(query) ||
            $0.action.lowercased().contains(query) ||
            $0.timestamp.lowercased().contains(query)
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            StandardFilterBar(selectedRange: $dateRange, customStart: $customStart, customEnd: $customEnd)

            if isLoading {
                ProgressView("Loading audit log...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "No Audit Entries",
                    message: "No recent changes have been recorded.",
                    helpLabel: "Learn how audit log works",
                    helpAction: { activeSheet = .help }
                )
            } else if filteredEntries.isEmpty {
                EmptyStateView(
                    icon: "line.3.horizontal.decrease.circle",
                    title: "No Matching Audit Entries",
                    message: "No audit entries match the selected date range and search.",
                    helpLabel: "Learn how audit log works",
                    helpAction: { activeSheet = .help }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Audit Log Help", sections: [
                ("What This Page Does", "Shows a chronological log of all data changes recorded on this device. Each entry shows the entity type, action (insert/update/delete), device, and timestamp."),
                ("How to Use It", "Scroll through recent changes or use the search bar to filter by table name or action. Pull down to refresh. Tap 'Load More' to see older entries."),
            ])
        }
        .searchable(text: $searchText, prompt: "Filter by table or action...")
        .refreshable { loadData() }
        .task { loadData() }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    // MARK: - Row View

    private func auditRow(_ entry: SettingsService.AuditLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconForAction(entry.action))
                    .foregroundStyle(colorForAction(entry.action))
                    .font(.caption)
                    .accessibilityHidden(true)
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
            errorMessage = userFriendlyError(error, context: "load audit log")
        }
        isLoading = false
    }
}
