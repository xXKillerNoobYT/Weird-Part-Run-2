import SwiftUI
import WiredPartCore

struct PeopleRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        switch tabId {
        case "people-employees": IOSEmployeesPage()
        case "people-customers": IOSCustomersPage()
        case "people-contacts": IOSContactsPage()
        case "people-contractors": IOSContractorsPage()
        case "people-teams": IOSTeamsPage()
        case "people-hats": IOSHatsPage()
        case "people-permissions": IOSPermissionsPage()
        default: ErrorStateView(message: "Unknown people page: \(tabId)") { }
        }
    }
}
