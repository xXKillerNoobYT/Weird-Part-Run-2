import SwiftUI
import GRDB
import WiredPartCore

/// Tool kits list page for iOS.
///
/// Displays a searchable list of tool kits showing kit name, tool count,
/// and status badge. Uses direct SQL queries against the tool_kits and
/// tool_kit_items tables. Supports pull-to-refresh and search filtering.
struct IOSToolKitsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var kits: [ToolKitRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""

    var body: some View {
        kitContent
            .navigationTitle("Tool Kits")
            .searchable(text: $searchText, prompt: "Search kits...")
            .refreshable { loadData() }
            .task { loadData() }
    }

    // MARK: - Content

    @ViewBuilder
    private var kitContent: some View {
        if isLoading {
            ProgressView("Loading tool kits...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if filteredKits.isEmpty {
            ContentUnavailableView {
                Label("No Kits", systemImage: "bag")
            } description: {
                Text("No tool kits found.")
            }
        } else {
            List(filteredKits) { kit in
                kitRow(kit)
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredKits: [ToolKitRow] {
        guard !searchText.isEmpty else { return kits }
        let query = searchText.lowercased()
        return kits.filter {
            $0.name.lowercased().contains(query) ||
            ($0.description?.lowercased().contains(query) ?? false)
        }
    }

    // MARK: - Row

    private func kitRow(_ kit: ToolKitRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bag.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(kit.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let desc = kit.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Label("\(kit.toolCount) tools", systemImage: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            statusBadge(kit.status)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badge

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "complete": .green
        case "incomplete": .orange
        case "checked_out": .blue
        case "maintenance": .red
        default: .secondary
        }
        return Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Model

    struct ToolKitRow: Identifiable {
        let id: Int64
        let name: String
        let description: String?
        let toolCount: Int
        let status: String
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else {
            isLoading = false
            loadError = "Database unavailable"
            return
        }
        isLoading = kits.isEmpty
        do {
            kits = try db.writer.read { db in
                let sql = """
                    SELECT tk.id, tk.name,
                           tk.description,
                           COALESCE(tk.status, 'available') AS status,
                           COUNT(tki.id) AS tool_count
                    FROM tool_kits tk
                    LEFT JOIN tool_kit_items tki ON tki.kit_id = tk.id AND tki.deleted_at IS NULL
                    WHERE tk.deleted_at IS NULL
                    GROUP BY tk.id
                    ORDER BY tk.name
                    """
                return try Row.fetchAll(db, sql: sql).map { row in
                    ToolKitRow(
                        id: row["id"],
                        name: row["name"],
                        description: row["description"],
                        toolCount: row["tool_count"],
                        status: row["status"]
                    )
                }
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
