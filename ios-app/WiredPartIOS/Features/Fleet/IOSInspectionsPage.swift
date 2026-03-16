import SwiftUI
import GRDB
import WiredPartCore

/// Vehicle inspections list page for iOS.
///
/// Displays a searchable list of inspection records with vehicle name,
/// inspector, date, and result badge (pass=green, fail=red).
/// Queries `vehicle_inspections` table directly via raw SQL since
/// FleetService doesn't have a dedicated inspections method.
struct IOSInspectionsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var inspections: [InspectionRow] = []
    @State private var isLoading = true
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            inspectionList
                .navigationTitle("Inspections")
                .searchable(text: $searchText, prompt: "Search inspections...")
                .refreshable { loadData() }
                .task { loadData() }
        }
    }

    // MARK: - Inspection List

    @ViewBuilder
    private var inspectionList: some View {
        if isLoading {
            ProgressView("Loading inspections...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredInspections.isEmpty {
            ContentUnavailableView {
                Label("No Inspections", systemImage: "checklist")
            } description: {
                Text("No vehicle inspections have been recorded yet.")
            }
        } else {
            List(filteredInspections, id: \.id) { inspection in
                inspectionRow(inspection)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredInspections: [InspectionRow] {
        guard !searchText.isEmpty else { return inspections }
        let query = searchText.lowercased()
        return inspections.filter {
            $0.vehicleName.lowercased().contains(query) ||
            $0.inspectorName.lowercased().contains(query) ||
            $0.result.lowercased().contains(query)
        }
    }

    private func inspectionRow(_ inspection: InspectionRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist.checked")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(inspection.vehicleName)
                        .fontWeight(.medium)
                    resultBadge(inspection.result)
                }
                HStack(spacing: 6) {
                    Label(inspection.inspectorName, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(String(inspection.inspectionDate.prefix(10)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if let odo = inspection.odometerReading {
                Text("\(odo.formatted()) mi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = inspections.isEmpty

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
                print("[IOSInspectionsPage] Error: \(error)")
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
