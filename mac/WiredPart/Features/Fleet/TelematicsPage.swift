import SwiftUI
import GRDB
import WiredPartCore

/// GPS / Telematics page — shows vehicle location data, last known positions,
/// and trip history.
///
/// Note: On macOS, GPS data comes from driver-submitted location updates
/// (stored in `vehicle_location_logs`). Real-time GPS tracking is an iOS feature
/// where the phone itself provides coordinates.
struct TelematicsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var vehicles: [VehicleLocationRow] = []
    @State private var searchText = ""
    @State private var isLoading = true

    private var filtered: [VehicleLocationRow] {
        guard !searchText.isEmpty else { return vehicles }
        let query = searchText.lowercased()
        return vehicles.filter {
            $0.vehicleName.lowercased().contains(query) ||
            $0.driverName.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if isLoading {
                ProgressView("Loading GPS data…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                emptyState
            } else {
                locationTable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadData() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("GPS & Telematics")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Last known vehicle positions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                TextField("Search vehicles…", text: $searchText)
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
            Image(systemName: "location.slash")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No GPS Data")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Vehicle location data will appear here once drivers submit GPS updates from their mobile devices.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Table

    private var locationTable: some View {
        Table(filtered) {
            TableColumn("Vehicle") { row in
                HStack(spacing: 6) {
                    Image(systemName: "truck.box")
                        .foregroundStyle(.blue)
                    Text(row.vehicleName)
                        .lineLimit(1)
                }
            }
            .width(min: 120, ideal: 180)

            TableColumn("Driver") { row in
                Text(row.driverName)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 140)

            TableColumn("Last Updated") { row in
                Text(row.lastUpdated)
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 160)

            TableColumn("Coordinates") { row in
                if let lat = row.latitude, let lon = row.longitude {
                    Text(String(format: "%.4f, %.4f", lat, lon))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 120, ideal: 160)

            TableColumn("Speed") { row in
                if let speed = row.speed {
                    Text(String(format: "%.0f mph", speed))
                        .monospacedDigit()
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(80)

            TableColumn("Status") { row in
                statusIndicator(row.status)
            }
            .width(80)
        }
    }

    // MARK: - Helpers

    private func statusIndicator(_ status: String) -> some View {
        let (color, label): (Color, String) = switch status.lowercased() {
        case "moving": (.green, "Moving")
        case "idle": (.orange, "Idle")
        case "parked", "stopped": (.gray, "Parked")
        default: (.secondary, status.capitalized)
        }
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

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
                vehicles = rows.map { row in
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
                vehicles = []
            } else {
                print("[TelematicsPage] Error: \(error)")
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
