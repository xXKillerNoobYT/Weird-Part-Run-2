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
/// Tab paths must match the routes handled by `IOSContentRouter`.
/// Permission strings match the keys from `AuthService.defaultPermissionMap()`.
let appModules: [AppModule] = [
    AppModule(id: "dashboard", label: "Dashboard", icon: "square.grid.2x2.fill", tabs: [
        AppTab(id: "dashboard-home", label: "Overview", icon: "chart.bar.fill", path: "/dashboard"),
    ]),
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
    AppModule(id: "warehouse", label: "Warehouse", icon: "building.fill", tabs: [
        AppTab(id: "warehouse-dashboard", label: "Dashboard", icon: "chart.bar.fill", path: "/warehouse/dashboard"),
        AppTab(id: "warehouse-movements", label: "Movements", icon: "arrow.left.arrow.right", path: "/warehouse/movements"),
        AppTab(id: "warehouse-locations", label: "Locations", icon: "map.fill", path: "/warehouse/locations"),
        AppTab(id: "warehouse-staging", label: "Staging", icon: "tray.2.fill", path: "/warehouse/staging"),
        AppTab(id: "warehouse-receiving", label: "Receiving", icon: "shippingbox.fill", path: "/warehouse/receiving"),
        AppTab(id: "warehouse-returns", label: "Returns", icon: "arrow.uturn.left", path: "/warehouse/returns"),
        AppTab(id: "warehouse-audit", label: "Audit", icon: "checkmark.shield.fill", path: "/warehouse/audit", permission: "perform_audit"),
        AppTab(id: "warehouse-inventory", label: "Inventory", icon: "square.grid.3x3.fill", path: "/warehouse/inventory"),
        AppTab(id: "warehouse-tools", label: "Tools", icon: "wrench.and.screwdriver.fill", path: "/warehouse/tools"),
        AppTab(id: "warehouse-network", label: "Network", icon: "antenna.radiowaves.left.and.right", path: "/warehouse/network", permission: "manage_devices"),
        AppTab(id: "warehouse-settings", label: "Settings", icon: "gearshape.fill", path: "/warehouse/settings", permission: "manage_warehouse"),
    ], permission: "view_warehouse"),
    AppModule(id: "jobs", label: "Jobs", icon: "hammer.fill", tabs: [
        AppTab(id: "jobs-list", label: "All Jobs", icon: "list.bullet", path: "/jobs/list"),
        AppTab(id: "jobs-labor", label: "Labor", icon: "clock.fill", path: "/jobs/labor", permission: "view_labor"),
        AppTab(id: "jobs-reports", label: "Reports", icon: "doc.text.fill", path: "/jobs/reports"),
        AppTab(id: "jobs-clock", label: "Clock", icon: "clock.badge.checkmark.fill", path: "/jobs/clock", permission: "clock_in_out"),
    ], permission: "view_jobs"),
    AppModule(id: "orders", label: "Orders", icon: "cart.fill", tabs: [
        AppTab(id: "orders-jpos", label: "Requests", icon: "doc.badge.plus", path: "/orders/jpos"),
        AppTab(id: "orders-pos", label: "Purchase Orders", icon: "doc.text.fill", path: "/orders/purchase-orders"),
        AppTab(id: "orders-returns", label: "Returns", icon: "arrow.uturn.left", path: "/orders/returns"),
        AppTab(id: "orders-procurement", label: "Procurement", icon: "cart.badge.plus", path: "/orders/procurement"),
        AppTab(id: "orders-staging", label: "Staging", icon: "list.clipboard.fill", path: "/orders/staging"),
        AppTab(id: "orders-approvals", label: "Approvals", icon: "checkmark.circle.fill", path: "/orders/approvals"),
    ], permission: "view_orders"),
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
    AppModule(id: "people", label: "People", icon: "person.2.fill", tabs: [
        AppTab(id: "people-customers", label: "Customers", icon: "person.crop.circle", path: "/people/customers", permission: "view_customers"),
        AppTab(id: "people-contacts", label: "Contacts", icon: "person.crop.rectangle.fill", path: "/people/contacts"),
        AppTab(id: "people-contractors", label: "Contractors", icon: "person.badge.shield.checkmark.fill", path: "/people/contractors", permission: "view_contractors"),
        AppTab(id: "people-teams", label: "Teams", icon: "person.3.fill", path: "/people/teams"),
    ], permission: "view_people"),
    AppModule(id: "scheduling", label: "Scheduling", icon: "calendar", tabs: [
        AppTab(id: "scheduling-calendar", label: "Calendar", icon: "calendar", path: "/scheduling/calendar"),
        AppTab(id: "scheduling-dispatch", label: "Dispatch", icon: "paperplane.fill", path: "/scheduling/dispatch", permission: "manage_dispatch"),
        AppTab(id: "scheduling-time-off", label: "Time Off", icon: "airplane.departure", path: "/scheduling/time-off"),
        AppTab(id: "scheduling-templates", label: "Templates", icon: "doc.on.doc.fill", path: "/scheduling/templates", permission: "manage_scheduling"),
        AppTab(id: "scheduling-availability", label: "Availability", icon: "clock.fill", path: "/scheduling/availability"),
        AppTab(id: "scheduling-sub-schedule", label: "Sub Schedule", icon: "person.badge.clock", path: "/scheduling/sub-schedule", permission: "manage_subcontractors"),
        AppTab(id: "scheduling-config", label: "Config", icon: "gearshape.fill", path: "/scheduling/config", permission: "manage_scheduling"),
    ], permission: "view_scheduling"),
    AppModule(id: "tools", label: "Tools", icon: "wrench.adjustable.fill", tabs: [
        AppTab(id: "tools-registry", label: "Registry", icon: "list.bullet", path: "/tools/registry"),
        AppTab(id: "tools-checkouts", label: "Checkouts", icon: "arrow.right.circle.fill", path: "/tools/checkouts"),
        AppTab(id: "tools-kits", label: "Kits", icon: "suitcase.fill", path: "/tools/kits"),
        AppTab(id: "tools-dashboard", label: "Dashboard", icon: "chart.bar.fill", path: "/tools/dashboard"),
        AppTab(id: "tools-admin", label: "Admin", icon: "person.badge.key.fill", path: "/tools/admin", permission: "manage_tools"),
        AppTab(id: "tools-maintenance", label: "Maintenance", icon: "wrench.adjustable.fill", path: "/tools/maintenance"),
    ], permission: "view_tools"),
    AppModule(id: "notebooks", label: "Notebooks", icon: "note.text", tabs: [
        AppTab(id: "notebooks-all", label: "All Notebooks", icon: "list.bullet", path: "/notebooks/all"),
        AppTab(id: "notebooks-templates", label: "Templates", icon: "doc.on.doc.fill", path: "/notebooks/templates", permission: "manage_templates"),
        AppTab(id: "notebooks-job-notebooks", label: "Job Notebooks", icon: "book.closed.fill", path: "/notebooks/job-notebooks"),
    ]),

    AppModule(id: "chat", label: "Chat", icon: "bubble.left.and.bubble.right.fill", tabs: [
        AppTab(id: "chat-channels", label: "Messages", icon: "bubble.left.fill", path: "/chat/channels"),
        AppTab(id: "chat-questions", label: "Q&A", icon: "questionmark.circle.fill", path: "/chat/questions"),
        AppTab(id: "chat-rfis", label: "RFIs", icon: "doc.questionmark.fill", path: "/chat/rfis", permission: "manage_jobs"),
    ], permission: "view_chat"),
    AppModule(id: "office", label: "Office", icon: "briefcase.fill", tabs: [
        // Operations
        AppTab(id: "office-manage-jobs", label: "Manage Jobs", icon: "hammer.fill", path: "/office/manage-jobs", permission: "manage_jobs"),
        AppTab(id: "office-warehouse-exec", label: "Warehouse", icon: "building.fill", path: "/office/warehouse-exec", permission: "manage_warehouse"),
        // Finance & Billing
        AppTab(id: "office-spending", label: "Spending", icon: "dollarsign.circle.fill", path: "/office/spending", permission: "show_dollar_values"),
        AppTab(id: "office-timesheets", label: "Timesheets", icon: "clock.badge.checkmark", path: "/office/timesheets", permission: "view_reports"),
        AppTab(id: "office-pre-billing", label: "Pre-Billing", icon: "doc.text.fill", path: "/office/pre-billing", permission: "export_reports"),
        AppTab(id: "office-bookkeeper", label: "Bookkeeper", icon: "books.vertical.fill", path: "/office/bookkeeper", permission: "export_reports"),
        AppTab(id: "office-profitability", label: "Profitability", icon: "chart.pie.fill", path: "/office/profitability", permission: "show_dollar_values"),
        AppTab(id: "office-labor-overview", label: "Labor Overview", icon: "person.3.fill", path: "/office/labor-overview", permission: "view_labor"),
        AppTab(id: "office-daily-summary", label: "Daily Summary", icon: "chart.bar.fill", path: "/office/daily-summary", permission: "view_reports"),
        // HR & Admin
        AppTab(id: "office-employees", label: "Employees", icon: "person.fill", path: "/office/employees", permission: "view_people"),
        AppTab(id: "office-hats", label: "Hats & Roles", icon: "graduationcap.fill", path: "/office/hats", permission: "manage_people"),
        AppTab(id: "office-permissions", label: "Permissions", icon: "lock.shield.fill", path: "/office/permissions", permission: "manage_people"),
    ], permission: "manage_jobs"),
    // Settings tabs are slimmed here — the full list is handled by UserMenuSheet.
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
