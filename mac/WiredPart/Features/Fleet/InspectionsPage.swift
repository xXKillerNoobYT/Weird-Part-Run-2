import SwiftUI
import GRDB
import WiredPartCore

/// Vehicle inspections page — lists all inspection records with vehicle name,
/// inspector, date, result, and notes.
///
/// Inspections are stored in `vehicle_inspections` table. This page queries
/// directly since FleetService doesn't have a dedicated inspections method yet.
struct InspectionsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var inspections: [InspectionRow] = []
    @State private var searchText = ""
    @State private var isLoading = true

    private var filtered: [InspectionRow] {
        guard !searchText.isEmpty else { return inspections }
        let query = searchText.lowercased()
        return inspections.filter {
            $0.vehicleName.lowercased().contains(query) ||
            $0.inspectorName.lowercased().contains(query) ||
            $0.result.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if isLoading {
                ProgressView("Loading inspections…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                emptyState
            } else {
                inspectionsTable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadData() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Vehicle Inspections")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("\(inspections.count) inspection\(inspections.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                TextField("Search…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Button {
                    loadData()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Inspections Found")
                .font(.title3)
                .fontWeight(.semibold)
            Text(searchText.isEmpty
                 ? "No vehicle inspections have been recorded yet."
                 : "No inspections match your search.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Table

    private var inspectionsTable: some View {
        Table(filtered) {
            TableColumn("Vehicle") { row in
                Text(row.vehicleName)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 160)

            TableColumn("Inspector") { row in
                Text(row.inspectorName)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 140)

            TableColumn("Date") { row in
                Text(String(row.inspectionDate.prefix(10)))
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Result") { row in
                resultBadge(row.result)
            }
            .width(80)

            TableColumn("Odometer") { row in
                if let odo = row.odometerReading {
                    Text("\(odo) mi")
                        .monospacedDigit()
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(80)

            TableColumn("Notes") { row in
                Text(row.notes ?? "—")
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func resultBadge(_ result: String) -> some View {
        let color: Color = switch result.lowercased() {
        case "pass", "passed": .green
        case "fail", "failed": .red
        case "conditional": .orange
        default: .gray
        }
        return Text(result.capitalized)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            try db.writer.read { dbConn in
                let sql = """
                    SELECT vi.id, vi.inspection_date, vi.result, vi.notes, vi.odometer_reading,
                           COALESCE(v.vehicle_name, v.vehicle_number, 'Unknown') AS vehicle_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS inspector_name
                    FROM vehicle_inspections vi
                    LEFT JOIN vehicles v ON v.id = vi.vehicle_id
                    LEFT JOIN users u ON u.id = vi.inspector_id
                    WHERE vi.deleted_at IS NULL
                    ORDER BY vi.inspection_date DESC
                    LIMIT 100
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql)
                inspections = rows.map { row in
                    InspectionRow(
                        id: row["id"] ?? 0,
                        vehicleName: row["vehicle_name"] ?? "Unknown",
                        inspectorName: row["inspector_name"] ?? "Unknown",
                        inspectionDate: row["inspection_date"] ?? "",
                        result: row["result"] ?? "pending",
                        odometerReading: row["odometer_reading"] as Int?,
                        notes: row["notes"] as String?
                    )
                }
            }
        } catch {
            let msg = String(describing: error)
            if msg.contains("no such table") {
                inspections = []
            } else {
                print("[InspectionsPage] Error: \(error)")
            }
        }

        isLoading = false
    }
}

// MARK: - Supporting Types

private struct InspectionRow: Identifiable {
    let id: Int64
    let vehicleName: String
    let inspectorName: String
    let inspectionDate: String
    let result: String
    let odometerReading: Int?
    let notes: String?
}
