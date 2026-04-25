import SwiftUI
import WiredPartCore

/// Trailer list page for iOS.
///
/// Displays a searchable list of trailers with trailer number, type,
/// status badge, current job, and assigned vehicle.
/// Uses FleetService.listTrailers(). Supports pull-to-refresh and search.
struct IOSTrailersPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - State

    @State private var trailers: [FleetService.TrailerListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        case createTrailer
        var id: String {
            switch self {
            case .help: "help"
            case .createTrailer: "createTrailer"
            }
        }
    }

    var body: some View {
        trailerList
            .navigationTitle("Trailers")
            .searchable(text: $searchText, prompt: "Search trailers...")
            .refreshable { loadData() }
            .task { loadData() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { loadData() }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        activeSheet = .createTrailer
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add trailer")
                    .requiresPermission("manage_fleet")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .help } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .createTrailer:
                    IOSCreateTrailerSheet(onSaved: { loadData() })
                case .help:
                    PageHelpSheet(
                        title: "Trailers Help",
                        sections: [
                            ("Overview", "This page lists all trailers in the fleet. Each row shows the trailer number, type, status, current job assignment, and the vehicle towing it."),
                            ("Searching", "Use the search bar to filter by trailer number, type, status, job name, or assigned vehicle. Useful when you need to find a specific trailer quickly."),
                            ("Adding a Trailer", "Tap the + button to add a new trailer to the fleet. You need the manage_fleet permission to create trailers."),
                            ("Trailer Detail", "Tap any trailer to open its detail page showing inventory, tools, storage units, and location history."),
                            ("Tips", "Status badges show availability at a glance: green for available, blue for in use, orange for maintenance, and red for retired. Pull down to refresh the list.")
                        ]
                    )
                }
            }
    }

    // MARK: - Trailer List

    @ViewBuilder
    private var trailerList: some View {
        if isLoading {
            ProgressView("Loading trailers...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredTrailers.isEmpty {
            ContentUnavailableView {
                Label("No Trailers", systemImage: "shippingbox")
            } description: {
                Text("No trailers found.")
            }
        } else {
            List(filteredTrailers, id: \.id) { trailer in
                NavigationLink(destination: IOSTrailerDetailPage(trailerId: trailer.id)) {
                    trailerRow(trailer)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredTrailers: [FleetService.TrailerListItem] {
        guard !searchText.isEmpty else { return trailers }
        let query = searchText.lowercased()
        return trailers.filter {
            $0.trailerNumber.lowercased().contains(query) ||
            $0.trailerType.lowercased().contains(query) ||
            $0.status.lowercased().contains(query) ||
            ($0.currentJobName?.lowercased().contains(query) ?? false) ||
            ($0.assignedVehicleName?.lowercased().contains(query) ?? false)
        }
    }

    private func trailerRow(_ trailer: FleetService.TrailerListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.title3)
                .foregroundStyle(.indigo)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(trailer.trailerNumber)
                        .fontWeight(.medium)
                    statusBadge(trailer.status)
                }
                Text(trailer.trailerType.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let job = trailer.currentJobName {
                    Label(job, systemImage: "hammer")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let vehicle = trailer.assignedVehicleName {
                VStack(alignment: .trailing, spacing: 4) {
                    Label {
                        Text(vehicle)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "truck.box")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status.lowercased() {
        case "available": .green
        case "in_use", "in use": .blue
        case "maintenance": .orange
        case "retired": .red
        default: .secondary
        }
        return Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
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
            isLoading = false
            return
        }
        isLoading = trailers.isEmpty
        loadError = nil
        do {
            trailers = try service.listTrailers()
        } catch {
            loadError = userFriendlyError(error, context: "load trailers")
        }
        isLoading = false
    }
}
