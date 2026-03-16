import SwiftUI
import WiredPartCore

struct FleetRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        switch tabId {
        case "fleet-vehicles": IOSVehiclesPage()
        case "fleet-dashboard": IOSFleetDashboardPage()
        case "fleet-maintenance": IOSMaintenancePage()
        case "fleet-mileage": IOSMileagePage()
        case "fleet-fuel": IOSFuelPage()
        case "fleet-trailers": IOSTrailersPage()
        case "fleet-inspections": IOSInspectionsPage()
        case "fleet-gps": IOSTelematicsPage()
        default: Text("Unknown fleet page: \(tabId)").foregroundStyle(.secondary)
        }
    }
}
