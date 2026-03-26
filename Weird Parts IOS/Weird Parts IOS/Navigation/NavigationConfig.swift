import SwiftUI

/// Defines the complete module and tab structure for the WiredPart iOS application.
///
/// Each `AppModule` represents a top-level navigation area (e.g. Dashboard, Parts,
/// Jobs). Each module contains one or more `AppTab` sub-sections that map to
/// specific feature pages via URL-style paths.
///
/// Modules and tabs support optional `permission` gating. When a permission string
/// is set, the module/tab is only visible to users who have that permission.
/// A `nil` permission means always visible (e.g. Dashboard, Notebooks).

// MARK: - Data Structures

struct AppTab: Identifiable, Hashable, Sendable {
    let id: String          // unique key, e.g. "parts-catalog"
    let label: String       // display title
    let icon: String        // SF Symbol name
    let path: String        // route path, e.g. "/parts/catalog"
    let permission: String? // required permission, nil = unrestricted

    init(id: String, label: String, icon: String, path: String, permission: String? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
        self.path = path
        self.permission = permission
    }
}

struct AppModule: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let icon: String
    let tabs: [AppTab]
    let permission: String? // required permission, nil = unrestricted

    init(id: String, label: String, icon: String, tabs: [AppTab], permission: String? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
        self.tabs = tabs
        self.permission = permission
    }

    // Hashable conformance on id only
    static func == (lhs: AppModule, rhs: AppModule) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Module Definitions

