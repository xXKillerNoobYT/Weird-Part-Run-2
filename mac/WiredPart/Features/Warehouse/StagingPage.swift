import SwiftUI
import GRDB
import WiredPartCore

/// Pulled staging tags management page.
///
/// Shows all active staging tags grouped by destination. Each tag displays
/// the part info, quantity, location, and who tagged it. Provides actions
/// to clear individual tags or all tags for a destination.
struct StagingPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var groups: [StagingGroup] = []
    @State private var isLoading = true

    // MARK: - Confirm Clear

    @State private var showClearAllConfirm = false
    @State private var clearAllDestination: String = ""

    @State private var showClearOneConfirm = false
    @State private var clearOneTagId: Int64?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                stagingContent
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadData() }
        .alert("Clear All Tags", isPresented: $showClearAllConfirm) {
            Button("Clear All", role: .destructive) {
                clearAllForDestination(clearAllDestination)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clear all staging tags for \"\(clearAllDestination)\"? This cannot be undone.")
        }
        .alert("Clear Tag", isPresented: $showClearOneConfirm) {
            Button("Clear", role: .destructive) {
                if let tagId = clearOneTagId {
                    clearSingleTag(tagId)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove this staging tag?")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Staging")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                let totalTags = groups.reduce(0) { $0 + $1.tags.count }
                Text("\(totalTags) tag\(totalTags == 1 ? "" : "s") across \(groups.count) destination\(groups.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                loadData()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Staging Content

    @ViewBuilder
    private var stagingContent: some View {
        if isLoading {
            ProgressView("Loading staging tags...")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
        } else if groups.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "tray.2")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No active staging tags")
                    .font(.headline)
                Text("Items tagged for staging will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            LazyVStack(spacing: 20) {
                ForEach(groups, id: \.destination) { group in
                    destinationGroup(group)
                }
            }
        }
    }

    private func destinationGroup(_ group: StagingGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(group.destination.isEmpty ? "No Destination" : group.destination,
                      systemImage: "mappin.and.ellipse")
                    .font(.headline)
                Spacer()
                Text("\(group.tags.count) item\(group.tags.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Menu {
                    Button("Move to Truck") {
                        // Placeholder for future action
                    }
                    Button("Move to Trailer") {
                        // Placeholder for future action
                    }
                    Button("Return to Warehouse") {
                        // Placeholder for future action
                    }
                    Divider()
                    Button("Clear All for \"\(group.destination)\"", role: .destructive) {
                        clearAllDestination = group.destination
                        showClearAllConfirm = true
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 100)
            }

            ForEach(group.tags, id: \.id) { tag in
                stagingTagCard(tag)
            }
        }
    }

    private func stagingTagCard(_ tag: StagingTagRow) -> some View {
        GroupBox {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tag.partName)
                        .font(.callout)
                        .fontWeight(.medium)
                    HStack(spacing: 12) {
                        if !tag.partCode.isEmpty {
                            Label(tag.partCode, systemImage: "barcode")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Label("Qty: \(tag.qty)", systemImage: "number")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label(tag.locationType, systemImage: "building.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        if !tag.taggedByName.isEmpty {
                            Label(tag.taggedByName, systemImage: "person")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(formatDate(tag.taggedAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Button {
                    clearOneTagId = tag.id
                    showClearOneConfirm = true
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Clear this staging tag")
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Helpers

    nonisolated private func formatDate(_ dateStr: String?) -> String {
        guard let dateStr else { return "-" }
        if dateStr.count >= 16 {
            return String(dateStr.prefix(16))
        }
        return dateStr
    }

    // MARK: - Actions

    private func clearSingleTag(_ tagId: Int64) {
        guard let db = appCore.db else { return }
        do {
            try db.writer.write { conn in
                try conn.execute(
                    sql: "UPDATE pulled_staging_tags SET deleted_at = datetime('now') WHERE id = ?",
                    arguments: [tagId]
                )
            }
        } catch {
            print("[StagingPage] Clear tag error: \(error)")
        }
        loadData()
    }

    private func clearAllForDestination(_ destination: String) {
        guard let db = appCore.db else { return }
        do {
            try db.writer.write { conn in
                try conn.execute(
                    sql: "UPDATE pulled_staging_tags SET deleted_at = datetime('now') WHERE destination_label = ? AND deleted_at IS NULL",
                    arguments: [destination]
                )
            }
        } catch {
            print("[StagingPage] Clear all error: \(error)")
        }
        loadData()
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            try db.writer.read { conn in
                let rows = try Row.fetchAll(conn, sql: """
                    SELECT pst.id, pst.stock_id, pst.destination_type,
                           pst.destination_id, pst.destination_label,
                           pst.tagged_at,
                           s.qty, s.location_type, s.location_id,
                           COALESCE(p.name, 'Unknown Part') AS part_name,
                           COALESCE(p.code, '') AS part_code,
                           COALESCE(u.display_name, '') AS tagged_by_name
                    FROM pulled_staging_tags pst
                    JOIN stock s ON s.id = pst.stock_id
                    LEFT JOIN parts p ON p.id = s.part_id
                    LEFT JOIN users u ON u.id = pst.tagged_by
                    WHERE pst.deleted_at IS NULL
                    ORDER BY pst.destination_label, pst.tagged_at DESC
                    """)

                let tags = rows.map { row in
                    StagingTagRow(
                        id: row["id"] ?? 0,
                        stockId: row["stock_id"] ?? 0,
                        destinationLabel: row["destination_label"] ?? "",
                        partName: row["part_name"] ?? "Unknown",
                        partCode: row["part_code"] ?? "",
                        qty: row["qty"] ?? 0,
                        locationType: row["location_type"] ?? "",
                        taggedByName: row["tagged_by_name"] ?? "",
                        taggedAt: row["tagged_at"]
                    )
                }

                // Group by destination
                let grouped = Dictionary(grouping: tags) { $0.destinationLabel }
                groups = grouped.map { key, values in
                    StagingGroup(destination: key, tags: values)
                }
                .sorted { $0.destination < $1.destination }
            }
        } catch {
            print("[StagingPage] Load error: \(error)")
        }

        isLoading = false
    }
}

// MARK: - Display Models

private struct StagingTagRow: Identifiable {
    let id: Int64
    let stockId: Int64
    let destinationLabel: String
    let partName: String
    let partCode: String
    let qty: Int
    let locationType: String
    let taggedByName: String
    let taggedAt: String?
}

private struct StagingGroup {
    let destination: String
    let tags: [StagingTagRow]
}
