import SwiftUI
import WiredPartCore

/// GPS / Telematics list page for iOS.
///
/// Shows the last known position of each vehicle using
/// FleetService.listTelematicsData(). Displays vehicle name,
/// driver, last updated time, and coordinates.
/// Includes an empty state explaining that GPS data comes from mobile devices.
struct IOSTelematicsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var locations: [FleetService.VehicleLocationRow] = []
    @State private var isInitialLoading = true
    @State private var isRefreshing = false
    @State private var hasLoadedOnce = false
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    var body: some View {
        locationList
            .navigationTitle("GPS & Telematics")
            .searchable(text: $searchText, prompt: "Search vehicles...")
            .onChange(of: searchText) { _, _ in postFleetTelematicsContext() }
            .refreshable { loadData() }
            .task { loadData() }
            .onAppear { postFleetTelematicsContext() }
            .onDisappear {
                NotificationCenter.default.post(name: .fleetTelematicsPageInactive, object: nil)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .help } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
                    .accessibilityHint("Opens help for this page.")
                    .accessibilityIdentifier("fleet-telematics-help-button")
                }
            }
            .sheet(item: $activeSheet) { _ in
                PageHelpSheet(
                    title: "GPS & Telematics Help",
                    sections: [
                        ("Overview", "This page shows the last known GPS position of each fleet vehicle. Data comes from driver mobile devices submitting location updates."),
                        ("Status Indicators", "Moving (green) means the vehicle is currently in transit. Idle (orange) means the engine is on but the vehicle is stationary. Parked (gray) means the vehicle has been stopped for a while."),
                        ("Reading Entries", "Each row shows the vehicle name, driver, GPS coordinates, current speed, and the time of the last update. A colored dot on the left indicates the movement status."),
                        ("Tips", "Pull down to refresh for the latest positions. If a vehicle shows no GPS data, the driver may need to enable location services on their device. GPS updates are submitted automatically during active trips.")
                    ]
                )
            }
    }

    // MARK: - Location List

    private var fleetTelematicsContext: String {
        let searchState = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "none" : "active"
        return "page=Fleet Telematics; total_locations=\(locations.count); visible_locations=\(filteredLocations.count); search=\(searchState)"
    }

    private func postFleetTelematicsContext() {
        NotificationCenter.default.post(
            name: .fleetTelematicsPageActive,
            object: nil,
            userInfo: ["context": fleetTelematicsContext]
        )
    }

    @ViewBuilder
    private var locationList: some View {
        Group {
            if isInitialLoading {
                ProgressView("Loading GPS data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if filteredLocations.isEmpty {
                EmptyStateView(
                    icon: "location.slash",
                    title: "No GPS Data",
                    message: "Vehicle location data will appear here once drivers submit GPS updates from their mobile devices."
                )
            } else {
                List(filteredLocations, id: \.id) { location in
                    locationRow(location)
                }
                .listStyle(.insetGrouped)
            }
        }
        .overlay(alignment: .top) {
            refreshingOverlay
        }
    }

    @ViewBuilder
    private var refreshingOverlay: some View {
        if isRefreshing {
            ProgressView()
                .progressViewStyle(.linear)
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.opacity)
                .accessibilityLabel("Refreshing GPS data")
        }
    }

    private var filteredLocations: [FleetService.VehicleLocationRow] {
        guard !searchText.isEmpty else { return locations }
        let query = searchText.lowercased()
        return locations.filter {
            $0.vehicleName.lowercased().contains(query) ||
            $0.driverName.lowercased().contains(query)
        }
    }

    private func locationRow(_ location: FleetService.VehicleLocationRow) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor(location.status).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "location.fill")
                    .font(.body)
                    .foregroundStyle(statusColor(location.status))
            }
            .accessibilityHidden(true)

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
        .rowAccessibility(
            label: "\(location.vehicleName), \(location.status.capitalized)",
            value: locationAccessibilityValue(location),
            id: "fleet-location-row-\(location.id)"
        )
    }

    // MARK: - Helpers

    private func locationAccessibilityValue(_ location: FleetService.VehicleLocationRow) -> String {
        var value = "Driver \(location.driverName)"
        if let speed = location.speed {
            value += ", \(String(format: "%.0f", speed)) miles per hour"
        }
        if !location.lastUpdated.isEmpty {
            value += ", updated \(location.lastUpdated.prefix(16))"
        }
        return value
    }

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
        guard let service = appCore.fleetService else {
            loadError = "Fleet service not available"
            hasLoadedOnce = true
            isInitialLoading = false
            isRefreshing = false
            return
        }

        if hasLoadedOnce {
            isRefreshing = true
        } else {
            isInitialLoading = true
        }

        DispatchQueue.main.async {
            defer {
                self.hasLoadedOnce = true
                self.isInitialLoading = false
                self.isRefreshing = false
            }

            self.loadError = nil
            do {
                self.locations = try service.listTelematicsData()
            } catch {
                self.loadError = userFriendlyError(error, context: "load telematics data")
            }
        }
    }
}
