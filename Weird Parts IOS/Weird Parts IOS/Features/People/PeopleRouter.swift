import SwiftUI
import WiredPartCore

struct PeopleRouter: View {
    enum OnboardingAction: Equatable {
        case addPerson
    }

    let tabId: String
    var onboardingAction: OnboardingAction?
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        switch tabId {
        case "people-dashboard": IOSPeopleDashboardPage()
        case "people-employees": IOSEmployeesPage(addPersonOnAppear: onboardingAction == .addPerson)
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
