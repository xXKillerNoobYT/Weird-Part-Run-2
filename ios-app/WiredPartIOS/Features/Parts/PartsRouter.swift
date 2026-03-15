import SwiftUI
import WiredPartCore

/// Routes a parts tab ID to the appropriate parts page view.
///
/// Each parts sub-page is a standalone SwiftUI view that queries
/// the database directly for its data. Pages cover the full
/// Parts & Inventory domain: categories, catalog, brands, suppliers,
/// pricing, companions, forecasting, and import/export.
struct PartsRouter: View {
    let tabId: String
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
            PartsCatalogPage()
        case "parts-brands":
            PartsBrandsPage()
        case "parts-suppliers":
            PartsSuppliersPage()
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
