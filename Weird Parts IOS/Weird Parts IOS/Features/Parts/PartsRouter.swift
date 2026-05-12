import SwiftUI
import WiredPartCore

/// Routes a parts tab ID to the appropriate parts page view.
///
/// Each parts sub-page is a standalone SwiftUI view that queries
/// the database directly for its data. Pages cover the full
/// Parts & Inventory domain: categories, catalog, brands, suppliers,
/// pricing, companions, forecasting, and import/export.
struct PartsRouter: View {
    enum OnboardingAction: Equatable {
        case addSupplier
        case importOrAdd
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
        case "parts-categories":
            PartsCategoriesPage()
        case "parts-catalog":
            PartsCatalogPage(openImportOrAddOnAppear: onboardingAction == .importOrAdd)
        case "parts-brands":
            PartsBrandsPage()
        case "parts-suppliers":
            PartsSuppliersPage(addSupplierOnAppear: onboardingAction == .addSupplier)
        case "parts-pricing":
            PartsPricingPage()
        case "parts-companions":
            PartsCompanionsPage()
        case "parts-forecasting":
            PartsForecastingPage()
        case "parts-import-export":
            PartsImportExportPage()
        default:
            Text("Unknown parts page: \(tabId)")
                .foregroundStyle(.secondary)
        }
    }
}
