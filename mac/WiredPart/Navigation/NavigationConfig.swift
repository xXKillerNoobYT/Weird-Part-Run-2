import SwiftUI

// MARK: - Types

/// A single tab within a navigation module.
struct NavTab: Identifiable, Sendable {
    let id: String
    let label: String
    let path: String
    let icon: String          // SF Symbol name
    let permission: String?   // nil = no restriction
    let group: String?        // for grouped tab bars (e.g. Office module)
}

/// A top-level navigation module shown in the sidebar.
struct NavModule: Identifiable, Sendable {
    let id: String
    let label: String
    let path: String
    let icon: String          // SF Symbol name
    let permission: String?
    let tabs: [NavTab]
}

// MARK: - Module Definitions

/// Single source of truth for all navigation modules and their tabs.
/// Mirrors the React `navigation.ts` configuration.
enum NavigationConfig {

    // MARK: Modules

    static let allModules: [NavModule] = [
        dashboard,
        parts,
        office,
        warehouse,
        trucks,
        jobs,
        scheduling,
        notebooks,
        chat,
        orders,
        people,
        settings,
    ]

    // 1. Dashboard
    static let dashboard = NavModule(
        id: "dashboard",
        label: "Dashboard",
        path: "/dashboard",
        icon: "square.grid.2x2",
        permission: nil,
        tabs: []
    )

    // 2. Parts
    static let parts = NavModule(
        id: "parts",
        label: "Parts",
        path: "/parts",
        icon: "shippingbox",
        permission: "view_parts_catalog",
        tabs: [
            NavTab(id: "categories",    label: "Categories",    path: "/parts/categories",    icon: "folder",          permission: nil, group: nil),
            NavTab(id: "catalog",       label: "Catalog",       path: "/parts/catalog",       icon: "list.bullet",     permission: nil, group: nil),
            NavTab(id: "brands",        label: "Brands",        path: "/parts/brands",        icon: "tag",             permission: nil, group: nil),
            NavTab(id: "suppliers",     label: "Suppliers",     path: "/parts/suppliers",     icon: "building.2",      permission: nil, group: nil),
            NavTab(id: "pricing",       label: "Pricing",       path: "/parts/pricing",       icon: "dollarsign.circle", permission: "show_dollar_values", group: nil),
            NavTab(id: "companions",    label: "Companions",    path: "/parts/companions",    icon: "link",            permission: nil, group: nil),
            NavTab(id: "forecasting",   label: "Forecasting",   path: "/parts/forecasting",   icon: "chart.line.uptrend.xyaxis", permission: nil, group: nil),
            NavTab(id: "import-export", label: "Import/Export", path: "/parts/import-export", icon: "arrow.up.arrow.down", permission: nil, group: nil),
        ]
    )

    // 3. Office
    static let office = NavModule(
        id: "office",
        label: "Office",
        path: "/office",
        icon: "building.2",
        permission: "view_admin_hub",
        tabs: [
            // Operations group
            NavTab(id: "warehouse-exec", label: "Warehouse Exec",  path: "/warehouse/executive",   icon: "building.columns",    permission: nil, group: "Operations"),
            NavTab(id: "job-mgmt",       label: "Job Management",  path: "/jobs/management",       icon: "hammer",              permission: nil, group: "Operations"),
            NavTab(id: "tool-admin",     label: "Tool Admin",      path: "/tools/admin",           icon: "wrench.and.screwdriver", permission: nil, group: "Operations"),
            // People group
            NavTab(id: "employees",      label: "Employees",       path: "/people/employees",      icon: "person.2",            permission: nil, group: "People"),
            NavTab(id: "teams",          label: "Teams",           path: "/people/teams",          icon: "person.3",            permission: nil, group: "People"),
            NavTab(id: "hats",           label: "Hats",            path: "/people/hats",           icon: "graduationcap",       permission: nil, group: "People"),
            // Scheduling group
            NavTab(id: "dispatch",       label: "Dispatch",        path: "/scheduling/dispatch",       icon: "paperplane",      permission: nil, group: "Scheduling"),
            NavTab(id: "dispatch-admin", label: "Dispatch Admin",  path: "/scheduling/dispatch-admin", icon: "gearshape.2",     permission: nil, group: "Scheduling"),
            NavTab(id: "availability",   label: "Availability",    path: "/scheduling/availability",   icon: "clock",           permission: nil, group: "Scheduling"),
            NavTab(id: "time-off",       label: "Time Off",        path: "/scheduling/time-off",       icon: "airplane.departure", permission: nil, group: "Scheduling"),
            NavTab(id: "templates",      label: "Templates",       path: "/scheduling/templates",      icon: "doc.on.doc",      permission: nil, group: "Scheduling"),
            NavTab(id: "sub-schedule",   label: "Sub Schedule",    path: "/scheduling/sub-schedule",   icon: "person.badge.clock", permission: nil, group: "Scheduling"),
            // Reports group
            NavTab(id: "reports",        label: "Reports",         path: "/reports/overview",      icon: "chart.bar",           permission: nil, group: "Reports"),
            NavTab(id: "timesheets",     label: "Timesheets",      path: "/reports/timesheets",    icon: "clock.badge.checkmark", permission: nil, group: "Reports"),
            NavTab(id: "pre-billing",    label: "Pre-Billing",     path: "/reports/pre-billing",   icon: "doc.text",            permission: nil, group: "Reports"),
            NavTab(id: "spending",       label: "Spending",        path: "/reports/spending",      icon: "creditcard",          permission: nil, group: "Reports"),
            NavTab(id: "profitability",  label: "Profitability",   path: "/reports/profitability", icon: "chart.pie",           permission: nil, group: "Reports"),
            NavTab(id: "bookkeeper",     label: "Bookkeeper",      path: "/reports/bookkeeper",    icon: "books.vertical",      permission: nil, group: "Reports"),
        ]
    )

