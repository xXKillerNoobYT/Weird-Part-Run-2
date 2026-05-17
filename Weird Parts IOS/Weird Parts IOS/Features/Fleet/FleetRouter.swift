import SwiftUI
import WiredPartCore

struct FleetRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        routedPage
            .onAppear { postFleetPageContext(active: true) }
            .onDisappear { postFleetPageContext(active: false) }
    }

    @ViewBuilder
    private var routedPage: some View {
        switch tabId {
        case "fleet-vehicles": IOSVehiclesPage()
        case "fleet-dashboard": IOSFleetDashboardPage()
        case "fleet-maintenance": IOSMaintenancePage()
        case "fleet-mileage": IOSMileagePage()
        case "fleet-fuel": IOSFuelPage()
        case "fleet-trailers": IOSTrailersPage()
        case "fleet-inspections": IOSInspectionsPage()
        case "fleet-tracking", "fleet-gps": IOSTelematicsPage()
        case "fleet-my-truck": IOSMyTruckPage()
        case "fleet-trailer-locations": IOSTrailerLocationsPage()
        case "fleet-truck-tools": IOSTruckToolsPage()
        default: Text("Unknown fleet page: \(tabId)").foregroundStyle(.secondary)
        }
    }

    private func postFleetPageContext(active: Bool) {
        guard let descriptor = fleetPageContextDescriptor else { return }
        NotificationCenter.default.post(
            name: active ? descriptor.activeName : descriptor.inactiveName,
            object: nil,
            userInfo: active ? ["context": descriptor.context] : nil
        )
    }

    private var fleetPageContextDescriptor: (activeName: Notification.Name, inactiveName: Notification.Name, context: String)? {
        switch tabId {
        case "fleet-dashboard":
            return (
                .fleetDashboardPageActive,
                .fleetDashboardPageInactive,
                "Fleet Dashboard: read-only overview of vehicle status, open maintenance, inspection readiness, mileage/fuel signals, and fleet quick actions. Available actions: review fleet KPIs, open vehicles, trailers, maintenance, mileage, fuel, inspections, tracking, or My Truck."
            )
        case "fleet-trailers":
            return (
                .fleetTrailersPageActive,
                .fleetTrailersPageInactive,
                "Trailers Page: read-only trailer registry and assignment workflow. Available actions: review trailer availability, status, current location, and trailer details; create/edit actions remain permission-gated."
            )
        case "fleet-maintenance":
            return (
                .fleetMaintenancePageActive,
                .fleetMaintenancePageInactive,
                "Fleet Maintenance Page: read-only maintenance queue, service status, upcoming work, and vehicle maintenance history. Available actions: review due/overdue maintenance and open related vehicle records."
            )
        case "fleet-mileage":
            return (
                .fleetMileagePageActive,
                .fleetMileagePageInactive,
                "Mileage Page: read-only odometer and mileage-log workflow for fleet vehicles. Available actions: review mileage trends, recent odometer entries, and vehicles needing mileage updates."
            )
        case "fleet-fuel":
            return (
                .fleetFuelPageActive,
                .fleetFuelPageInactive,
                "Fuel Page: read-only fuel-log workflow for fleet vehicles. Available actions: review fuel entries, efficiency signals, and vehicles with recent fuel activity."
            )
        case "fleet-inspections":
            return (
                .fleetInspectionsPageActive,
                .fleetInspectionsPageInactive,
                "Inspections Page: read-only pre-trip and vehicle inspection workflow. Available actions: review inspection status, failed checks, and vehicles needing inspection follow-up."
            )
        case "fleet-tracking", "fleet-gps":
            return (
                .fleetTrackingPageActive,
                .fleetTrackingPageInactive,
                "Fleet Tracking Page: read-only telematics and vehicle location workflow. Available actions: review last known locations, GPS/tracking health, and vehicle movement signals."
            )
        case "fleet-my-truck":
            return (
                .fleetMyTruckPageActive,
                .fleetMyTruckPageInactive,
                "My Truck Page: read-only driver vehicle hub for the current user's assigned truck. Available actions: review assigned vehicle, mileage, fuel, inspection, and maintenance prompts."
            )
        default:
            return nil
        }
    }
}
