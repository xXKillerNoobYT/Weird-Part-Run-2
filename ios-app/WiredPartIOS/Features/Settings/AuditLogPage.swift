import SwiftUI
import GRDB
import WiredPartCore

/// Audit log viewer page.
///
/// Displays the activity log entries from the database showing
/// who did what and when. Reads directly from the activity_log table.
struct AuditLogPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var entries: [AuditEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading audit log...")
            } else if entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No audit log entries yet")
                        .font(.headline)
                    Text("Activity is recorded as users interact with the system.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.action)
                                    .font(.body)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(entry.timestamp)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            HStack(spacing: 8) {
                                if let userName = entry.userName {
                                    Text(userName)
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                }
                                Text("\(entry.entityType) #\(entry.entityId)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let details = entry.details, !details.isEmpty {
                                Text(details)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .onAppear { loadEntries() }
    }

    private func loadEntries() {
        isLoading = true
        do {
            entries = try appCore.db.writer.read { dbConnection -> [AuditEntry] in
                let rows = try Row.fetchAll(dbConnection, sql: """
                    SELECT al.*, u.display_name
                    FROM activity_log al
                    LEFT JOIN users u ON u.id = al.user_id
                    ORDER BY al.timestamp DESC
                    LIMIT 200
                    """)
                return rows.map { row in
                    AuditEntry(
                        id: row["id"] as Int64,
                        userId: row["user_id"] as Int64?,
                        userName: row["display_name"] as String?,
                        action: row["action"] as String,
                        entityType: row["entity_type"] as String? ?? "unknown",
                        entityId: row["entity_id"] as Int64? ?? 0,
                        details: row["details"] as String?,
                        timestamp: row["timestamp"] as String? ?? ""
                    )
                }
            }
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - Audit Entry Model

private struct AuditEntry: Identifiable {
    let id: Int64
    let userId: Int64?
    let userName: String?
    let action: String
    let entityType: String
    let entityId: Int64
    let details: String?
    let timestamp: String
}