    // 4. Warehouse
    static let warehouse = NavModule(
        id: "warehouse",
        label: "Warehouse",
        path: "/warehouse",
        icon: "building.columns",
        permission: "view_warehouse",
        tabs: [
            NavTab(id: "dashboard",  label: "Dashboard",  path: "/warehouse/dashboard",  icon: "square.grid.2x2", permission: nil, group: nil),
            NavTab(id: "movements",  label: "Movements",  path: "/warehouse/movements",  icon: "arrow.left.arrow.right", permission: nil, group: nil),
            NavTab(id: "staging",    label: "Staging",     path: "/warehouse/staging",    icon: "tray.2",          permission: nil, group: nil),
            NavTab(id: "receiving",  label: "Receiving",   path: "/warehouse/receiving",  icon: "shippingbox.and.arrow.backward", permission: nil, group: nil),
            NavTab(id: "returns",    label: "Returns",     path: "/warehouse/returns",    icon: "arrow.uturn.backward", permission: nil, group: nil),
            NavTab(id: "audit",      label: "Audit",       path: "/warehouse/audit",      icon: "checkmark.shield", permission: nil, group: nil),
        ]
    )

    // 5. Trucks
    static let trucks = NavModule(
        id: "trucks",
        label: "Trucks",
        path: "/trucks",
        icon: "truck.box",
        permission: "view_fleet",
        tabs: [
            NavTab(id: "fleet",       label: "Fleet",       path: "/trucks/fleet",       icon: "truck.box",      permission: nil, group: nil),
            NavTab(id: "maintenance", label: "Maintenance", path: "/trucks/maintenance", icon: "wrench",         permission: nil, group: nil),
            NavTab(id: "mileage",     label: "Mileage",     path: "/trucks/mileage",     icon: "gauge.medium",   permission: nil, group: nil),
            NavTab(id: "inspections", label: "Inspections", path: "/trucks/inspections", icon: "checklist",      permission: nil, group: nil),
            NavTab(id: "gps",         label: "GPS",         path: "/trucks/gps",         icon: "location",       permission: nil, group: nil),
            NavTab(id: "trailers",    label: "Trailers",    path: "/trucks/trailers",    icon: "box.truck",      permission: nil, group: nil),
        ]
    )

    // 6. Jobs
    static let jobs = NavModule(
        id: "jobs",
        label: "Jobs",
        path: "/jobs",
        icon: "hammer",
        permission: "view_jobs",
        tabs: [
            NavTab(id: "active",         label: "Active",          path: "/jobs/active",         icon: "list.bullet",     permission: nil, group: nil),
            NavTab(id: "detail",         label: "Detail",          path: "/jobs/detail",         icon: "doc.text",        permission: nil, group: nil),
            NavTab(id: "clock",          label: "Clock",           path: "/jobs/clock",          icon: "clock",           permission: nil, group: nil),
            NavTab(id: "questionnaire",  label: "Questionnaire",   path: "/jobs/questionnaire",  icon: "questionmark.circle", permission: nil, group: nil),
            NavTab(id: "daily-reports",  label: "Daily Reports",   path: "/jobs/daily-reports",  icon: "doc.plaintext",   permission: nil, group: nil),
        ]
    )

