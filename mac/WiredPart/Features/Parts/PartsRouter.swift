import SwiftUI

/// Routes a `/parts/*` path to the appropriate parts page view.
///
/// Mirrors the SettingsRouter pattern: extracts the tab ID from the path
/// and switches to the corresponding page. Falls back to CatalogPage
/// when the tab ID is unrecognized.
struct PartsRouter: View {
    @EnvironmentObject private var appCore: AppCore
    let path: String

    /// Extract the tab ID from the path, e.g. "/parts/catalog" -> "catalog"
    private var tabId: String {
        let components = path.split(separator: "/")
        guard components.count >= 2 else { return "catalog" }
        return String(components.last ?? "catalog")
    }

    var body: some View {
        switch tabId {
        case "categories":
            CategoriesPage()
        case "catalog":
            CatalogPage()
        case "brands":
            BrandsPage()
        case "suppliers":
            SuppliersPage()
        case "pricing":
            PricingPage()
        case "companions":
            CompanionsPage()
        case "forecasting":
            ForecastingPage()
        case "import-export":
            ImportExportPage()
        default:
            CatalogPage()
        }
    }
}
