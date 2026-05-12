import SwiftUI
import WiredPartCore

/// Routes a warehouse tab ID to the appropriate warehouse page view.
///
/// Each warehouse sub-page is a standalone SwiftUI view that queries
/// the database directly for its data. Pages cover the Warehouse domain:
/// dashboard KPIs, stock movements, and inventory by location.
struct WarehouseRouter: View {
    enum OnboardingAction: Equatable {
        case showFloorPlanTutorial
    }

    let tabId: String
    var onboardingAction: OnboardingAction?
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        routedView
    }

    @ViewBuilder
    private var routedView: some View {
        switch tabId {
        case "warehouse-dashboard":
            WarehouseDashboardPage()
        case "warehouse-movements":
            WarehouseMovementsPage()
        case "warehouse-locations":
            WarehouseLocationsPage(showFloorPlanTutorialOnAppear: onboardingAction == .showFloorPlanTutorial)
        case "warehouse-staging":
            IOSStagingPage()
        case "warehouse-receiving":
            IOSReceivingPage()
        case "warehouse-returns":
            IOSWarehouseReturnsPage()
        case "warehouse-audit":
            IOSAuditPage()
        case "warehouse-inventory":
            IOSInventoryGridPage()
        case "warehouse-tools":
            IOSWarehouseToolsPage()
        case "warehouse-network":
            IOSWarehouseNetworkPage()
        case "warehouse-leaderboard":
            IOSWarehouseLeaderboardPage()
        case "warehouse-settings":
            IOSWarehouseSettingsPage()
        case "warehouse-organization":
            IOSOrganizationAuditPage()
        default:
            ErrorStateView(message: "Unknown warehouse page: \(tabId)") { }
        }
    }
}
