import SwiftUI
import WiredPartCore

struct FleetRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        switch tabId {
        case "fleet-vehicles": IOSVehiclesPage()
        case "fleet-maintenance": IOSMaintenancePage()
        case "fleet-mileage": IOSMileagePage()
        default: Text("Unknown fleet page: \(tabId)").foregroundStyle(.secondary)
        }
    }
}