/// Complete ordered list of all application modules.
///
/// Ordered by usage frequency: daily use → work tools → management.
/// Tab paths must match the routes handled by `IOSContentRouter`.
/// Permission strings match the keys from `AuthService.defaultPermissionMap()`.
let appModules: [AppModule] = [

    // ── DAILY USE (everyone) ──────────────────────────────────────────

    // 1. Dashboard — first thing every morning
    AppModule(id: "dashboard", label: "Dashboard", icon: "square.grid.2x2.fill", tabs: [
        AppTab(id: "dashboard-home", label: "Overview", icon: "chart.bar.fill", path: "/dashboard"),
        AppTab(id: "dashboard-clock", label: "Clock", icon: "clock.badge.checkmark.fill", path: "/dashboard/clock", permission: "clock_in_out"),
        AppTab(id: "dashboard-report", label: "Daily Report", icon: "doc.text.magnifyingglass", path: "/dashboard/report"),
        AppTab(id: "dashboard-scanner", label: "QR Scanner", icon: "qrcode.viewfinder", path: "/dashboard/scanner"),
    ]),
    // 2. Jobs — what you work on all day
    AppModule(id: "jobs", label: "Jobs", icon: "hammer.fill", tabs: [
        AppTab(id: "jobs-list", label: "All Jobs", icon: "list.bullet", path: "/jobs/list"),
        AppTab(id: "jobs-labor", label: "Labor", icon: "clock.fill", path: "/jobs/labor", permission: "view_labor"),
        AppTab(id: "jobs-reports", label: "Reports", icon: "doc.text.fill", path: "/jobs/reports"),
    ], permission: "view_jobs"),
    // 3. Chat — constant communication
    AppModule(id: "chat", label: "Chat", icon: "bubble.left.and.bubble.right.fill", tabs: [
        AppTab(id: "chat-channels", label: "Messages", icon: "bubble.left.fill", path: "/chat/channels"),
        AppTab(id: "chat-questions", label: "Q&A", icon: "questionmark.circle.fill", path: "/chat/questions"),
        AppTab(id: "chat-rfis", label: "RFIs", icon: "doc.questionmark.fill", path: "/chat/rfis", permission: "manage_jobs"),
    ], permission: "view_chat"),
    // 4. Scheduling — check schedule, dispatch, time off
    AppModule(id: "scheduling", label: "Scheduling", icon: "calendar", tabs: [
        AppTab(id: "scheduling-calendar", label: "Calendar", icon: "calendar", path: "/scheduling/calendar"),
        AppTab(id: "scheduling-dispatch", label: "Dispatch", icon: "paperplane.fill", path: "/scheduling/dispatch", permission: "manage_dispatch"),
        AppTab(id: "scheduling-time-off", label: "Time Off", icon: "airplane.departure", path: "/scheduling/time-off"),
        AppTab(id: "scheduling-templates", label: "Templates", icon: "doc.on.doc.fill", path: "/scheduling/templates", permission: "manage_scheduling"),
        AppTab(id: "scheduling-availability", label: "Availability", icon: "clock.fill", path: "/scheduling/availability"),
        AppTab(id: "scheduling-sub-schedule", label: "Sub Schedule", icon: "person.badge.clock", path: "/scheduling/sub-schedule", permission: "manage_subcontractors"),
        AppTab(id: "scheduling-pipeline", label: "Pipeline", icon: "chart.bar.doc.horizontal", path: "/scheduling/pipeline", permission: "manage_dispatch"),
        AppTab(id: "scheduling-long-pipeline", label: "Long-Term", icon: "chart.bar.xaxis", path: "/scheduling/long-pipeline", permission: "manage_dispatch"),
        AppTab(id: "scheduling-config", label: "Config", icon: "gearshape.fill", path: "/scheduling/config", permission: "manage_scheduling"),
    ], permission: "view_scheduling"),

    // ── WORK TOOLS (role-based) ───────────────────────────────────────

    // 5. Warehouse — movements, receiving, staging
    AppModule(id: "warehouse", label: "Warehouse", icon: "building.fill", tabs: [
        AppTab(id: "warehouse-dashboard", label: "Dashboard", icon: "chart.bar.fill", path: "/warehouse/dashboard"),
        AppTab(id: "warehouse-receiving", label: "Sorting", icon: "shippingbox.fill", path: "/warehouse/receiving"),
        AppTab(id: "warehouse-staging", label: "Staging", icon: "tray.2.fill", path: "/warehouse/staging"),
        AppTab(id: "warehouse-movements", label: "Movements", icon: "arrow.left.arrow.right", path: "/warehouse/movements"),
        AppTab(id: "warehouse-inventory", label: "Inventory", icon: "square.grid.3x3.fill", path: "/warehouse/inventory"),
        AppTab(id: "warehouse-locations", label: "Locations", icon: "map.fill", path: "/warehouse/locations"),
        AppTab(id: "warehouse-audit", label: "Audit", icon: "checkmark.shield.fill", path: "/warehouse/audit", permission: "perform_audit"),
        AppTab(id: "warehouse-returns", label: "Returns", icon: "arrow.uturn.left", path: "/warehouse/returns"),
        AppTab(id: "warehouse-tools", label: "Tools", icon: "wrench.and.screwdriver.fill", path: "/warehouse/tools"),
        AppTab(id: "warehouse-leaderboard", label: "Leaderboard", icon: "trophy.fill", path: "/warehouse/leaderboard", permission: "manage_warehouse"),
        AppTab(id: "warehouse-network", label: "Network", icon: "antenna.radiowaves.left.and.right", path: "/warehouse/network", permission: "manage_devices"),
        AppTab(id: "warehouse-settings", label: "Settings", icon: "gearshape.fill", path: "/warehouse/settings", permission: "manage_warehouse"),
    ], permission: "view_warehouse"),
    // 6. Orders — JPOs, POs, procurement
    AppModule(id: "orders", label: "Orders", icon: "cart.fill", tabs: [
        AppTab(id: "orders-jpos", label: "Job Orders", icon: "doc.badge.plus", path: "/orders/jpos"),
        AppTab(id: "orders-pos", label: "Purchase Orders", icon: "doc.text.fill", path: "/orders/purchase-orders"),
        AppTab(id: "orders-procurement", label: "Procurement", icon: "cart.badge.plus", path: "/orders/procurement"),
        AppTab(id: "orders-parts", label: "Parts Mgmt", icon: "list.bullet.rectangle.portrait", path: "/orders/parts"),
        AppTab(id: "orders-staging", label: "Stage Planner", icon: "list.clipboard.fill", path: "/orders/staging"),
        AppTab(id: "orders-approvals", label: "Approvals", icon: "checkmark.circle.fill", path: "/orders/approvals"),
        AppTab(id: "orders-returns", label: "Returns", icon: "arrow.uturn.left", path: "/orders/returns"),
        AppTab(id: "orders-wishlist", label: "Wishlist", icon: "heart.text.clipboard", path: "/orders/wishlist"),
    ], permission: "view_orders"),
    // 7. Fleet — trucks, trailers, my truck
    AppModule(id: "fleet", label: "Fleet", icon: "car.fill", tabs: [
        AppTab(id: "fleet-dashboard", label: "Dashboard", icon: "chart.bar.fill", path: "/fleet/dashboard"),
        AppTab(id: "fleet-vehicles", label: "Vehicles", icon: "car.fill", path: "/fleet/vehicles"),
        AppTab(id: "fleet-trailers", label: "Trailers", icon: "box.truck.fill", path: "/fleet/trailers"),
        AppTab(id: "fleet-maintenance", label: "Maintenance", icon: "wrench.fill", path: "/fleet/maintenance"),
        AppTab(id: "fleet-mileage", label: "Mileage", icon: "speedometer", path: "/fleet/mileage"),
        AppTab(id: "fleet-fuel", label: "Fuel", icon: "fuelpump.fill", path: "/fleet/fuel"),
        AppTab(id: "fleet-inspections", label: "Inspections", icon: "checklist", path: "/fleet/inspections"),
        AppTab(id: "fleet-tracking", label: "Tracking", icon: "location.fill", path: "/fleet/tracking"),
        AppTab(id: "fleet-my-truck", label: "My Truck", icon: "car.rear.fill", path: "/fleet/my-truck"),
    ], permission: "view_fleet"),
    // 8. Tools — registry, checkouts, kits
    AppModule(id: "tools", label: "Tools", icon: "wrench.adjustable.fill", tabs: [
        AppTab(id: "tools-dashboard", label: "Dashboard", icon: "chart.bar.fill", path: "/tools/dashboard"),
        AppTab(id: "tools-registry", label: "All Tools", icon: "list.bullet", path: "/tools/registry"),
        AppTab(id: "tools-checkouts", label: "Checkouts", icon: "arrow.right.circle.fill", path: "/tools/checkouts"),
        AppTab(id: "tools-kits", label: "Kits", icon: "suitcase.fill", path: "/tools/kits"),
        AppTab(id: "tools-maintenance", label: "Maintenance", icon: "wrench.adjustable.fill", path: "/tools/maintenance"),
        AppTab(id: "tools-admin", label: "Admin", icon: "person.badge.key.fill", path: "/tools/admin", permission: "manage_tools"),
    ], permission: "view_tools"),
    // 9. Notebooks — job notes, templates
    AppModule(id: "notebooks", label: "Notebooks", icon: "note.text", tabs: [
        AppTab(id: "notebooks-all", label: "All Notebooks", icon: "list.bullet", path: "/notebooks/all"),
        AppTab(id: "notebooks-templates", label: "Templates", icon: "doc.on.doc.fill", path: "/notebooks/templates", permission: "manage_templates"),
        AppTab(id: "notebooks-job-notebooks", label: "Job Notebooks", icon: "book.closed.fill", path: "/notebooks/job-notebooks"),
    ]),

    // ── MANAGEMENT (office/admin) ─────────────────────────────────────

    // 10. Parts — catalog, pricing, forecasting
    AppModule(id: "parts", label: "Parts", icon: "wrench.and.screwdriver.fill", tabs: [
        AppTab(id: "parts-catalog", label: "Catalog", icon: "list.bullet", path: "/parts/catalog"),
        AppTab(id: "parts-categories", label: "Categories", icon: "folder.fill", path: "/parts/categories"),
        AppTab(id: "parts-brands", label: "Brands", icon: "tag.fill", path: "/parts/brands"),
        AppTab(id: "parts-suppliers", label: "Suppliers", icon: "building.2.fill", path: "/parts/suppliers"),
        AppTab(id: "parts-pricing", label: "Pricing", icon: "dollarsign.circle", path: "/parts/pricing", permission: "show_dollar_values"),
        AppTab(id: "parts-companions", label: "Companions", icon: "link", path: "/parts/companions"),
        AppTab(id: "parts-forecasting", label: "Forecasting", icon: "chart.line.uptrend.xyaxis", path: "/parts/forecasting"),
        AppTab(id: "parts-import-export", label: "Import/Export", icon: "arrow.up.arrow.down", path: "/parts/import-export"),
    ], permission: "view_parts_catalog"),
    // 11. People — customers, employees, contacts
    AppModule(id: "people", label: "People", icon: "person.2.fill", tabs: [
        AppTab(id: "people-dashboard", label: "Dashboard", icon: "chart.bar.fill", path: "/people/dashboard"),
        AppTab(id: "people-employees", label: "Employees", icon: "person.fill", path: "/people/employees", permission: "view_people"),
        AppTab(id: "people-customers", label: "Customers", icon: "person.crop.circle", path: "/people/customers", permission: "view_customers"),
        AppTab(id: "people-contacts", label: "Contacts", icon: "person.crop.rectangle.fill", path: "/people/contacts"),
        AppTab(id: "people-contractors", label: "Contractors", icon: "person.badge.shield.checkmark.fill", path: "/people/contractors", permission: "view_contractors"),
        AppTab(id: "people-teams", label: "Teams", icon: "person.3.fill", path: "/people/teams"),
        AppTab(id: "people-hats", label: "Hats & Roles", icon: "graduationcap.fill", path: "/people/hats", permission: "manage_people"),
        AppTab(id: "people-permissions", label: "Permissions", icon: "lock.shield.fill", path: "/people/permissions", permission: "manage_people"),
    ], permission: "view_people"),
    // 12. Office — dashboard, approvals, pipeline, teams, reports
    AppModule(id: "office", label: "Office", icon: "briefcase.fill", tabs: [
        AppTab(id: "office-dashboard", label: "Dashboard", icon: "gauge.with.dots.needle.50percent", path: "/office/dashboard", permission: "manage_jobs"),
        AppTab(id: "office-approvals", label: "Approvals", icon: "checkmark.seal.fill", path: "/office/approvals", permission: "manage_jobs"),
        AppTab(id: "office-manage-jobs", label: "Manage Jobs", icon: "hammer.fill", path: "/office/manage-jobs", permission: "manage_jobs"),
        AppTab(id: "office-warehouse-exec", label: "Warehouse", icon: "building.fill", path: "/office/warehouse-exec", permission: "manage_warehouse"),
        AppTab(id: "office-estimation-settings", label: "Estimation", icon: "chart.bar.doc.horizontal", path: "/office/estimation-settings", permission: "manage_jobs"),
        AppTab(id: "office-pipeline", label: "Pipeline", icon: "chart.bar.xaxis", path: "/office/pipeline", permission: "manage_jobs"),
        AppTab(id: "office-spending", label: "Spending", icon: "dollarsign.circle.fill", path: "/office/spending", permission: "show_dollar_values"),
        AppTab(id: "office-teams", label: "Teams", icon: "person.3.fill", path: "/office/teams"),
        AppTab(id: "office-reports", label: "Reports", icon: "chart.pie.fill", path: "/office/reports", permission: "view_reports"),
    ], permission: "manage_jobs"),
    // 13. Settings — app config, security
    AppModule(id: "settings", label: "Settings", icon: "gearshape.fill", tabs: [
        AppTab(id: "settings-themes", label: "Themes", icon: "paintpalette.fill", path: "/settings/themes"),
        AppTab(id: "settings-app-config", label: "App Config", icon: "slider.horizontal.3", path: "/settings/app-config"),
        AppTab(id: "settings-notifications", label: "Notifications", icon: "bell.fill", path: "/settings/notifications"),
        AppTab(id: "settings-sync", label: "Sync", icon: "arrow.triangle.2.circlepath", path: "/settings/sync"),
        AppTab(id: "settings-security", label: "Security", icon: "lock.shield.fill", path: "/settings/security", permission: "manage_devices"),
        AppTab(id: "settings-audit", label: "Audit Log", icon: "list.bullet.clipboard.fill", path: "/settings/audit", permission: "view_activity_log"),
    ], permission: "manage_settings"),
]

