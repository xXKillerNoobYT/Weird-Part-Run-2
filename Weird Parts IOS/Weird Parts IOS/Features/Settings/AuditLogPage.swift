import SwiftUI
import GRDB
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
    @State private var entries: [AuditEntry] = []
    @State private var errorMessage: String?
    @State private var limit = 50

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
                    ForEach(entries) { entry in
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
        .task { loadData() }
    }

    // MARK: - Row View

    private func auditRow(_ entry: AuditEntry) -> some View {
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
        guard let db = appCore.db else {
            errorMessage = "Database not available."
            isLoading = false
            return
        }
        do {
            entries = try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT cl.id, cl.table_name, cl.operation, cl.timestamp AS changed_at,
                           cl.device_id
                    FROM _change_log cl
                    ORDER BY cl.timestamp DESC
                    LIMIT ?
                """, arguments: [limit])
                return rows.map { row in
                    AuditEntry(
                        id: "\(row["id"] as Int64? ?? 0)",
                        entityType: row["table_name"] as? String ?? "unknown",
                        action: row["operation"] as? String ?? "unknown",
                        timestamp: row["changed_at"] as? String ?? "",
                        deviceId: row["device_id"] as? String
                    )
                }
            }
        } catch {
            let msg = String(describing: error)
            if msg.contains("no such table") {
                entries = []
            } else {
                errorMessage = "Failed to load audit log: \(error.localizedDescription)"
            }
        }
        isLoading = false
    }

    // MARK: - Model

    private struct AuditEntry: Identifiable {
        let id: String
        let entityType: String
        let action: String
        let timestamp: String
        let deviceId: String?
    }
}
