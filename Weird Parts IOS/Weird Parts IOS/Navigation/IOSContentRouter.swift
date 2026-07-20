import SwiftUI
import WiredPartCore

struct AIRouteIdentity: Equatable {
    let path: String
    let pageId: String
}

struct AIRouteContextLifecycle {
    private(set) var publishedIdentity: AIRouteIdentity?

    mutating func activate(path: String, pageId: String) {
        publishedIdentity = AIRouteIdentity(path: path, pageId: pageId)
    }

    mutating func deactivate() -> AIRouteIdentity? {
        defer { publishedIdentity = nil }
        return publishedIdentity
    }
}

/// Routes a URL-style path to the appropriate native view.
///
/// Paths that have fully implemented native views are routed directly.
/// All other paths show a placeholder indicating the feature is coming soon.
struct IOSContentRouter: View {
    let path: String
    @EnvironmentObject private var appCore: AppCore

    private struct RouteDescriptor {
        let moduleLabel: String
        let pageLabel: String
        let pageId: String
    }

    /// The last route identity actually published to the assistant. Keeping this
    /// separate from the current path lets an unregistered/placeholder path
    /// deactivate the prior registered route instead of silently retaining it.
    @State private var routeContextLifecycle = AIRouteContextLifecycle()

    var body: some View {
        routedView
            .onAppear { postRouteContext() }
            .onChange(of: path) { _, _ in postRouteContext() }
            .onReceive(NotificationCenter.default.publisher(for: .requestCurrentPageContext)) { _ in
                postRouteContext()
            }
            .onDisappear { postRouteInactive() }
    }

    private var routeDescriptor: RouteDescriptor? {
        for module in appModules {
            if let tab = module.tabs.first(where: { $0.path == path }) {
                return RouteDescriptor(
                    moduleLabel: module.label,
                    pageLabel: tab.label,
                    pageId: tab.id
                )
            }
        }
        guard let pageId = deepRoutePageId else { return nil }
        let tokens = pageId.split(separator: "-").map(String.init)
        let moduleLabel = tokens.first?.capitalized ?? "App"
        let pageLabel = tokens.dropFirst().map { token in
            switch token.lowercased() {
            case "ai": return "AI"
            case "pdf": return "PDF"
            case "qa": return "Q&A"
            default: return token.capitalized
            }
        }.joined(separator: " ")
        return RouteDescriptor(
            moduleLabel: moduleLabel,
            pageLabel: pageLabel.isEmpty ? pageId : pageLabel,
            pageId: pageId
        )
    }

