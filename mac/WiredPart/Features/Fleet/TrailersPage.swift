import SwiftUI
import WiredPartCore

/// Trailers list page.
///
/// Displays a searchable, sortable table of all trailers with number, type,
/// status, current job, and assigned vehicle columns. Status badge uses
/// color coding for availability.
struct TrailersPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var trailers: [FleetService.TrailerListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\FleetService.TrailerListItem.trailerNumber)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tableContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { load() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Trailers")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(trailers.count) trailer\(trailers.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField("Search trailers...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { load() }

            Button {
                load()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Table

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("Loading trailers...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if trailers.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No trailers found")
                    .font(.headline)
                Text("Trailers will appear here once added.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedTrailers, sortOrder: $sortOrder) {
                TableColumn("Number", value: \.trailerNumber) { trailer in
                    Text(trailer.trailerNumber)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }
                .width(min: 80, ideal: 110)

                TableColumn("Type", value: \.trailerType) { trailer in
                    Text(trailer.trailerType.capitalized)
                }
                .width(min: 80, ideal: 120)

                TableColumn("Status", value: \.status) { trailer in
                    statusBadge(trailer.status)
                }
                .width(min: 80, ideal: 110)

                TableColumn("Job") { (trailer: FleetService.TrailerListItem) in
                    Text(trailer.currentJobName ?? "-")
                        .font(.callout)
                        .foregroundStyle(trailer.currentJobName != nil ? .primary : .secondary)
                }
                .width(min: 120, ideal: 180)

                TableColumn("Vehicle") { (trailer: FleetService.TrailerListItem) in
                    Text(trailer.assignedVehicleName ?? "-")
                        .font(.callout)
                        .foregroundStyle(trailer.assignedVehicleName != nil ? .primary : .secondary)
                }
                .width(min: 120, ideal: 160)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedTrailers: [FleetService.TrailerListItem] {
        trailers.sorted(using: sortOrder)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "available": .green
        case "in_use", "deployed": .blue
        case "maintenance": .orange
        case "decommissioned": .red
        default: .secondary
        }
        return Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(.caption, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func load() {
        guard let db = appCore.db else { return }
        let service = FleetService(db: db)
        isLoading = true
        do {
            let allTrailers = try service.listTrailers()
            // Client-side search filter
            if searchText.isEmpty {
                trailers = allTrailers
            } else {
                let query = searchText.lowercased()
                trailers = allTrailers.filter {
                    $0.trailerNumber.lowercased().contains(query) ||
                    $0.trailerType.lowercased().contains(query) ||
                    ($0.currentJobName?.lowercased().contains(query) ?? false) ||
                    ($0.assignedVehicleName?.lowercased().contains(query) ?? false)
                }
            }
        } catch {
            print("[TrailersPage] Load error: \(error)")
        }
        isLoading = false
    }
}
