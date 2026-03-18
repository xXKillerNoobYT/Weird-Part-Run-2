import SwiftUI
import WiredPartCore

struct PeopleRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        switch tabId {
        case "people-customers": IOSCustomersPage()
        case "people-contacts": IOSContactsPage()
        case "people-contractors": IOSContractorsPage()
        case "people-teams": IOSTeamsPage()
        // Legacy fallbacks — these pages now live in Office
        case "people-employees": IOSEmployeesPage()
        case "people-hats": IOSHatsPage()
        case "people-permissions": IOSPermissionsPage()
        default: Text("Unknown people page: \(tabId)").foregroundStyle(.secondary)
        }
    }
}