    /// Canonical identity for every explicit router path that is not an AppTab.
    /// The coverage verifier compares this registry with the routed switch and
    /// inventory, so a new deep link or alias cannot silently miss AI/Help context.
    private var deepRoutePageId: String? {
        switch path {
        case "/chat/messages": return "chat-channels"
        case "/chat/qa": return "chat-questions"
        case "/jobs/clock": return "dashboard-clock"
        case "/warehouse/network": return "devices-network"
        case "/trucks/inspections": return "fleet-inspections"
        case "/trucks/maintenance": return "fleet-maintenance"
        case "/trucks/mileage": return "fleet-mileage"
        case "/fleet/gps", "/trucks/gps": return "fleet-tracking"
        case "/fleet/trailer-locations": return "fleet-trailer-locations"
        case "/trucks/trailers": return "fleet-trailers"
        case "/fleet/truck-tools": return "fleet-truck-tools"
        case "/trucks/fleet": return "fleet-vehicles"
        case "/jobs/daily-reports": return "jobs-daily-reports"
        case "/jobs/detail": return "jobs-detail"
        case "/jobs/active": return "jobs-list"
        case "/jobs/questionnaire": return "jobs-questionnaire"
        case "/notebooks/list", "/notebooks/general": return "notebooks-all"
        case "/orders/requests": return "orders-jpos"
        case "/orders/unified-order": return "orders-staging"
        case "/people/directory": return "people-employees"
        case "/reports/bookkeeper": return "reports-bookkeeper"
        case "/reports/daily-summary", "/reports/overview": return "reports-daily-summary"
        case "/reports/labor-overview": return "reports-labor"
        case "/reports/pre-billing": return "reports-prebilling"
        case "/reports/profitability": return "reports-profitability"
        case "/reports/public": return "reports-public"
        case "/reports/spending": return "reports-spending"
        case "/reports/timesheets": return "reports-timesheets"
        case "/scheduling/my-schedule": return "scheduling-calendar"
        case "/scheduling/dispatch-admin": return "scheduling-dispatch"
        case "/settings/about": return "settings-about"
        case "/settings/ai-config": return "settings-ai-config"
        case "/settings/audit-log": return "settings-audit"
        case "/settings/audit-settings": return "settings-audit-settings"
        case "/settings/backups": return "settings-backups"
        case "/settings/billing", "/settings/billing-pay-settings": return "settings-billing"
        case "/settings/bluetooth": return "settings-bluetooth"
        case "/settings/bootstrap", "/settings/bootstrap-admin": return "settings-bootstrap"
        case "/settings/break-lunch": return "settings-breaks"
        case "/settings/bug-report", "/settings/feedback", "/settings/report-a-bug": return "settings-bug-report"
        case "/settings/clockout", "/settings/clock-out-questions": return "settings-clockout"
        case "/settings/company", "/settings/company-profiles": return "settings-company"
        case "/settings/daily-report-templates": return "settings-daily-report-templates"
        case "/settings/device-management": return "settings-device-management"
        case "/settings/dispatch-preferences": return "settings-dispatch-preferences"
        case "/settings/export", "/settings/data-export": return "settings-export"
        case "/settings/forecast-config": return "settings-forecast-config"
        case "/settings/integrations": return "settings-integrations"
        case "/settings/job-estimation-questions": return "settings-job-estimation-questions"
        case "/settings/keys", "/settings/key-management": return "settings-keys"
        case "/settings/notification-prefs": return "settings-notifications"
        case "/settings/org-thresholds": return "settings-org-thresholds"
        case "/settings/pdf", "/settings/pdf-settings": return "settings-pdf"
        case "/settings/pretrip-checklists": return "settings-pretrip-checklists"
        case "/settings/remote-sync": return "settings-remote-sync"
        case "/settings/report-templates": return "settings-report-templates"
        case "/settings/reset", "/settings/database-reset": return "settings-reset"
        case "/settings/security-admin": return "settings-security"
        case "/settings/shared-channels": return "settings-shared-channels"
        case "/settings/supplier-bridge": return "settings-supplier-bridge"
        case "/settings/tool-policies": return "settings-tool-policies"
        case "/settings/updates", "/settings/update-protocol": return "settings-updates"
        case "/tools/checkout": return "tools-checkouts"
        default: return nil
        }
    }

    /// Publish only route identity. Page-specific visible counts and filters stay
    /// in dedicated notifications; this fallback deliberately excludes record
    /// values, private notes, credentials, and mutation identifiers.
    private func postRouteContext() {
        guard let descriptor = routeDescriptor else {
            postRouteInactive()
            return
        }
        routeContextLifecycle.activate(path: path, pageId: descriptor.pageId)
        let context = "Module: \(descriptor.moduleLabel); Page: \(descriptor.pageLabel); Route: \(path)"
        NotificationCenter.default.post(
            name: .routePageActive,
            object: nil,
            userInfo: [
                "context": context,
                "path": path,
                "pageId": descriptor.pageId,
                "module": descriptor.moduleLabel,
                "page": descriptor.pageLabel,
            ]
        )
    }

    private func postRouteInactive() {
        guard let identity = routeContextLifecycle.deactivate() else { return }
        NotificationCenter.default.post(
            name: .routePageInactive,
            object: nil,
            userInfo: [
                "path": identity.path,
                "pageId": identity.pageId,
            ]
        )
    }

