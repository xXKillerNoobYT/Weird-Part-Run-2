import SwiftUI
import GRDB
import WiredPartCore

/// System audit log viewer page.
///
/// Reads from the `activity_log` table to display a chronological
/// list of system events (user actions, settings changes, etc.).
struct AuditLogPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var entries: [AuditEntry] = []
    @State private var isLoading: Bool = true
    @State private var filterAction: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Audit Log")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // Filter
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter by action...", text: $filterAction)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                    Button("Refresh") {
                        loadEntries()
                    }
                    .buttonStyle(.bordered)
                }

                // Entries
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if filteredEntries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("No audit log entries found")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    GroupBox("Recent Activity (\(filteredEntries.count))") {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                                auditRow(entry)
                                if index < filteredEntries.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadEntries() }
    }

    private var filteredEntries: [AuditEntry] {
        if filterAction.isEmpty { return entries }
        let query = filterAction.lowercased()
        return entries.filter {
            $0.action.lowercased().contains(query) ||
            ($0.details?.lowercased().contains(query) ?? false)
        }
    }

    private func auditRow(_ entry: AuditEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconForAction(entry.action))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.action.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.callout)
                        .fontWeight(.medium)
                    Spacer()
                    Text(entry.timestamp ?? "")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let details = entry.details, !details.isEmpty {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if let entityType = entry.entityType {
                        Text(entityType)
                            .font(.system(size: 10))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.secondary.opacity(0.1)))
                    }
                    Text("User #\(entry.userId)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func iconForAction(_ action: String) -> String {
        if action.contains("create") || action.contains("add") || action.contains("setup") { return "plus.circle" }
        if action.contains("update") || action.contains("edit") { return "pencil.circle" }
        if action.contains("delete") || action.contains("remove") { return "minus.circle" }
        if action.contains("login") || action.contains("auth") { return "person.badge.key" }
        return "doc.text"
    }

    private func loadEntries() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            entries = try db.writer.read { dbConnection in
                try AuditEntry.fetchAll(
                    dbConnection,
                    sql: "SELECT * FROM activity_log ORDER BY timestamp DESC LIMIT 200"
                )
            }
        } catch {
            entries = []
        }

        isLoading = false
    }
}

// MARK: - Model

private struct AuditEntry: Codable, FetchableRecord, Identifiable {
    var id: Int64?
    var userId: Int64
    var action: String
    var entityType: String?
    var entityId: Int64?
    var details: String?
    var timestamp: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case action
        case entityType = "entity_type"
        case entityId = "entity_id"
        case details
        case timestamp
    }
}
