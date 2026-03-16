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
        AppTab(id: "warehouse-staging", label: "Staging", icon: "tray.2.fill", path: "/warehouse/staging"),
        AppTab(id: "warehouse-receiving", label: "Receiving", icon: "shippingbox.fill", path: "/warehouse/receiving"),
        AppTab(id: "warehouse-returns", label: "Returns", icon: "arrow.uturn.left", path: "/warehouse/returns"),
        AppTab(id: "warehouse-audit", label: "Audit", icon: "checkmark.shield.fill", path: "/warehouse/audit"),
    ]),
    AppModule(id: "jobs", label: "Jobs", icon: "hammer.fill", tabs: [
        AppTab(id: "jobs-list", label: "All Jobs", icon: "list.bullet", path: "/jobs/list"),
        AppTab(id: "jobs-labor", label: "Labor", icon: "clock.fill", path: "/jobs/labor"),
        AppTab(id: "jobs-reports", label: "Reports", icon: "doc.text.fill", path: "/jobs/reports"),
        AppTab(id: "jobs-clock", label: "Clock", icon: "clock.badge.checkmark.fill", path: "/jobs/clock"),
        AppTab(id: "jobs-detail", label: "Detail", icon: "doc.text.magnifyingglass", path: "/jobs/detail"),
        AppTab(id: "jobs-questionnaire", label: "Questionnaire", icon: "questionmark.circle.fill", path: "/jobs/questionnaire"),
        AppTab(id: "jobs-daily-reports", label: "Daily Reports", icon: "doc.plaintext.fill", path: "/jobs/daily-reports"),
    ]),
    AppModule(id: "orders", label: "Orders", icon: "cart.fill", tabs: [
        AppTab(id: "orders-jpos", label: "Requests", icon: "doc.badge.plus", path: "/orders/jpos"),
        AppTab(id: "orders-pos", label: "Purchase Orders", icon: "doc.text.fill", path: "/orders/purchase-orders"),
        AppTab(id: "orders-returns", label: "Returns", icon: "arrow.uturn.left", path: "/orders/returns"),
        AppTab(id: "orders-procurement", label: "Procurement", icon: "cart.badge.plus", path: "/orders/procurement"),
        AppTab(id: "orders-staging", label: "Staging", icon: "list.clipboard.fill", path: "/orders/staging"),
        AppTab(id: "orders-approvals", label: "Approvals", icon: "checkmark.circle.fill", path: "/orders/approvals"),
    ]),
    AppModule(id: "fleet", label: "Fleet", icon: "car.fill", tabs: [
        AppTab(id: "fleet-vehicles", label: "Vehicles", icon: "car.fill", path: "/fleet/vehicles"),
        AppTab(id: "fleet-maintenance", label: "Maintenance", icon: "wrench.fill", path: "/fleet/maintenance"),
        AppTab(id: "fleet-mileage", label: "Mileage", icon: "speedometer", path: "/fleet/mileage"),
        AppTab(id: "fleet-dashboard", label: "Dashboard", icon: "chart.bar.fill", path: "/fleet/dashboard"),
        AppTab(id: "fleet-fuel", label: "Fuel", icon: "fuelpump.fill", path: "/fleet/fuel"),
        AppTab(id: "fleet-trailers", label: "Trailers", icon: "box.truck.fill", path: "/fleet/trailers"),
        AppTab(id: "fleet-inspections", label: "Inspections", icon: "checklist", path: "/fleet/inspections"),
        AppTab(id: "fleet-gps", label: "GPS", icon: "location.fill", path: "/fleet/gps"),
    ]),
    AppModule(id: "people", label: "People", icon: "person.2.fill", tabs: [
        AppTab(id: "people-employees", label: "Employees", icon: "person.fill", path: "/people/employees"),
        AppTab(id: "people-customers", label: "Customers", icon: "person.crop.circle", path: "/people/customers"),
        AppTab(id: "people-contacts", label: "Contacts", icon: "person.crop.rectangle.fill", path: "/people/contacts"),
        AppTab(id: "people-hats", label: "Hats", icon: "graduationcap.fill", path: "/people/hats"),
        AppTab(id: "people-teams", label: "Teams", icon: "person.3.fill", path: "/people/teams"),
        AppTab(id: "people-contractors", label: "Contractors", icon: "person.badge.shield.checkmark.fill", path: "/people/contractors"),
    ]),
    AppModule(id: "scheduling", label: "Scheduling", icon: "calendar", tabs: [
        AppTab(id: "scheduling-calendar", label: "Calendar", icon: "calendar", path: "/scheduling/calendar"),
        AppTab(id: "scheduling-dispatch", label: "Dispatch", icon: "paperplane.fill", path: "/scheduling/dispatch"),
        AppTab(id: "scheduling-time-off", label: "Time Off", icon: "airplane.departure", path: "/scheduling/time-off"),
        AppTab(id: "scheduling-templates", label: "Templates", icon: "doc.on.doc.fill", path: "/scheduling/templates"),
        AppTab(id: "scheduling-availability", label: "Availability", icon: "clock.fill", path: "/scheduling/availability"),
        AppTab(id: "scheduling-sub-schedule", label: "Sub Schedule", icon: "person.badge.clock", path: "/scheduling/sub-schedule"),
    ]),
    AppModule(id: "tools", label: "Tools", icon: "briefcase.fill", tabs: [
        AppTab(id: "tools-registry", label: "Registry", icon: "list.bullet", path: "/tools/registry"),
        AppTab(id: "tools-checkouts", label: "Checkouts", icon: "arrow.right.circle.fill", path: "/tools/checkouts"),
        AppTab(id: "tools-kits", label: "Kits", icon: "suitcase.fill", path: "/tools/kits"),
        AppTab(id: "tools-dashboard", label: "Dashboard", icon: "chart.bar.fill", path: "/tools/dashboard"),
    ]),
    AppModule(id: "notebooks", label: "Notebooks", icon: "note.text", tabs: [
        AppTab(id: "notebooks-all", label: "All Notebooks", icon: "list.bullet", path: "/notebooks/all"),
        AppTab(id: "notebooks-templates", label: "Templates", icon: "doc.on.doc.fill", path: "/notebooks/templates"),
        AppTab(id: "notebooks-job-notebooks", label: "Job Notebooks", icon: "book.closed.fill", path: "/notebooks/job-notebooks"),
    ]),
    AppModule(id: "reports", label: "Reports", icon: "chart.pie.fill", tabs: [
        AppTab(id: "reports-timesheets", label: "Timesheets", icon: "clock.badge.checkmark", path: "/reports/timesheets"),
        AppTab(id: "reports-spending", label: "Spending", icon: "creditcard.fill", path: "/reports/spending"),
        AppTab(id: "reports-daily-summary", label: "Daily Summary", icon: "chart.bar.fill", path: "/reports/daily-summary"),
        AppTab(id: "reports-profitability", label: "Profitability", icon: "chart.pie.fill", path: "/reports/profitability"),
        AppTab(id: "reports-pre-billing", label: "Pre-Billing", icon: "doc.text.fill", path: "/reports/pre-billing"),
        AppTab(id: "reports-bookkeeper", label: "Bookkeeper", icon: "books.vertical.fill", path: "/reports/bookkeeper"),
    ]),
    AppModule(id: "chat", label: "Chat", icon: "bubble.left.and.bubble.right.fill", tabs: [
        AppTab(id: "chat-channels", label: "Messages", icon: "bubble.left.fill", path: "/chat/channels"),
        AppTab(id: "chat-questions", label: "Q&A", icon: "questionmark.circle.fill", path: "/chat/questions"),
    ]),
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
        AppTab(id: "settings-clockout", label: "Clock-Out Questions", icon: "questionmark.circle.fill", path: "/settings/clockout"),
        AppTab(id: "settings-backups", label: "Backups", icon: "externaldrive.fill", path: "/settings/backups"),
        AppTab(id: "settings-bootstrap", label: "Bootstrap", icon: "desktopcomputer", path: "/settings/bootstrap"),
        AppTab(id: "settings-keys", label: "Key Management", icon: "key.fill", path: "/settings/keys"),
        AppTab(id: "settings-security", label: "Security", icon: "lock.shield.fill", path: "/settings/security"),
        AppTab(id: "settings-updates", label: "Updates", icon: "arrow.down.circle.fill", path: "/settings/updates"),
        AppTab(id: "settings-export", label: "Data Export", icon: "square.and.arrow.up.fill", path: "/settings/export"),
        AppTab(id: "settings-integrations", label: "Integrations", icon: "puzzlepiece.extension.fill", path: "/settings/integrations"),
        AppTab(id: "settings-audit", label: "Audit Log", icon: "list.bullet.clipboard.fill", path: "/settings/audit"),
        AppTab(id: "settings-supplier-bridge", label: "Supplier Bridge", icon: "link.circle.fill", path: "/settings/supplier-bridge"),
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