// MARK: - Navigation Notification

extension Notification.Name {
    /// Posted when a view wants to navigate to a specific module tab.
    /// `userInfo` should contain `"moduleId"` (String) and optionally `"tabId"` (String).
    static let navigateToModule = Notification.Name("WiredPart.navigateToModule")

    /// Posted when the Parts Catalog page appears, with current context for AI.
    static let catalogPageActive = Notification.Name("WiredPart.catalogPageActive")

    /// Posted when the Parts Catalog page disappears.
    static let catalogPageInactive = Notification.Name("WiredPart.catalogPageInactive")

    /// Posted by the AI panel to set catalog filters programmatically.
    static let aiSetCatalogFilters = Notification.Name("WiredPart.aiSetCatalogFilters")

    /// Posted when the Pricing page appears, with current context for AI.
    static let pricingPageActive = Notification.Name("WiredPart.pricingPageActive")

    /// Posted when the Pricing page disappears.
    static let pricingPageInactive = Notification.Name("WiredPart.pricingPageInactive")

    /// Posted when the Suppliers page appears, with current context for AI.
    static let suppliersPageActive = Notification.Name("WiredPart.suppliersPageActive")

    /// Posted when the Suppliers page disappears.
    static let suppliersPageInactive = Notification.Name("WiredPart.suppliersPageInactive")