    // 7. Scheduling
    static let scheduling = NavModule(
        id: "scheduling",
        label: "Scheduling",
        path: "/scheduling",
        icon: "calendar",
        permission: "view_schedule",
        tabs: [
            NavTab(id: "calendar",    label: "Calendar",    path: "/scheduling/calendar",    icon: "calendar",     permission: nil, group: nil),
            NavTab(id: "my-schedule", label: "My Schedule", path: "/scheduling/my-schedule", icon: "person.crop.circle.badge.clock", permission: nil, group: nil),
        ]
    )

    // 8. Notebooks
    static let notebooks = NavModule(
        id: "notebooks",
        label: "Notebooks",
        path: "/notebooks",
        icon: "book",
        permission: nil,
        tabs: [
            NavTab(id: "job-notebooks", label: "Job Notebooks",    path: "/notebooks/job-notebooks", icon: "book.closed",  permission: nil, group: nil),
            NavTab(id: "general",       label: "General",          path: "/notebooks/general",       icon: "note.text",    permission: nil, group: nil),
            NavTab(id: "templates",     label: "Templates",        path: "/notebooks/templates",     icon: "doc.on.doc",   permission: nil, group: nil),
        ]
    )

    // 9. Chat
    static let chat = NavModule(
        id: "chat",
        label: "Chat",
        path: "/chat",
        icon: "bubble.left.and.bubble.right",
        permission: nil,
        tabs: [
            NavTab(id: "inbox",    label: "Inbox",    path: "/chat/inbox",    icon: "tray",                   permission: nil, group: nil),
            NavTab(id: "qa-board", label: "Q&A Board", path: "/chat/qa-board", icon: "questionmark.bubble",    permission: nil, group: nil),
        ]
    )

    // 10. Orders
    static let orders = NavModule(
        id: "orders",
        label: "Orders",
        path: "/orders",
        icon: "cart",
        permission: "view_orders",
        tabs: [
            NavTab(id: "requests",        label: "Requests",        path: "/orders/requests",        icon: "doc.badge.plus",     permission: nil, group: nil),
            NavTab(id: "unified-order",   label: "Unified Order",   path: "/orders/unified-order",   icon: "list.clipboard",     permission: nil, group: nil),
            NavTab(id: "purchase-orders", label: "Purchase Orders", path: "/orders/purchase-orders", icon: "doc.text.fill",      permission: nil, group: nil),
            NavTab(id: "returns",         label: "Returns",         path: "/orders/returns",         icon: "arrow.uturn.backward", permission: nil, group: nil),
            NavTab(id: "procurement",     label: "Procurement",     path: "/orders/procurement",     icon: "cart.badge.plus",    permission: nil, group: nil),
            NavTab(id: "approvals",       label: "Approvals",       path: "/orders/approvals",       icon: "checkmark.circle",   permission: nil, group: nil),
        ]
    )

    // 11. People
    static let people = NavModule(
        id: "people",
        label: "People",
        path: "/people",
        icon: "person.3",
        permission: "view_employees",
        tabs: [
            NavTab(id: "directory",   label: "Directory",    path: "/people/directory",   icon: "person.text.rectangle", permission: nil, group: nil),
            NavTab(id: "customers",   label: "Customers",    path: "/people/customers",   icon: "person.crop.circle",    permission: "view_customers", group: nil),
            NavTab(id: "contractors", label: "Contractors",  path: "/people/contractors", icon: "person.badge.shield.checkmark", permission: "view_contractors", group: nil),
            NavTab(id: "contacts",    label: "Contacts",     path: "/people/contacts",    icon: "person.crop.circle.badge.questionmark", permission: nil, group: nil),
        ]
    )

