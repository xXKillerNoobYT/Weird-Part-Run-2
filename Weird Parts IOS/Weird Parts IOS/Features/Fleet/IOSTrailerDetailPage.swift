import SwiftUI
import WiredPartCore

/// Trailer detail page showing trailer information and current assignment.
struct IOSTrailerDetailPage: View {
    @EnvironmentObject private var appCore: AppCore
    let trailer: FleetService.TrailerListItem

    var body: some View {
        List {
            Section("Trailer Info") {
                detailRow("Number", trailer.trailerNumber)
                detailRow("Type", trailer.trailerType.capitalized)
                detailRow("Status", trailer.status.capitalized)
            }

            Section("Assignment") {
                if let job = trailer.currentJobName {
                    detailRow("Current Job", job)
                } else {
                    Text("Not assigned to a job")
                        .foregroundStyle(.secondary)
                }

                if let vehicle = trailer.assignedVehicleName {
                    detailRow("Assigned Vehicle", vehicle)
                } else {
                    Text("Not assigned to a vehicle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Trailer \(trailer.trailerNumber)")
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}
