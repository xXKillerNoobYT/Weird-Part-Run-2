import SwiftUI
import WiredPartCore

/// Vehicles list page for iOS.
///
/// Displays a searchable list of fleet vehicles with vehicle number, name,
/// type, status badge, and assigned user. Supports pull-to-refresh and
/// status-based filtering.
struct IOSVehiclesPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var vehicles: [FleetService.VehicleListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter = "all"
    @State private var showCreateVehicle = false
    @State private var loadError: String?

    private let statusOptions = ["all", "active", "inactive", "maintenance", "retired"]

    var body: some View {
        VStack(spacing: 0) {
            statusPicker
            vehicleList
        }
        .navigationTitle("Vehicles")
        .searchable(text: $searchText, prompt: "Search vehicles...")
        .onChange(of: searchText) { loadData() }
        .refreshable { loadData() }
        .task { loadData() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateVehicle = true
                } label: {
                    Image(systemName: "plus")
                }
                .requiresPermission("manage_fleet")
            }
        }
        .sheet(isPresented: $showCreateVehicle) {
            IOSCreateVehicleSheet(onSaved: { loadData() })
        }
    }

    // MARK: - Status Picker

    private var statusPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statusOptions, id: \.self) { status in
                    Button {
                        statusFilter = status
                        loadData()
                    } label: {
                        Text(status == "all" ? "All" : status.capitalized)
                            .font(.caption)
                            .fontWeight(statusFilter == status ? .bold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(statusFilter == status ? Color.accentColor : Color.secondary.opacity(0.2))
                            )
                            .foregroundStyle(statusFilter == status ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Vehicle List

    @ViewBuilder
    private var vehicleList: some View {
        if isLoading {
            ProgressView("Loading vehicles...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredVehicles.isEmpty {
            EmptyStateView(
                icon: "car",
                title: "No Vehicles",
                message: searchText.isEmpty ? "Add your first vehicle to get started." : "No vehicles match your criteria.",
                actionLabel: searchText.isEmpty ? "Add Vehicle" : nil
            ) {
                showCreateVehicle = true
            }
        } else {
            List(filteredVehicles, id: \.id) { vehicle in
                NavigationLink(destination: IOSVehicleDetailPage(vehicleId: vehicle.id)) {
                    vehicleRow(vehicle)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredVehicles: [FleetService.VehicleListItem] {
        guard !searchText.isEmpty else { return vehicles }
        let query = searchText.lowercased()
        return vehicles.filter {
            $0.vehicleName.lowercased().contains(query) ||
            $0.vehicleNumber.lowercased().contains(query) ||
            ($0.make?.lowercased().contains(query) ?? false) ||
            ($0.model?.lowercased().contains(query) ?? false) ||
            ($0.assignedUserName?.lowercased().contains(query) ?? false)
        }
    }

    private func vehicleRow(_ vehicle: FleetService.VehicleListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: vehicleIcon(vehicle.vehicleType))
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(vehicle.vehicleNumber)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    typeBadge(vehicle.vehicleType)
                }
                Text(vehicle.vehicleName)
                    .fontWeight(.medium)
                if let make = vehicle.make, let model = vehicle.model {
                    HStack(spacing: 4) {
                        Text("\(make) \(model)")
                        if let year = vehicle.year {
                            Text("(\(String(year)))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(vehicle.status)
                if let user = vehicle.assignedUserName {
                    Label(user, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let odo = vehicle.currentOdometer {
                    Text("\(odo.formatted()) mi")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(vehicle.vehicleName), \(vehicle.vehicleNumber), \(vehicle.vehicleType), status \(vehicle.status)")
    }

    // MARK: - Helpers

    private func vehicleIcon(_ type: String) -> String {
        switch type {
        case "truck": return "truck.box"
        case "van": return "bus"
        case "car": return "car"
        case "trailer": return "shippingbox"
        default: return "car"
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "active": .green
        case "inactive": .secondary
        case "maintenance": .orange
        case "retired": .red
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func typeBadge(_ type: String) -> some View {
        Text(type.capitalized)
            .font(.caption2)
            .foregroundStyle(.blue)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.fleetService else { return }
        isLoading = vehicles.isEmpty
        loadError = nil
        do {
            vehicles = try service.listVehicles(
                status: statusFilter == "all" ? nil : statusFilter
            )
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
