import SwiftUI
import GRDB
import WiredPartCore

/// Stock movements list with sortable table, filters, and detail sheets.
///
/// Shows all stock movements in a macOS-native Table with sortable columns.
/// Supports filtering by movement type, search text, and date range.
/// Click a row to view full movement details in a sheet.
struct MovementsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var movements: [MovementRow] = []
    @State private var isLoading = true

    // MARK: - Filters

    @State private var searchText = ""
    @State private var selectedType = "all"
    @State private var selectedRange = "30"

    // MARK: - Detail Sheet

    @State private var selectedMovement: MovementRow?
    @State private var showDetail = false

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\MovementRow.createdAt, order: .reverse)]

    private let movementTypes = ["all", "transfer", "consume", "return", "receive", "adjust"]
    private let dateRanges = [("7", "7 days"), ("30", "30 days"), ("90", "90 days"), ("all", "All time")]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tableContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { loadData() }
        .sheet(isPresented: $showDetail) {
            if let movement = selectedMovement {
                movementDetailSheet(movement)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Movements")
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer()

            // Movement type filter
            Picker("Type", selection: $selectedType) {
                ForEach(movementTypes, id: \.self) { type in
                    Text(type == "all" ? "All Types" : type.capitalized).tag(type)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 150)
            .onChange(of: selectedType) { _, _ in loadData() }

            // Date range filter
            Picker("Range", selection: $selectedRange) {
                ForEach(dateRanges, id: \.0) { range in
                    Text(range.1).tag(range.0)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 120)
            .onChange(of: selectedRange) { _, _ in loadData() }

            // Search
            TextField("Search parts...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .onChange(of: searchText) { _, _ in loadData() }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Table Content

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("Loading movements...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if movements.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No movements found")
                    .font(.headline)
                Text(searchText.isEmpty && selectedType == "all"
                     ? "Stock movements will appear here."
                     : "Try adjusting your search or filters.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedMovements, sortOrder: $sortOrder) {
                TableColumn("Date", value: \.createdAt) { row in
                    Text(formatDate(row.createdAt))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 140)

                TableColumn("Part", value: \.partName) { row in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.partName)
                            .fontWeight(.medium)
                        if !row.partCode.isEmpty {
                            Text(row.partCode)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .width(min: 120, ideal: 200)

                TableColumn("From -> To", value: \.locationDescription) { row in
                    Text(row.locationDescription)
                        .font(.callout)
                }
                .width(min: 100, ideal: 160)

                TableColumn("Qty", value: \.qty) { row in
                    Text("\(row.qty)")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(row.qty > 0 ? Color.green : Color.red)
                }
                .width(min: 50, ideal: 60)

                TableColumn("Type", value: \.movementType) { row in
                    Text(row.movementType.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(typeColor(row.movementType).opacity(0.15))
                        .foregroundStyle(typeColor(row.movementType))
                        .clipShape(Capsule())
                }
                .width(min: 70, ideal: 90)

                TableColumn("Performed By", value: \.performerName) { row in
                    Text(row.performerName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 120)

                TableColumn("Notes", value: \.notes) { row in
                    Text(row.notes)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 150)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: MovementRow.ID.self) { ids in
                if let id = ids.first, let movement = movements.first(where: { $0.id == id }) {
                    Button("View Details") {
                        selectedMovement = movement
                        showDetail = true
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first, let movement = movements.first(where: { $0.id == id }) {
                    selectedMovement = movement
                    showDetail = true
                }
            }
        }
    }

    private var sortedMovements: [MovementRow] {
        movements.sorted(using: sortOrder)
    }

    // MARK: - Detail Sheet

    private func movementDetailSheet(_ movement: MovementRow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Movement #\(movement.id)")
                        .font(.title)
                        .fontWeight(.bold)
                    Spacer()
                    Button("Done") { showDetail = false }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.cancelAction)
                }

                Divider()

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    detailField("Part", value: movement.partName)
                    detailField("Code", value: movement.partCode)
                    detailField("Quantity", value: "\(movement.qty)")
                    detailField("Type", value: movement.movementType.capitalized)
                    detailField("From", value: movement.fromLocationType ?? "-")
                    detailField("To", value: movement.toLocationType ?? "-")
                    detailField("Performed By", value: movement.performerName)
                    detailField("Date", value: movement.createdAt)
                }

                if !movement.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(movement.notes)
                            .font(.body)
                    }
                }

                if !movement.reason.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reason")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(movement.reason)
                            .font(.body)
                    }
                }
            }
            .padding(24)
        }
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

    nonisolated private func typeColor(_ type: String) -> Color {
        switch type {
        case "transfer": return .blue
        case "consume": return .orange
        case "return": return .purple
        case "receive": return .green
        case "adjust": return .gray
        default: return .blue
        }
    }

    nonisolated private func formatDate(_ dateStr: String) -> String {
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
                var whereClauses = ["sm.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                // Movement type filter
                if selectedType != "all" {
                    whereClauses.append("sm.movement_type = ?")
                    args.append(selectedType)
                }

                // Date range filter
                if selectedRange != "all", let days = Int(selectedRange) {
                    whereClauses.append("sm.created_at >= datetime('now', '-\(days) days')")
                }

                // Search filter
                let trimmed = searchText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    whereClauses.append("(p.name LIKE ? OR p.code LIKE ? OR sm.reference_number LIKE ?)")
                    let like = "%\(trimmed)%"
                    args.append(like)
                    args.append(like)
                    args.append(like)
                }

                let sql = """
                    SELECT sm.id, sm.part_id, sm.qty, sm.movement_type,
                           sm.from_location_type, sm.from_location_id,
                           sm.to_location_type, sm.to_location_id,
                           sm.reason, sm.notes, sm.reference_number,
                           sm.created_at,
                           COALESCE(p.name, 'Unknown Part') AS part_name,
                           COALESCE(p.code, '') AS part_code,
                           COALESCE(u.display_name, 'Unknown') AS performer_name
                    FROM stock_movements sm
                    LEFT JOIN parts p ON p.id = sm.part_id
                    LEFT JOIN users u ON u.id = sm.performed_by
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY sm.created_at DESC
                    LIMIT 500
                    """

                let rows = try Row.fetchAll(conn, sql: sql, arguments: StatementArguments(args) ?? StatementArguments())

                movements = rows.map { row in
                    let fromLoc: String? = row["from_location_type"]
                    let toLoc: String? = row["to_location_type"]
                    var locDesc: String
                    if let from = fromLoc, let to = toLoc {
                        locDesc = "\(from) -> \(to)"
                    } else if let to = toLoc {
                        locDesc = "-> \(to)"
                    } else if let from = fromLoc {
                        locDesc = "\(from) ->"
                    } else {
                        locDesc = "-"
                    }

                    return MovementRow(
                        id: row["id"] ?? 0,
                        partName: row["part_name"] ?? "Unknown",
                        partCode: row["part_code"] ?? "",
                        qty: row["qty"] ?? 0,
                        movementType: row["movement_type"] ?? "transfer",
                        fromLocationType: row["from_location_type"],
                        toLocationType: row["to_location_type"],
                        locationDescription: locDesc,
                        reason: row["reason"] ?? "",
                        notes: row["notes"] ?? "",
                        performerName: row["performer_name"] ?? "Unknown",
                        createdAt: row["created_at"] ?? ""
                    )
                }
            }
        } catch {
            print("[MovementsPage] Load error: \(error)")
        }

        isLoading = false
    }
}

// MARK: - Movement Row Model

/// View-model for a single row in the movements table.
/// Identifiable for Table selection, Comparable fields for sorting.
private struct MovementRow: Identifiable {
    let id: Int64
    let partName: String
    let partCode: String
    let qty: Int
    let movementType: String
    let fromLocationType: String?
    let toLocationType: String?
    let locationDescription: String
    let reason: String
    let notes: String
    let performerName: String
    let createdAt: String
}
