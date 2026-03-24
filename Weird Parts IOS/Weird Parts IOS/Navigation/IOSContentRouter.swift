import SwiftUI
import WiredPartCore

/// Routes a URL-style path to the appropriate native view.
///
/// Paths that have fully implemented native views are routed directly.
/// All other paths show a placeholder indicating the feature is coming soon.
struct IOSContentRouter: View {
    let path: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        routedView
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
        case "/warehouse/network":
            WarehouseRouter(tabId: "warehouse-network")
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
        case "/people/customers":
            PeopleRouter(tabId: "people-customers")
        case "/people/contacts":
            PeopleRouter(tabId: "people-contacts")
        case "/people/contractors":
            PeopleRouter(tabId: "people-contractors")
        case "/people/teams":
            PeopleRouter(tabId: "people-teams")
        // People legacy routes — redirect to Office
        case "/people/employees", "/people/directory":
            OfficeRouter(tabId: "office-employees")
        case "/people/hats":
            OfficeRouter(tabId: "office-hats")
        case "/people/permissions":
            OfficeRouter(tabId: "office-permissions")

        // Scheduling sub-routes
        case "/scheduling/calendar":
            SchedulingRouter(tabId: "scheduling-calendar")
        case "/scheduling/dispatch":
            SchedulingRouter(tabId: "scheduling-dispatch")
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
        case "/office/manage-jobs":
            OfficeRouter(tabId: "office-manage-jobs")
        case "/office/warehouse-exec":
            OfficeRouter(tabId: "office-warehouse-exec")
        case "/office/spending":
            OfficeRouter(tabId: "office-spending")
        case "/office/timesheets":
            OfficeRouter(tabId: "office-timesheets")
        case "/office/pre-billing":
            OfficeRouter(tabId: "office-pre-billing")
        case "/office/bookkeeper":
            OfficeRouter(tabId: "office-bookkeeper")
        case "/office/profitability":
            OfficeRouter(tabId: "office-profitability")
        case "/office/labor-overview":
            OfficeRouter(tabId: "office-labor-overview")
        case "/office/daily-summary":
            OfficeRouter(tabId: "office-daily-summary")
        case "/office/estimation-settings":
            OfficeRouter(tabId: "office-estimation-settings")
        case "/office/employees":
            OfficeRouter(tabId: "office-employees")
        case "/office/hats":
            OfficeRouter(tabId: "office-hats")
        case "/office/permissions":
            OfficeRouter(tabId: "office-permissions")

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

        // Reports legacy routes — redirect to Office
        case "/reports/timesheets":
            OfficeRouter(tabId: "office-timesheets")
        case "/reports/spending":
            OfficeRouter(tabId: "office-spending")
        case "/reports/daily-summary", "/reports/overview":
            OfficeRouter(tabId: "office-daily-summary")
        case "/reports/profitability":
            OfficeRouter(tabId: "office-profitability")
        case "/reports/pre-billing":
            OfficeRouter(tabId: "office-pre-billing")
        case "/reports/bookkeeper":
            OfficeRouter(tabId: "office-bookkeeper")
        case "/reports/labor-overview":
            OfficeRouter(tabId: "office-labor-overview")

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

        // Everything else — placeholder for future native views
        default:
            PlaceholderView(path: path)
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
                .font(.system(size: 48))
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
