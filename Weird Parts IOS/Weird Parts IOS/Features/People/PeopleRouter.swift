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
        case "people-hats": IOSHatsPage()
        case "people-teams": IOSTeamsPage()
        case "people-contractors": IOSContractorsPage()
        default: Text("Unknown people page: \(tabId)").foregroundStyle(.secondary)
        }
    }
}