    @ViewBuilder
    private var routedView: some View {
        switch path {
        // Dashboard
        case "/dashboard":
            DashboardView()
        case "/dashboard/clock":
            IOSClockPage()
        case "/dashboard/report":
            DashboardDailyReportPage()
        case "/dashboard/scanner":
            IOSDashboardQRScannerPage()

        // Parts sub-routes
        case "/parts/categories":
            PartsRouter(tabId: "parts-categories")
        case "/parts/catalog":
            PartsRouter(tabId: "parts-catalog")
        case "/parts/brands":
            PartsRouter(tabId: "parts-brands")
        case "/parts/suppliers":
            PartsRouter(tabId: "parts-suppliers")
        case "/parts/pricing":
            PartsRouter(tabId: "parts-pricing")
        case "/parts/companions":
            PartsRouter(tabId: "parts-companions")
        case "/parts/forecasting":
            PartsRouter(tabId: "parts-forecasting")
        case "/parts/import-export":
            PartsRouter(tabId: "parts-import-export")

        // Settings sub-routes
        case "/settings/themes":
            SettingsRouter(tabId: "settings-themes")
        case "/settings/app-config":
            SettingsRouter(tabId: "settings-app-config")
        case "/settings/about":
            SettingsRouter(tabId: "settings-about")
        case "/settings/bug-report", "/settings/feedback", "/settings/report-a-bug":
            SettingsRouter(tabId: "settings-bug-report")
        case "/settings/company":
            SettingsRouter(tabId: "settings-company")
        case "/settings/pdf":
            SettingsRouter(tabId: "settings-pdf")
        case "/settings/billing":
            SettingsRouter(tabId: "settings-billing")
        case "/settings/notifications":
            SettingsRouter(tabId: "settings-notifications")
        case "/settings/sync":
            SettingsRouter(tabId: "settings-sync")
        case "/settings/bluetooth":
            SettingsRouter(tabId: "settings-bluetooth")
        case "/settings/clockout":
            SettingsRouter(tabId: "settings-clockout")
        case "/settings/backups":
            SettingsRouter(tabId: "settings-backups")
        case "/settings/bootstrap":
            SettingsRouter(tabId: "settings-bootstrap")
        case "/settings/keys":
            SettingsRouter(tabId: "settings-keys")
        case "/settings/security":
            SettingsRouter(tabId: "settings-security")
        case "/settings/updates":
            SettingsRouter(tabId: "settings-updates")
        case "/settings/export":
            SettingsRouter(tabId: "settings-export")
        case "/settings/integrations":
            SettingsRouter(tabId: "settings-integrations")
        case "/settings/audit":
            SettingsRouter(tabId: "settings-audit")
        case "/settings/supplier-bridge":
            SettingsRouter(tabId: "settings-supplier-bridge")
        case "/settings/reset", "/settings/database-reset":
            SettingsRouter(tabId: "settings-reset")
        case "/settings/clock-out-questions":
            SettingsRouter(tabId: "settings-clockout")
        case "/settings/company-profiles":
            SettingsRouter(tabId: "settings-company")
        case "/settings/pdf-settings":
            SettingsRouter(tabId: "settings-pdf")
        case "/settings/billing-pay-settings":
            SettingsRouter(tabId: "settings-billing")
        case "/settings/notification-prefs":
            SettingsRouter(tabId: "settings-notifications")
        case "/settings/bootstrap-admin":
            SettingsRouter(tabId: "settings-bootstrap")
        case "/settings/key-management":
            SettingsRouter(tabId: "settings-keys")
        case "/settings/security-admin":
            SettingsRouter(tabId: "settings-security")
        case "/settings/update-protocol":
            SettingsRouter(tabId: "settings-updates")
        case "/settings/data-export":
            SettingsRouter(tabId: "settings-export")
        case "/settings/audit-log":
            SettingsRouter(tabId: "settings-audit")

        // Jobs sub-routes
        case "/jobs/list", "/jobs/active":
            JobsRouter(tabId: "jobs-list")
        case "/jobs/labor":
            JobsRouter(tabId: "jobs-labor")
        case "/jobs/reports":
            JobsRouter(tabId: "jobs-reports")
        case "/jobs/clock":
            IOSClockPage() // Redirect — Clock now lives under Dashboard
        case "/jobs/detail":
            JobsRouter(tabId: "jobs-detail")
        case "/jobs/questionnaire":
            JobsRouter(tabId: "jobs-questionnaire")
        case "/jobs/daily-reports":
            JobsRouter(tabId: "jobs-daily-reports")

        // Warehouse sub-routes
        case "/warehouse/dashboard":
            WarehouseRouter(tabId: "warehouse-dashboard")
        case "/warehouse/movements":
            WarehouseRouter(tabId: "warehouse-movements")
        case "/warehouse/locations":
            WarehouseRouter(tabId: "warehouse-locations")
        case "/warehouse/staging":
            WarehouseRouter(tabId: "warehouse-staging")
        case "/warehouse/receiving":
            WarehouseRouter(tabId: "warehouse-receiving")
        case "/warehouse/returns":
            WarehouseRouter(tabId: "warehouse-returns")
        case "/warehouse/audit":
            WarehouseRouter(tabId: "warehouse-audit")
        case "/warehouse/inventory":
            WarehouseRouter(tabId: "warehouse-inventory")
        case "/warehouse/tools":
            WarehouseRouter(tabId: "warehouse-tools")
        case "/warehouse/leaderboard":
            WarehouseRouter(tabId: "warehouse-leaderboard")
        // Network/devices is now its own top-level "Devices" module. The old
        // /warehouse/network path is kept as an alias for any existing deep links.
        case "/devices/network", "/warehouse/network":
            IOSWarehouseNetworkPage()
        case "/warehouse/settings":
            WarehouseRouter(tabId: "warehouse-settings")

        // Orders sub-routes
        case "/orders/jpos", "/orders/requests":
            OrdersRouter(tabId: "orders-jpos")
        case "/orders/purchase-orders":
            OrdersRouter(tabId: "orders-pos")
        case "/orders/returns":
            OrdersRouter(tabId: "orders-returns")
        case "/orders/procurement":
            OrdersRouter(tabId: "orders-procurement")
        case "/orders/staging", "/orders/unified-order":
            OrdersRouter(tabId: "orders-staging")
        case "/orders/approvals":
            OrdersRouter(tabId: "orders-approvals")
        case "/orders/parts":
            OrdersRouter(tabId: "orders-parts")
        case "/orders/wishlist":
            OrdersRouter(tabId: "orders-wishlist")

        // Fleet sub-routes
        case "/fleet/vehicles", "/trucks/fleet":
            FleetRouter(tabId: "fleet-vehicles")
        case "/fleet/maintenance", "/trucks/maintenance":
            FleetRouter(tabId: "fleet-maintenance")
        case "/fleet/mileage", "/trucks/mileage":
            FleetRouter(tabId: "fleet-mileage")
        case "/fleet/dashboard":
            FleetRouter(tabId: "fleet-dashboard")
        case "/fleet/fuel":
            FleetRouter(tabId: "fleet-fuel")
        case "/fleet/trailers", "/trucks/trailers":
            FleetRouter(tabId: "fleet-trailers")
        case "/fleet/inspections", "/trucks/inspections":
            FleetRouter(tabId: "fleet-inspections")
        case "/fleet/tracking", "/fleet/gps", "/trucks/gps":
            FleetRouter(tabId: "fleet-tracking")
        case "/fleet/my-truck":
            FleetRouter(tabId: "fleet-my-truck")
        case "/fleet/trailer-locations":
            FleetRouter(tabId: "fleet-trailer-locations")
        case "/fleet/truck-tools":
            FleetRouter(tabId: "fleet-truck-tools")

        // People sub-routes
        case "/people/dashboard":
            PeopleRouter(tabId: "people-dashboard")
        case "/people/customers":
            PeopleRouter(tabId: "people-customers")
        case "/people/contacts":
            PeopleRouter(tabId: "people-contacts")
        case "/people/contractors":
            PeopleRouter(tabId: "people-contractors")
        case "/people/teams":
            PeopleRouter(tabId: "people-teams")
        // People legacy routes — redirect to People module
        case "/people/employees", "/people/directory":
            PeopleRouter(tabId: "people-employees")
        case "/people/hats":
            PeopleRouter(tabId: "people-hats")
        case "/people/permissions":
            PeopleRouter(tabId: "people-permissions")

        // Scheduling sub-routes
        case "/scheduling/calendar":
            SchedulingRouter(tabId: "scheduling-calendar")
        case "/scheduling/dispatch":
            SchedulingRouter(tabId: "scheduling-dispatch")
        case "/scheduling/flex-pool":
            SchedulingRouter(tabId: "scheduling-flex-pool")
        case "/scheduling/time-off":
            SchedulingRouter(tabId: "scheduling-time-off")
        case "/scheduling/templates":
            SchedulingRouter(tabId: "scheduling-templates")
        case "/scheduling/availability":
            SchedulingRouter(tabId: "scheduling-availability")
        case "/scheduling/sub-schedule":
            SchedulingRouter(tabId: "scheduling-sub-schedule")
        case "/scheduling/dispatch-admin":
            SchedulingRouter(tabId: "scheduling-dispatch")
        case "/scheduling/my-schedule":
            SchedulingRouter(tabId: "scheduling-calendar")
        case "/scheduling/config":
            SchedulingRouter(tabId: "scheduling-config")
        case "/scheduling/pipeline":
            SchedulingRouter(tabId: "scheduling-pipeline")
        case "/scheduling/long-pipeline":
            SchedulingRouter(tabId: "scheduling-long-pipeline")

        // Office sub-routes
        case "/office/dashboard":
            officeRoute(tabId: "office-dashboard", permissions: [officeAccessPermission])
        case "/office/approvals":
            officeRoute(tabId: "office-approvals", permissions: [officeAccessPermission])
        case "/office/manage-jobs":
            officeRoute(tabId: "office-manage-jobs", permissions: [officeAccessPermission, "manage_jobs"])
        case "/office/warehouse-exec":
            officeRoute(tabId: "office-warehouse-exec", permissions: [officeAccessPermission, "manage_warehouse"])
        case "/office/estimation-settings":
            officeRoute(tabId: "office-estimation-settings", permissions: [officeAccessPermission, "manage_jobs"])
        case "/office/pipeline":
            officeRoute(tabId: "office-pipeline", permissions: [officeAccessPermission, "manage_jobs"])
        case "/office/spending":
            officeRoute(tabId: "office-spending", permissions: [officeAccessPermission, financialValuesPermission])
        case "/office/teams":
            officeRoute(tabId: "office-teams", permissions: [officeAccessPermission])
        case "/office/reports":
            officeRoute(tabId: "office-reports", permissions: [officeAccessPermission, "view_reports"])

        // Chat sub-routes
        case "/chat/channels", "/chat/messages":
            IOSChatRouter(tabId: "chat-channels")
        case "/chat/questions", "/chat/qa":
            IOSChatRouter(tabId: "chat-questions")
        case "/chat/rfis":
            IOSChatRouter(tabId: "chat-rfis")

        // Notebooks sub-routes
        case "/notebooks/all", "/notebooks/list", "/notebooks/general":
            IOSNotebooksRouter(tabId: "notebooks-all")
        case "/notebooks/templates":
            IOSNotebooksRouter(tabId: "notebooks-templates")
        case "/notebooks/job-notebooks":
            IOSNotebooksRouter(tabId: "notebooks-job-notebooks")

        // Reports legacy routes — render pages directly
        case "/reports/timesheets":
            IOSTimesheetsPage()
        case "/reports/spending":
            IOSSpendingPage()
        case "/reports/daily-summary", "/reports/overview":
            IOSDailyReportsSummaryPage()
        case "/reports/profitability":
            IOSProfitabilityPage()
        case "/reports/pre-billing":
            IOSPreBillingPage()
        case "/reports/bookkeeper":
            IOSBookkeeperExportPage()
        case "/reports/labor-overview":
            IOSLaborOverviewPage()
        case "/reports/public":
            // Fix #217: IOSPublicReportView is a stub that always shows an error
            // because public-report sharing hasn't been built yet. Route to the
            // standard PlaceholderView so users see "Coming Soon" instead of a
            // confusing error message on a navigable route.
            PlaceholderView(path: "/reports/public")

        // Tools sub-routes
        case "/tools/registry":
            IOSToolsRouter(tabId: "tools-registry")
        case "/tools/checkouts", "/tools/checkout":
            IOSToolsRouter(tabId: "tools-checkouts")
        case "/tools/kits":
            IOSToolsRouter(tabId: "tools-kits")
        case "/tools/dashboard":
            IOSToolsRouter(tabId: "tools-dashboard")
        case "/tools/admin":
            IOSToolsRouter(tabId: "tools-admin")
        case "/tools/maintenance":
            IOSToolsRouter(tabId: "tools-maintenance")

        // Settings additional routes
        case "/settings/ai-config":
            SettingsRouter(tabId: "settings-ai-config")
        case "/settings/device-management":
            SettingsRouter(tabId: "settings-device-management")
        case "/settings/remote-sync":
            SettingsRouter(tabId: "settings-remote-sync")
        case "/settings/shared-channels":
            SettingsRouter(tabId: "settings-shared-channels")
        case "/settings/break-lunch":
            SettingsRouter(tabId: "settings-breaks")

        // Settings stub routes (52A)
        case "/settings/tool-policies":
            SettingsRouter(tabId: "settings-tool-policies")
        case "/settings/pretrip-checklists":
            SettingsRouter(tabId: "settings-pretrip-checklists")
        case "/settings/dispatch-preferences":
            SettingsRouter(tabId: "settings-dispatch-preferences")
        case "/settings/forecast-config":
            SettingsRouter(tabId: "settings-forecast-config")
        case "/settings/org-thresholds":
            SettingsRouter(tabId: "settings-org-thresholds")
        case "/settings/audit-settings":
            SettingsRouter(tabId: "settings-audit-settings")
        case "/settings/daily-report-templates":
            SettingsRouter(tabId: "settings-daily-report-templates")
        case "/settings/job-estimation-questions":
            SettingsRouter(tabId: "settings-job-estimation-questions")
        case "/settings/report-templates":
            SettingsRouter(tabId: "settings-report-templates")

        // Everything else — placeholder for future native views
        default:
            PlaceholderView(path: path)
        }
    }

    @ViewBuilder
    private func officeRoute(tabId: String, permissions: [String]) -> some View {
        if permissions.allSatisfy({ appCore.hasPermission($0) }) {
            OfficeRouter(tabId: tabId)
        } else {
            let hasOfficeAccess = appCore.hasPermission(officeAccessPermission)
            EmptyStateView(
                icon: "lock.shield",
                title: hasOfficeAccess ? "Permission required" : "Office access required",
                message: hasOfficeAccess
                    ? "You do not have the required permission to open this Office page."
                    : "You do not have Office access."
            )
        }
    }
}

// MARK: - Placeholder

/// Informational placeholder shown for routes that don't yet have
/// a native SwiftUI implementation.
struct PlaceholderView: View {
    let path: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer.fill")
                .decorativeIconFont(48)
                .foregroundStyle(.secondary)
            Text("Coming Soon")
                .font(.title2)
                .fontWeight(.semibold)
            Text(path)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospaced()
            Text("This feature is being built as a native SwiftUI view.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
