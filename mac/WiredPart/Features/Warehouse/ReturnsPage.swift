import SwiftUI
import GRDB
import WiredPartCore

/// Returns management page showing recent return movements.
///
/// Displays return-type stock movements with part info, quantities,
/// location details, and notes. Supports filtering and restock actions.
struct ReturnsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var returns: [ReturnRow] = []
    @State private var isLoading = true

    // MARK: - Filters

    @State private var searchText = ""
    @State private var filterStatus = "all"

    // MARK: - Detail

    @State private var selectedReturn: ReturnRow?
    @State private var showDetail = false

    private let statusFilters = ["all", "pending", "processed"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                returnsContent
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadData() }
        .sheet(isPresented: $showDetail) {
            if let ret = selectedReturn {
                returnDetailSheet(ret)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Returns")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(returns.count) return movement\(returns.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            // Status filter
            Picker("Status", selection: $filterStatus) {
                ForEach(statusFilters, id: \.self) { status in
                    Text(status == "all" ? "All" : status.capitalized).tag(status)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 250)
            .onChange(of: filterStatus) { _, _ in loadData() }

            // Search
            TextField("Search parts...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .onChange(of: searchText) { _, _ in loadData() }
        }
    }

    // MARK: - Returns Content

    @ViewBuilder
    private var returnsContent: some View {
        if isLoading {
            ProgressView("Loading returns...")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
        } else if returns.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No return movements found")
                    .font(.headline)
                Text(searchText.isEmpty
                     ? "Return movements will appear here."
                     : "Try adjusting your search.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(returns, id: \.id) { ret in
                    returnCard(ret)
                }
            }
        }
    }

    private func returnCard(_ ret: ReturnRow) -> some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 4) {
                    Text(ret.partName)
                        .font(.callout)
                        .fontWeight(.medium)
                    HStack(spacing: 8) {
                        if !ret.partCode.isEmpty {
                            Text(ret.partCode)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Qty: \(ret.qty)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    HStack(spacing: 8) {
                        if let from = ret.fromLocationType {
                            Label(from, systemImage: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if let to = ret.toLocationType {
                            Label(to, systemImage: "arrow.left")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    if !ret.notes.isEmpty {
                        Text(ret.notes)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(ret.performerName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatDate(ret.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Button("View") {
                    selectedReturn = ret
                    showDetail = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Detail Sheet

    private func returnDetailSheet(_ ret: ReturnRow) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Return Details")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Done") { showDetail = false }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.cancelAction)
            }

            Divider()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                detailField("Part", value: ret.partName)
                detailField("Code", value: ret.partCode)
                detailField("Quantity", value: "\(ret.qty)")
                detailField("From Location", value: ret.fromLocationType ?? "-")
                detailField("To Location", value: ret.toLocationType ?? "-")
                detailField("Performed By", value: ret.performerName)
                detailField("Date", value: formatDate(ret.createdAt))
                detailField("Reason", value: ret.reason)
            }

            if !ret.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ret.notes)
                        .font(.body)
                }
            }

            Divider()

            HStack(spacing: 12) {
                Button {
                    // Restock action — create a new movement to warehouse
                } label: {
                    Label("Restock to Warehouse", systemImage: "arrow.uturn.forward")
                }
                .buttonStyle(.bordered)
                .tint(.green)

                Button {
                    // Mark as damaged
                } label: {
                    Label("Mark Damaged", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Spacer()
            }
        }
        .padding(24)
        .frame(minWidth: 500, minHeight: 350)
    }

    private func detailField(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "-" : value)
                .font(.body)
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

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            try db.writer.read { conn in
                var whereClauses = [
                    "sm.deleted_at IS NULL",
                    "sm.movement_type = 'return'"
                ]
                var args: [DatabaseValueConvertible?] = []

                // Search filter
                let trimmed = searchText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    whereClauses.append("(p.name LIKE ? OR p.code LIKE ?)")
                    let like = "%\(trimmed)%"
                    args.append(like)
                    args.append(like)
                }

                // Status filter: "pending" = recent (last 7 days), "processed" = older
                if filterStatus == "pending" {
                    whereClauses.append("sm.created_at >= datetime('now', '-7 days')")
                } else if filterStatus == "processed" {
                    whereClauses.append("sm.created_at < datetime('now', '-7 days')")
                }

                let sql = """
                    SELECT sm.id, sm.part_id, sm.qty, sm.movement_type,
                           sm.from_location_type, sm.to_location_type,
                           sm.reason, sm.notes, sm.created_at,
                           COALESCE(p.name, 'Unknown Part') AS part_name,
                           COALESCE(p.code, '') AS part_code,
                           COALESCE(u.display_name, 'Unknown') AS performer_name
                    FROM stock_movements sm
                    LEFT JOIN parts p ON p.id = sm.part_id
                    LEFT JOIN users u ON u.id = sm.performed_by
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY sm.created_at DESC
                    LIMIT 200
                    """

                let rows = try Row.fetchAll(conn, sql: sql, arguments: StatementArguments(args) ?? StatementArguments())

                returns = rows.map { row in
                    ReturnRow(
                        id: row["id"] ?? 0,
                        partName: row["part_name"] ?? "Unknown",
                        partCode: row["part_code"] ?? "",
                        qty: row["qty"] ?? 0,
                        fromLocationType: row["from_location_type"],
                        toLocationType: row["to_location_type"],
                        reason: row["reason"] ?? "",
                        notes: row["notes"] ?? "",
                        performerName: row["performer_name"] ?? "Unknown",
                        createdAt: row["created_at"]
                    )
                }
            }
        } catch {
            print("[ReturnsPage] Load error: \(error)")
        }

        isLoading = false
    }
}

// MARK: - Display Models

private struct ReturnRow: Identifiable {
    let id: Int64
    let partName: String
    let partCode: String
    let qty: Int
    let fromLocationType: String?
    let toLocationType: String?
    let reason: String
    let notes: String
    let performerName: String
    let createdAt: String?
}