    /// Posted when the Companions page appears, with current context for AI.
    static let companionsPageActive = Notification.Name("WiredPart.companionsPageActive")

    /// Posted when the Companions page disappears.
    static let companionsPageInactive = Notification.Name("WiredPart.companionsPageInactive")

    /// Posted when the Forecasting page appears, with current context for AI.
    static let forecastingPageActive = Notification.Name("WiredPart.forecastingPageActive")

    /// Posted when the Forecasting page disappears.
    static let forecastingPageInactive = Notification.Name("WiredPart.forecastingPageInactive")

    // MARK: - Dashboard

    /// Posted when the Dashboard page appears, with summary stats context for AI.
    static let dashboardPageActive = Notification.Name("WiredPart.dashboardPageActive")

    /// Posted when the Dashboard page disappears.
    static let dashboardPageInactive = Notification.Name("WiredPart.dashboardPageInactive")

    // MARK: - Jobs

    /// Posted when the Jobs List page appears, with job count and filter context for AI.
    static let jobsListPageActive = Notification.Name("WiredPart.jobsListPageActive")

    /// Posted when the Jobs List page disappears.
    static let jobsListPageInactive = Notification.Name("WiredPart.jobsListPageInactive")

    /// Posted when the Clock In/Out page appears, with clock status context for AI.
    static let clockPageActive = Notification.Name("WiredPart.clockPageActive")