    // 12. Settings
    static let settings = NavModule(
        id: "settings",
        label: "Settings",
        path: "/settings",
        icon: "gear",
        permission: nil,
        tabs: [
            NavTab(id: "app-config",           label: "App Config",          path: "/settings/app-config",           icon: "gearshape",                permission: nil, group: nil),
            NavTab(id: "about",                label: "About",              path: "/settings/about",                icon: "info.circle",              permission: nil, group: nil),
            NavTab(id: "themes",               label: "Themes",             path: "/settings/themes",               icon: "paintbrush",               permission: nil, group: nil),
            NavTab(id: "notification-prefs",   label: "Notifications",      path: "/settings/notification-prefs",   icon: "bell",                     permission: nil, group: nil),
            NavTab(id: "company-profiles",     label: "Company Profiles",   path: "/settings/company-profiles",     icon: "building",                 permission: "manage_settings", group: nil),
            NavTab(id: "pdf-settings",         label: "PDF Settings",       path: "/settings/pdf-settings",         icon: "doc.richtext",             permission: "manage_settings", group: nil),
            NavTab(id: "billing-pay-settings", label: "Billing & Pay",      path: "/settings/billing-pay-settings", icon: "banknote",                 permission: "manage_settings", group: nil),
            NavTab(id: "supplier-bridge",      label: "Supplier Bridge",    path: "/settings/supplier-bridge",      icon: "link.circle",              permission: "manage_settings", group: nil),
            NavTab(id: "sync",                 label: "Sync",               path: "/settings/sync",                 icon: "arrow.triangle.2.circlepath", permission: "manage_devices", group: nil),
            NavTab(id: "bluetooth",            label: "Bluetooth",          path: "/settings/bluetooth",            icon: "wave.3.right",             permission: "manage_devices", group: nil),
            NavTab(id: "clock-out-questions",  label: "Clock-Out Questions", path: "/settings/clock-out-questions",  icon: "questionmark.circle",      permission: "manage_settings", group: nil),
            NavTab(id: "backups",              label: "Backups",            path: "/settings/backups",              icon: "externaldrive",            permission: "manage_settings", group: nil),
            NavTab(id: "bootstrap-admin",      label: "Bootstrap Admin",    path: "/settings/bootstrap-admin",      icon: "desktopcomputer",          permission: "manage_devices", group: nil),
            NavTab(id: "key-management",       label: "Key Management",     path: "/settings/key-management",       icon: "key",                      permission: "manage_devices", group: nil),
            NavTab(id: "security-admin",       label: "Security Admin",     path: "/settings/security-admin",       icon: "lock.shield",              permission: "manage_devices", group: nil),
            NavTab(id: "update-protocol",      label: "Update Protocol",    path: "/settings/update-protocol",      icon: "arrow.down.circle",        permission: "manage_devices", group: nil),
            NavTab(id: "data-export",          label: "Data Export",        path: "/settings/data-export",          icon: "square.and.arrow.up",      permission: "manage_settings", group: nil),
            NavTab(id: "integrations",         label: "Integrations",       path: "/settings/integrations",         icon: "puzzlepiece.extension",    permission: "manage_settings", group: nil),
            NavTab(id: "audit-log",            label: "Audit Log",          path: "/settings/audit-log",            icon: "list.bullet.clipboard",    permission: "view_activity_log", group: nil),
            NavTab(id: "database-reset",       label: "Database Reset",     path: "/settings/database-reset",       icon: "arrow.counterclockwise.circle", permission: nil, group: nil),
        ]
    )

    // MARK: - Helpers

    /// Return only modules the user has permission to see.
    static func visibleModules(permissions: [String]) -> [NavModule] {
        allModules.filter { module in
            guard let perm = module.permission else { return true }
            return permissions.contains(perm)
        }
    }

    /// Return only tabs the user has permission to see within a module.
    static func visibleTabs(for module: NavModule, permissions: [String]) -> [NavTab] {
        module.tabs.filter { tab in
            guard let perm = tab.permission else { return true }
            return permissions.contains(perm)
        }
    }

    /// Find a module by path. Two-pass: first checks all tab paths, then module path prefixes.
    static func findModule(byPath path: String) -> NavModule? {
        // Pass 1: exact tab path match
        for module in allModules {
            for tab in module.tabs where tab.path == path {
                return module
            }
        }
        // Pass 2: module path prefix match
        for module in allModules {
            if path == module.path || path.hasPrefix(module.path + "/") {
                return module
            }
        }
        return nil
    }

    /// Get the default tab path for a module (first visible tab, or the module path itself).
    static func defaultTabPath(for module: NavModule, permissions: [String]) -> String {
        let visible = visibleTabs(for: module, permissions: permissions)
        return visible.first?.path ?? module.path
    }
}
