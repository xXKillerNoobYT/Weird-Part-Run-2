import SwiftUI

/// Routes a `/people/*` path to the appropriate people page view.
///
/// Extracts the tab ID from the path and switches to the corresponding page.
/// Falls back to EmployeesPage when the tab ID is unrecognized.
struct PeopleRouter: View {
    @EnvironmentObject private var appCore: AppCore
    let path: String

    /// Extract the tab ID from the path, e.g. "/people/customers" -> "customers"
    private var tabId: String {
        let components = path.split(separator: "/")
        guard components.count >= 2 else { return "employees" }
        return String(components.last ?? "employees")
    }

    var body: some View {
        switch tabId {
        case "employees":
            EmployeesPage()
        case "directory":
            EmployeesPage()
        case "customers":
            CustomersPage()
        case "contractors":
            ContactsPage()
        case "contacts":
            ContactsPage()
        case "teams":
            TeamsPage()
        case "hats":
            HatsPage()
        default:
            EmployeesPage()
        }
    }
}