    /// Posted when the Clock In/Out page disappears.
    static let clockPageInactive = Notification.Name("WiredPart.clockPageInactive")

    // MARK: - Orders

    /// Posted when the JPOs page appears, with JPO count and filter context for AI.
    static let jposPageActive = Notification.Name("WiredPart.jposPageActive")

    /// Posted when the JPOs page disappears.
    static let jposPageInactive = Notification.Name("WiredPart.jposPageInactive")

    /// Posted when the Purchase Orders page appears, with PO count context for AI.
    static let purchaseOrdersPageActive = Notification.Name("WiredPart.purchaseOrdersPageActive")

    /// Posted when the Purchase Orders page disappears.
    static let purchaseOrdersPageInactive = Notification.Name("WiredPart.purchaseOrdersPageInactive")

    // MARK: - Warehouse

    /// Posted when the Inventory Grid page appears, with inventory context for AI.
    static let inventoryGridPageActive = Notification.Name("WiredPart.inventoryGridPageActive")

    /// Posted when the Inventory Grid page disappears.
    static let inventoryGridPageInactive = Notification.Name("WiredPart.inventoryGridPageInactive")

    // MARK: - Scheduling

    /// Posted when the Dispatch page appears, with assignment context for AI.
    static let dispatchPageActive = Notification.Name("WiredPart.dispatchPageActive")

