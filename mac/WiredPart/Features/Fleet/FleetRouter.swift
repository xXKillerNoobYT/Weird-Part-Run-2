import SwiftUI

/// Routes a `/fleet/*` path to the appropriate fleet page view.
///
/// Extracts the tab ID from the path and switches to the corresponding page.
/// Falls back to VehiclesPage when the tab ID is unrecognized.
struct FleetRouter: View {
    @EnvironmentObject private var appCore: AppCore
    let path: String

    /// Extract the tab ID from the path, e.g. "/fleet/maintenance" -> "maintenance"
    private var tabId: String {
        let components = path.split(separator: "/")
        guard components.count >= 2 else { return "vehicles" }
        return String(components.last ?? "vehicles")
    }

    var body: some View {
        switch tabId {
        case "fleet", "vehicles":
            VehiclesPage()
        case "maintenance":
            MaintenancePage()
        case "mileage":
            MileagePage()
        case "fuel":
            FuelPage()
        case "trailers":
            TrailersPage()
        case "inspections":
            PlaceholderView(path: path)
        case "gps":
            PlaceholderView(path: path)
        case "fleet-dashboard":
            FleetDashboardPage()
        default:
            VehiclesPage()
        }
    }
}
