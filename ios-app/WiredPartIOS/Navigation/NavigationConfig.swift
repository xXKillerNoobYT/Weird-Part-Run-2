import SwiftUI

/// Defines the complete module and tab structure for the WiredPart application.
///
/// Each `AppModule` represents a top-level navigation area (e.g. Dashboard, Parts,
/// Jobs). Each module contains one or more `AppTab` sub-sections that map to
/// specific feature pages via URL-style paths.
///
/// This configuration is shared between macOS (sidebar) and iOS (tab bar)
/// navigation shells. The presentation differs but the data is identical.

// MARK: - Data Structures

struct AppTab: Identifiable, Hashable, Sendable {
    let id: String      // unique key, e.g. "parts-catalog"
    let label: String   // display title
    let icon: String    // SF Symbol name
    let path: String    // route path, e.g. "/parts/catalog"
}

struct AppModule: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let icon: String
    let tabs: [AppTab]

    // Hashable conformance on id only
    static func == (lhs: AppModule, rhs: AppModule) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Module Definitions

/// Complete ordered list of all application modules.
///
/// Tab paths must match the routes handled by `IOSContentRouter`.
let appModules: [AppModule] = [
    AppModule(id: "dashboard", label: "Dashboard", icon: "square.grid.2x2.fill", tabs: [
        AppTab(id: "dashboard-home", label: "Overview", icon: "chart.bar.fill", path: "/dashboard"),
    ]),
    AppModule(id: "parts", label: "Parts", icon: "wrench.and.screwdriver.fill", tabs: [
        AppTab(id: "parts-catalog", label: "Catalog", icon: "list.bullet", path: "/parts/catalog"),
        AppTab(id: "parts-categories", label: "Categories", icon: "folder.fill", path: "/parts/categories"),
        AppTab(id: "parts-brands", label: "Brands", icon: "tag.fill", path: "/parts/brands"),
        AppTab(id: "parts-suppliers", label: "Suppliers", icon: "building.2.fill", path: "/parts/suppliers"),
        AppTab(id: "parts-pricing", label: "Pricing", icon: "dollarsign.circle", path: "/parts/pricing"),
        AppTab(id: "parts-companions", label: "Companions", icon: "link", path: "/parts/companions"),
        AppTab(id: "parts-forecasting", label: "Forecasting", icon: "chart.line.uptrend.xyaxis", path: "/parts/forecasting"),
        AppTab(id: "parts-import-export", label: "Import/Export", icon: "arrow.up.arrow.down", path: "/parts/import-export"),
    ]),
    AppModule(id: "warehouse", label: "Warehouse", icon: "building.fill", tabs: [
        AppTab(id: "warehouse-dashboard", label: "Dashboard", icon: "chart.bar.fill", path: "/warehouse/dashboard"),
        AppTab(id: "warehouse-movements", label: "Movements", icon: "arrow.left.arrow.right", path: "/warehouse/movements"),
        AppTab(id: "warehouse-locations", label: "Locations", icon: "map.fill", path: "/warehouse/locations"),
    ]),
    AppModule(id: "jobs", label: "Jobs", icon: "hammer.fill", tabs: [
        AppTab(id: "jobs-list", label: "All Jobs", icon: "list.bullet", path: "/jobs/list"),
        AppTab(id: "jobs-labor", label: "Labor", icon: "clock.fill", path: "/jobs/labor"),
        AppTab(id: "jobs-reports", label: "Reports", icon: "doc.text.fill", path: "/jobs/reports"),
    ]),
    AppModule(id: "orders", label: "Orders", icon: "cart.fill", tabs: [
        AppTab(id: "orders-jpos", label: "Requests", icon: "doc.badge.plus", path: "/orders/jpos"),
        AppTab(id: "orders-pos", label: "Purchase Orders", icon: "doc.text.fill", path: "/orders/purchase-orders"),
        AppTab(id: "orders-returns", label: "Returns", icon: "arrow.uturn.left", path: "/orders/returns"),
    ]),
    AppModule(id: "fleet", label: "Fleet", icon: "car.fill", tabs: [
        AppTab(id: "fleet-vehicles", label: "Vehicles", icon: "car.fill", path: "/fleet/vehicles"),
        AppTab(id: "fleet-maintenance", label: "Maintenance", icon: "wrench.fill", path: "/fleet/maintenance"),
        AppTab(id: "fleet-mileage", label: "Mileage", icon: "speedometer", path: "/fleet/mileage"),
    ]),
    AppModule(id: "people", label: "People", icon: "person.2.fill", tabs: [
        AppTab(id: "people-employees", label: "Employees", icon: "person.fill", path: "/people/employees"),
        AppTab(id: "people-customers", label: "Customers", icon: "person.crop.circle", path: "/people/customers"),
        AppTab(id: "people-contacts", label: "Contacts", icon: "person.crop.rectangle.fill", path: "/people/contacts"),
    ]),
    AppModule(id: "scheduling", label: "Scheduling", icon: "calendar", tabs: [
        AppTab(id: "scheduling-calendar", label: "Calendar", icon: "calendar", path: "/scheduling/calendar"),
        AppTab(id: "scheduling-dispatch", label: "Dispatch", icon: "paperplane.fill", path: "/scheduling/dispatch"),
    ]),
    AppModule(id: "tools", label: "Tools", icon: "briefcase.fill", tabs: [
        AppTab(id: "tools-registry", label: "Registry", icon: "list.bullet", path: "/tools/registry"),
        AppTab(id: "tools-checkouts", label: "Checkouts", icon: "arrow.right.circle.fill", path: "/tools/checkouts"),
    ]),
    AppModule(id: "notebooks", label: "Notebooks", icon: "note.text", tabs: [
        AppTab(id: "notebooks-all", label: "All Notebooks", icon: "list.bullet", path: "/notebooks/all"),
        AppTab(id: "notebooks-templates", label: "Templates", icon: "doc.on.doc.fill", path: "/notebooks/templates"),
    ]),
    AppModule(id: "reports", label: "Reports", icon: "chart.pie.fill", tabs: [
        AppTab(id: "reports-timesheets", label: "Timesheets", icon: "clock.badge.checkmark", path: "/reports/timesheets"),
        AppTab(id: "reports-spending", label: "Spending", icon: "creditcard.fill", path: "/reports/spending"),
    ]),
    AppModule(id: "chat", label: "Chat", icon: "bubble.left.and.bubble.right.fill", tabs: [
        AppTab(id: "chat-channels", label: "Messages", icon: "bubble.left.fill", path: "/chat/channels"),
        AppTab(id: "chat-questions", label: "Q&A", icon: "questionmark.circle.fill", path: "/chat/questions"),
    ]),
    // Desktop-only pages excluded: Backups, Bootstrap Admin, Key Management,
    // Security Admin, Update Protocol, Data Export, Integrations, Audit Log,
    // Supplier Bridge, Clock-Out Questions
    AppModule(id: "settings", label: "Settings", icon: "gearshape.fill", tabs: [
        AppTab(id: "settings-themes", label: "Themes", icon: "paintpalette.fill", path: "/settings/themes"),
        AppTab(id: "settings-app-config", label: "App Config", icon: "slider.horizontal.3", path: "/settings/app-config"),
        AppTab(id: "settings-company", label: "Company", icon: "building.2.fill", path: "/settings/company"),
        AppTab(id: "settings-pdf", label: "PDF", icon: "doc.fill", path: "/settings/pdf"),
        AppTab(id: "settings-billing", label: "Billing & Pay", icon: "dollarsign.circle.fill", path: "/settings/billing"),
        AppTab(id: "settings-notifications", label: "Notifications", icon: "bell.fill", path: "/settings/notifications"),
        AppTab(id: "settings-sync", label: "Sync", icon: "arrow.triangle.2.circlepath", path: "/settings/sync"),
        AppTab(id: "settings-bluetooth", label: "Bluetooth", icon: "wave.3.right", path: "/settings/bluetooth"),
        AppTab(id: "settings-about", label: "About", icon: "info.circle.fill", path: "/settings/about"),
        AppTab(id: "settings-reset", label: "Database Reset", icon: "arrow.counterclockwise.circle.fill", path: "/settings/reset"),
    ]),
]

// MARK: - Helpers

/// Find a module by its ID.
func findModule(_ id: String) -> AppModule? {
    appModules.first { $0.id == id }
}

/// Modules visible in the primary tab bar (excludes Settings, which is in "More").
var visibleModules: [AppModule] {
    appModules.filter { $0.id != "settings" }
}
