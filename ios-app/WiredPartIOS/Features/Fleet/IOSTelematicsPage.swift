import SwiftUI
import GRDB
import WiredPartCore

/// GPS / Telematics list page for iOS.
///
/// Shows the last known position of each vehicle by querying
/// `vehicle_location_logs` directly via raw SQL. Displays vehicle name,
/// driver, last updated time, and coordinates.
/// Includes an empty state explaining that GPS data comes from mobile devices.
struct IOSTelematicsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var locations: [VehicleLocationRow] = []
    @State private var isLoading = true
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            locationList
                .navigationTitle("GPS & Telematics")
                .searchable(text: $searchText, prompt: "Search vehicles...")
                .refreshable { loadData() }
                .task { loadData() }
        }
    }

    // MARK: - Location List

    @ViewBuilder
    private var locationList: some View {
        if isLoading {
            ProgressView("Loading GPS data...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredLocations.isEmpty {
            ContentUnavailableView {
                Label("No GPS Data", systemImage: "location.slash")
            } description: {
                Text("Vehicle location data will appear here once drivers submit GPS updates from their mobile devices.")
            }
        } else {
            List(filteredLocations, id: \.id) { location in
                locationRow(location)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredLocations: [VehicleLocationRow] {
        guard !searchText.isEmpty else { return locations }
        let query = searchText.lowercased()
        return locations.filter {
            $0.vehicleName.lowercased().contains(query) ||
            $0.driverName.lowercased().contains(query)
        }
    }

    private func locationRow(_ location: VehicleLocationRow) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor(location.status).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "location.fill")
                    .font(.body)
                    .foregroundStyle(statusColor(location.status))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(location.vehicleName)
                        .fontWeight(.medium)
                    statusBadge(location.status)
                }
                Label(location.driverName, systemImage: "person")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lat = location.latitude, let lon = location.longitude {
                    Text(String(format: "%.4f, %.4f", lat, lon))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let speed = location.speed {
                    Text(String(format: "%.0f mph", speed))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                if !location.lastUpdated.isEmpty {
                    Text(String(location.lastUpdated.prefix(16)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "moving": return .green
        case "idle": return .orange
        case "parked", "stopped": return .gray
        default: return .secondary
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let color = statusColor(status)
        return Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = locations.isEmpty

        do {
            try db.writer.read { dbConn in
                // Get latest location per vehicle
                let sql = """
                    SELECT vll.id, vll.latitude, vll.longitude, vll.speed,
                           vll.status, vll.recorded_at,
                           COALESCE(v.vehicle_name, v.vehicle_number, 'Unknown') AS vehicle_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS driver_name
                    FROM vehicle_location_logs vll
                    LEFT JOIN vehicles v ON v.id = vll.vehicle_id
                    LEFT JOIN users u ON u.id = vll.user_id
                    WHERE vll.id IN (
                        SELECT MAX(id) FROM vehicle_location_logs
                        WHERE deleted_at IS NULL
                        GROUP BY vehicle_id
                    )
                    ORDER BY vll.recorded_at DESC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql)
                locations = rows.map { row in
                    VehicleLocationRow(
                        id: row["id"] ?? 0,
                        vehicleName: row["vehicle_name"] ?? "Unknown",
                        driverName: row["driver_name"] ?? "Unknown",
                        latitude: row["latitude"] as Double?,
                        longitude: row["longitude"] as Double?,
                        speed: row["speed"] as Double?,
                        status: row["status"] ?? "unknown",
                        lastUpdated: row["recorded_at"] ?? ""
                    )
                }
            }
        } catch {
            let msg = String(describing: error)
            if msg.contains("no such table") {
                locations = []
            } else {
                print("[IOSTelematicsPage] Error: \(error)")
            }
        }

        isLoading = false
    }
}

// MARK: - Supporting Types

private struct VehicleLocationRow: Identifiable {
    let id: Int64
    let vehicleName: String
    let driverName: String
    let latitude: Double?
    let longitude: Double?
    let speed: Double?
    let status: String
    let lastUpdated: String
}
