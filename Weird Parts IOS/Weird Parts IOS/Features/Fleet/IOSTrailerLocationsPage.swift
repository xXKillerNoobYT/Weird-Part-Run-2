import SwiftUI
import WiredPartCore

/// Page showing where trailers are located — job sites, warehouse, yard, etc.
struct IOSTrailerLocationsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var trailers: [FleetService.TrailerListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading trailer locations...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if filteredTrailers.isEmpty {
                EmptyStateView(
                    icon: "box.truck.fill",
                    title: "No Trailers",
                    message: searchText.isEmpty ? "No trailers in the system." : "No trailers match your search."
                )
            } else {
                trailerList
            }
        }
        .navigationTitle("Trailer Locations")
        .searchable(text: $searchText, prompt: "Search trailers...")
        .refreshable { loadData() }
        .task { loadData() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(
                title: "Trailer Locations Help",
                sections: [
                    ("Overview", "This page shows where every trailer in the fleet is located right now. Trailers are grouped into two sections: those currently at job sites and those in the yard or unassigned."),
                    ("At Job Sites", "Trailers assigned to a job appear under the At Job Sites section with the job name and the tow vehicle shown. This helps dispatchers know which trailers are deployed."),
                    ("Yard / Unassigned", "Trailers not currently on a job appear in this section. These are available for assignment to upcoming jobs or maintenance."),
                    ("Tips", "Use the search bar to find a trailer by number, type, job name, or tow vehicle. Pull down to refresh locations. If a trailer shows the wrong location, update it from the trailer detail page.")
                ]
            )
        }
    }

    private var trailerList: some View {
        List {
            // Group by status/location
            let atJob = filteredTrailers.filter { $0.currentJobName != nil }
            let unassigned = filteredTrailers.filter { $0.currentJobName == nil }

            if !atJob.isEmpty {
                Section("At Job Sites (\(atJob.count))") {
                    ForEach(atJob) { trailer in
                        trailerRow(trailer)
                    }
                }
            }

            if !unassigned.isEmpty {
                Section("Yard / Unassigned (\(unassigned.count))") {
                    ForEach(unassigned) { trailer in
                        trailerRow(trailer)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func trailerRow(_ trailer: FleetService.TrailerListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "box.truck.fill")
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(trailer.trailerNumber)
                    .fontWeight(.medium)
                Text(trailer.trailerType.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                StatusBadge(text: trailer.status.capitalized, color: statusColor(trailer.status))
                if let job = trailer.currentJobName {
                    Text(job)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let vehicle = trailer.assignedVehicleName {
                    Text(vehicle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var filteredTrailers: [FleetService.TrailerListItem] {
        guard !searchText.isEmpty else { return trailers }
        let query = searchText.lowercased()
        return trailers.filter {
            $0.trailerNumber.lowercased().contains(query) ||
            $0.trailerType.lowercased().contains(query) ||
            ($0.currentJobName?.lowercased().contains(query) ?? false) ||
            ($0.assignedVehicleName?.lowercased().contains(query) ?? false)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "available": return .green
        case "in_use", "deployed": return .blue
        case "maintenance": return .orange
        default: return .secondary
        }
    }

    private func loadData() {
        guard let fleet = appCore.fleetService else {
            loadError = "Fleet service not available"
            isLoading = false
            return
        }
        isLoading = trailers.isEmpty
        loadError = nil
        do {
            trailers = try fleet.listTrailers()
        } catch {
            loadError = userFriendlyError(error, context: "load trailer locations")
        }
        isLoading = false
    }
}