    /// Posted when the Dispatch page disappears.
    static let dispatchPageInactive = Notification.Name("WiredPart.dispatchPageInactive")

    /// Posted when the Schedule Calendar page appears, with selected date context for AI.
    static let scheduleCalendarPageActive = Notification.Name("WiredPart.scheduleCalendarPageActive")

    /// Posted when the Schedule Calendar page disappears.
    static let scheduleCalendarPageInactive = Notification.Name("WiredPart.scheduleCalendarPageInactive")

    // MARK: - People

    /// Posted when the Employees page appears, with employee count context for AI.
    static let employeesPageActive = Notification.Name("WiredPart.employeesPageActive")

    /// Posted when the Employees page disappears.
    static let employeesPageInactive = Notification.Name("WiredPart.employeesPageInactive")

    // MARK: - Fleet

    /// Posted when the Vehicles page appears, with vehicle count context for AI.
    static let vehiclesPageActive = Notification.Name("WiredPart.vehiclesPageActive")

    /// Posted when the Vehicles page disappears.
    static let vehiclesPageInactive = Notification.Name("WiredPart.vehiclesPageInactive")

    // MARK: - Tools

    /// Posted when the Tool Registry page appears, with tool count context for AI.
    static let toolRegistryPageActive = Notification.Name("WiredPart.toolRegistryPageActive")

    /// Posted when the Tool Registry page disappears.
    static let toolRegistryPageInactive = Notification.Name("WiredPart.toolRegistryPageInactive")

    // MARK: - Notebooks

    /// Posted when the Notebooks List page appears, with notebook count context for AI.
    static let notebooksListPageActive = Notification.Name("WiredPart.notebooksListPageActive")

    /// Posted when the Notebooks List page disappears.
    static let notebooksListPageInactive = Notification.Name("WiredPart.notebooksListPageInactive")

    // MARK: - Settings

    /// Posted when the Settings page appears, with context for AI.
    static let settingsPageActive = Notification.Name("WiredPart.settingsPageActive")

    /// Posted when the Settings page disappears.
    static let settingsPageInactive = Notification.Name("WiredPart.settingsPageInactive")
}

// MARK: - Lookup Table

/// Fast module lookup by ID.
let allModulesById: [String: AppModule] = {
    Dictionary(uniqueKeysWithValues: appModules.map { ($0.id, $0) })
}()

// MARK: - Permission Filtering

/// Returns modules visible to a user with the given permissions.
/// Modules with `permission: nil` are always visible.
func visibleModules(permissions: [String]) -> [AppModule] {
    appModules.filter { module in
        guard let perm = module.permission else { return true }
        return permissions.contains(perm)
    }
}

/// Returns tabs visible within a module for a user with the given permissions.
/// Tabs with `permission: nil` are always visible.
func visibleTabs(for module: AppModule, permissions: [String]) -> [AppTab] {
    module.tabs.filter { tab in
        guard let perm = tab.permission else { return true }
        return permissions.contains(perm)
    }
}
