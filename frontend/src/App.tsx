/**
 * App — Root component with routing configuration.
 *
 * Route structure:
 * /                        → Redirect to /dashboard
 * /dashboard               → DashboardPage
 * /parts/catalog            → CatalogPage
 * /parts/brands             → BrandsPage
 * ... (all module/tab routes)
 * /settings/themes          → ThemesPage (functional)
 *
 * All routes are wrapped in:
 * 1. AuthGate (ensures authentication before rendering)
 * 2. AppShell (sidebar + topbar + tabbar + content area)
 */

import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

// Auth
import { AuthGate } from './components/auth/AuthGate';

// Layout
import { AppShell } from './components/layout/AppShell';

// Pages — Dashboard
import { DashboardPage } from './features/dashboard/pages/DashboardPage';

// Pages — Parts
import { CatalogPage } from './features/parts/pages/CatalogPage';
import { BrandsPage } from './features/parts/pages/BrandsPage';
import { PricingPage } from './features/parts/pages/PricingPage';
import { ForecastingPage } from './features/parts/pages/ForecastingPage';
import { ImportExportPage } from './features/parts/pages/ImportExportPage';
import { SuppliersPage } from './features/parts/pages/SuppliersPage';
import { CategoriesPage } from './features/parts/pages/CategoriesPage';
import { CompanionsPage } from './features/parts/pages/CompanionsPage';

// Pages — Office
import { WarehouseExecPage } from './features/office/pages/WarehouseExecPage';
import { ManageJobsPage } from './features/office/pages/ManageJobsPage';
import { SpendingDashboardPage } from './features/office/pages/SpendingDashboardPage';

// Pages — Warehouse
import { WarehouseDashboardPage } from './features/warehouse/pages/WarehouseDashboardPage';
import { InventoryGridPage } from './features/warehouse/pages/InventoryGridPage';
import { StagingPage } from './features/warehouse/pages/StagingPage';
import { AuditPage } from './features/warehouse/pages/AuditPage';
import { MovementsLogPage } from './features/warehouse/pages/MovementsLogPage';
import { WarehouseToolsPage } from './features/warehouse/pages/ToolsPage';
import { ReceivingPage } from './features/warehouse/pages/ReceivingPage';
import { ReturnSortingPage } from './features/warehouse/pages/ReturnSortingPage';
import { WarehouseSettingsPage } from './features/warehouse/pages/WarehouseSettingsPage';
import { WarehouseNetworkPage } from './features/warehouse/pages/WarehouseNetworkPage';

// Pages — Trucks
import { MyTruckPage } from './features/trucks/pages/MyTruckPage';
import { AllTrucksPage } from './features/trucks/pages/AllTrucksPage';
import { VehicleDetailPage } from './features/trucks/pages/VehicleDetailPage';
import { ToolsPage } from './features/trucks/pages/ToolsPage';
import { MaintenancePage } from './features/trucks/pages/MaintenancePage';
import { MileagePage } from './features/trucks/pages/MileagePage';
import { FleetDashboardPage } from './features/trucks/pages/FleetDashboardPage';
import { TrailersPage } from './features/trucks/pages/TrailersPage';
import { TrailerDetailPage } from './features/trucks/pages/TrailerDetailPage';
import { TrailerLocationsPage } from './features/trucks/pages/TrailerLocationsPage';
import { FuelPage } from './features/trucks/pages/FuelPage';
import { TelematicsPage } from './features/trucks/pages/TelematicsPage';
import { InspectionsPage } from './features/trucks/pages/InspectionsPage';

// Pages — Jobs
import { ActiveJobsPage } from './features/jobs/pages/ActiveJobsPage';
import { MyClockPage } from './features/jobs/pages/MyClockPage';
import { JobDetailPage } from './features/jobs/pages/JobDetailPage';
import { JobReportsListPage } from './features/jobs/pages/JobReportsListPage';
import { DailyReportView } from './features/jobs/pages/DailyReportView';

// Pages — Notebooks
import { NotebooksPage } from './features/notebooks/pages/NotebooksPage';
import { NotebookDetailPage } from './features/notebooks/pages/NotebookDetailPage';
import { JobNotebookTemplatePage } from './features/office/pages/JobNotebookTemplatePage';
import { WarehouseLocationsPage } from './features/office/pages/WarehouseLocationsPage';

// Pages — Chat
import ChatInboxPage from './features/chat/pages/ChatInboxPage';
import QABoardPage from './features/chat/pages/QABoardPage';
import RFIListPage from './features/chat/pages/RFIListPage';

// Pages — Orders
import { PartsRequestsPage } from './features/orders/pages/PartsRequestsPage';
import { MyOrdersPage } from './features/orders/pages/MyOrdersPage';
import { UnifiedOrderPage } from './features/orders/pages/UnifiedOrderPage';
import { ReceiveShipmentPage } from './features/orders/pages/ReceiveShipmentPage';
import { ReturnsPage } from './features/orders/pages/ReturnsPage';
import { ProcurementPage } from './features/orders/pages/ProcurementPage';
import { ReturnAnalyticsPage } from './features/orders/pages/ReturnAnalyticsPage';
import { JPODetailPage } from './features/orders/pages/JPODetailPage';
import { PODetailPage } from './features/orders/pages/PODetailPage';
import { NewReturnPage } from './features/orders/pages/NewReturnPage';
import { ReturnDetailPage } from './features/orders/pages/ReturnDetailPage';
import { ApprovalsTab } from './features/office/pages/ApprovalsTab';
import { POManagementTab } from './features/office/pages/POManagementTab';
import { ReviewAndSendPage } from './features/office/pages/ReviewAndSendPage';

// Pages — People
import { EmployeeListPage } from './features/people/pages/EmployeeListPage';
import { EmployeeDetailPage } from './features/people/pages/EmployeeDetailPage';
import { HatsPage } from './features/people/pages/HatsPage';
import { PermissionsPage } from './features/people/pages/PermissionsPage';
import { TeamsPage } from './features/people/pages/TeamsPage';
import { CustomersPage } from './features/people/pages/CustomersPage';
import { CustomerDetailPage } from './features/people/pages/CustomerDetailPage';
import { ContractorsPage } from './features/people/pages/ContractorsPage';
import { ContractorDetailPage } from './features/people/pages/ContractorDetailPage';
import { ContactDirectoryPage } from './features/people/pages/ContactDirectoryPage';

// Pages — Scheduling
import { ScheduleCalendarPage } from './features/scheduling/pages/ScheduleCalendarPage';
import { DailyDispatchPage } from './features/scheduling/pages/DailyDispatchPage';
import { WeeklyAvailabilityPage } from './features/scheduling/pages/WeeklyAvailabilityPage';
import { TimeOffPage } from './features/scheduling/pages/TimeOffPage';
import { DispatchTemplatesPage } from './features/scheduling/pages/DispatchTemplatesPage';
import { ScheduleConfigPage } from './features/scheduling/pages/ScheduleConfigPage';
import { SubSchedulePage } from './features/scheduling/pages/SubSchedulePage';

// Pages — Reports
import { PreBillingPage } from './features/reports/pages/PreBillingPage';
import { TimesheetsPage } from './features/reports/pages/TimesheetsPage';
import { LaborOverviewPage } from './features/reports/pages/LaborOverviewPage';
import { ExportsPage } from './features/reports/pages/ExportsPage';
import { ProfitabilityPage } from './features/reports/pages/ProfitabilityPage';

// Pages — Tools (cross-module)
import { ToolScanRedirect } from './features/tools/components/ToolScanRedirect';

// Pages — Settings
import { AppConfigPage } from './features/settings/pages/AppConfigPage';
import { CompanyProfilePage } from './features/settings/pages/CompanyProfilePage';
import { ThemesPage } from './features/settings/pages/ThemesPage';
import { NotificationPrefsPage } from './features/settings/pages/NotificationPrefsPage';
import { SyncPage } from './features/settings/pages/SyncPage';
import { AiConfigPage } from './features/settings/pages/AiConfigPage';
import { DeviceManagementPage } from './features/settings/pages/DeviceManagementPage';
import { SecurityAdminPage } from './features/settings/pages/SecurityAdminPage';
import { BootstrapAdminPage } from './features/settings/pages/BootstrapAdminPage';
import { SupplierBridgePage } from './features/settings/pages/SupplierBridgePage';
import { UpdateProtocolPage } from './features/settings/pages/UpdateProtocolPage';
import AboutPage from './features/settings/pages/AboutPage';
import { ClockOutQuestionsPage } from './features/settings/pages/ClockOutQuestionsPage';

// ── React Query Client ─────────────────────────────────────────────
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      staleTime: 30_000,  // 30 seconds before refetch
      refetchOnWindowFocus: false,
    },
  },
});

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <AuthGate>
          <Routes>
            {/* Main app routes — all inside AppShell */}
            <Route element={<AppShell />}>
              {/* Root redirect */}
              <Route path="/" element={<Navigate to="/dashboard" replace />} />

              {/* Dashboard */}
              <Route path="/dashboard" element={<DashboardPage />} />

              {/* Parts */}
              <Route path="/parts" element={<Navigate to="/parts/catalog" replace />} />
              <Route path="/parts/categories" element={<CategoriesPage />} />
              <Route path="/parts/catalog" element={<CatalogPage />} />
              <Route path="/parts/brands" element={<BrandsPage />} />
              <Route path="/parts/suppliers" element={<SuppliersPage />} />
              <Route path="/parts/pricing" element={<PricingPage />} />
              <Route path="/parts/forecasting" element={<ForecastingPage />} />
              <Route path="/parts/companions" element={<CompanionsPage />} />
              <Route path="/parts/import-export" element={<ImportExportPage />} />

              {/* Office */}
              <Route path="/office" element={<Navigate to="/office/warehouse-exec" replace />} />
              <Route path="/office/warehouse-exec" element={<WarehouseExecPage />} />
              <Route path="/office/manage-jobs" element={<ManageJobsPage />} />
              <Route path="/office/notebook-templates" element={<JobNotebookTemplatePage />} />
              <Route path="/office/clock-out-questions" element={<ClockOutQuestionsPage />} />
              <Route path="/office/warehouse-locations" element={<WarehouseLocationsPage />} />
              <Route path="/office/spending" element={<SpendingDashboardPage />} />

              {/* Warehouse */}
              <Route path="/warehouse" element={<Navigate to="/warehouse/dashboard" replace />} />
              <Route path="/warehouse/dashboard" element={<WarehouseDashboardPage />} />
              <Route path="/warehouse/inventory" element={<InventoryGridPage />} />
              <Route path="/warehouse/receiving" element={<ReceivingPage />} />
              <Route path="/warehouse/return-sorting" element={<ReturnSortingPage />} />
              <Route path="/warehouse/staging" element={<StagingPage />} />
              <Route path="/warehouse/audit" element={<AuditPage />} />
              <Route path="/warehouse/movements" element={<MovementsLogPage />} />
              <Route path="/warehouse/tools" element={<WarehouseToolsPage />} />
              <Route path="/warehouse/network" element={<WarehouseNetworkPage />} />
              <Route path="/warehouse/settings" element={<WarehouseSettingsPage />} />

              {/* Trucks */}
              <Route path="/trucks" element={<Navigate to="/trucks/my-truck" replace />} />
              <Route path="/trucks/my-truck" element={<MyTruckPage />} />
              <Route path="/trucks/all" element={<AllTrucksPage />} />
              <Route path="/trucks/tools" element={<ToolsPage />} />
              <Route path="/trucks/maintenance" element={<MaintenancePage />} />
              <Route path="/trucks/mileage" element={<MileagePage />} />
              <Route path="/trucks/fleet" element={<FleetDashboardPage />} />
              <Route path="/trucks/fuel" element={<FuelPage />} />
              <Route path="/trucks/telematics" element={<TelematicsPage />} />
              <Route path="/trucks/inspections" element={<InspectionsPage />} />
              <Route path="/trucks/trailers" element={<TrailersPage />} />
              <Route path="/trucks/trailers/:trailer_id" element={<TrailerDetailPage />} />
              <Route path="/trucks/trailer-locations" element={<TrailerLocationsPage />} />
              <Route path="/trucks/:id" element={<VehicleDetailPage />} />

              {/* Jobs */}
              <Route path="/jobs" element={<Navigate to="/jobs/active" replace />} />
              <Route path="/jobs/active" element={<ActiveJobsPage />} />
              <Route path="/jobs/my-clock" element={<MyClockPage />} />
              <Route path="/jobs/:id" element={<JobDetailPage />} />

              {/* Notebooks */}
              <Route path="/notebooks" element={<Navigate to="/notebooks/all" replace />} />
              <Route path="/notebooks/all" element={<NotebooksPage />} />
              <Route path="/notebooks/job-notebooks" element={<NotebooksPage />} />
              <Route path="/notebooks/general" element={<NotebooksPage />} />
              <Route path="/notebooks/:notebookId" element={<NotebookDetailPage />} />

              {/* Chat & Q&A */}
              <Route path="/chat" element={<Navigate to="/chat/inbox" replace />} />
              <Route path="/chat/inbox" element={<ChatInboxPage />} />
              <Route path="/chat/qa-board" element={<QABoardPage />} />
              <Route path="/chat/rfis" element={<RFIListPage />} />

              {/* Orders — Phase 7A: Field-worker tabs + Office tabs */}
              <Route path="/orders" element={<Navigate to="/orders/my-orders" replace />} />
              {/* Field worker tabs */}
              <Route path="/orders/my-orders" element={<MyOrdersPage />} />
              <Route path="/orders/new-order" element={<UnifiedOrderPage />} />
              <Route path="/orders/returns" element={<ReturnsPage />} />
              <Route path="/orders/returns/new" element={<NewReturnPage />} />
              <Route path="/orders/returns/:id" element={<ReturnDetailPage />} />
              {/* Office tabs */}
              <Route path="/orders/approvals" element={<ApprovalsTab />} />
              <Route path="/orders/all-requests" element={<PartsRequestsPage />} />
              <Route path="/orders/purchase-orders" element={<POManagementTab />} />
              <Route path="/orders/purchase-orders/new" element={<Navigate to="/orders/new-order" replace />} />
              <Route path="/orders/purchase-orders/receive" element={<ReceiveShipmentPage />} />
              <Route path="/orders/review-and-send" element={<ReviewAndSendPage />} />
              <Route path="/orders/procurement" element={<ProcurementPage />} />
              <Route path="/orders/return-analytics" element={<ReturnAnalyticsPage />} />
              {/* Detail pages (shared between field + office) */}
              <Route path="/orders/parts-requests/:id" element={<JPODetailPage />} />
              <Route path="/orders/pos/:id" element={<PODetailPage />} />
              <Route path="/orders/parts-requests/:id/generate-pos" element={<Navigate to="/orders/review-and-send" replace />} />

              {/* Scheduling */}
              <Route path="/scheduling" element={<Navigate to="/scheduling/calendar" replace />} />
              <Route path="/scheduling/calendar" element={<ScheduleCalendarPage />} />
              <Route path="/scheduling/dispatch" element={<DailyDispatchPage />} />
              <Route path="/scheduling/availability" element={<WeeklyAvailabilityPage />} />
              <Route path="/scheduling/time-off" element={<TimeOffPage />} />
              <Route path="/scheduling/templates" element={<DispatchTemplatesPage />} />
              <Route path="/scheduling/schedules" element={<ScheduleConfigPage />} />
              <Route path="/scheduling/subcontractors" element={<SubSchedulePage />} />

              {/* People */}
              <Route path="/people" element={<Navigate to="/people/employees" replace />} />
              <Route path="/people/employees" element={<EmployeeListPage />} />
              <Route path="/people/employees/:id" element={<EmployeeDetailPage />} />
              <Route path="/people/customers" element={<CustomersPage />} />
              <Route path="/people/customers/:id" element={<CustomerDetailPage />} />
              <Route path="/people/contractors" element={<ContractorsPage />} />
              <Route path="/people/contractors/:id" element={<ContractorDetailPage />} />
              <Route path="/people/directory" element={<ContactDirectoryPage />} />
              <Route path="/people/hats" element={<HatsPage />} />
              <Route path="/people/permissions" element={<PermissionsPage />} />
              <Route path="/people/teams" element={<TeamsPage />} />

              {/* Reports */}
              <Route path="/reports" element={<Navigate to="/reports/daily-reports" replace />} />
              <Route path="/reports/daily-reports" element={<JobReportsListPage />} />
              <Route path="/reports/daily-reports/:jobId/:date" element={<DailyReportView />} />
              <Route path="/reports/pre-billing" element={<PreBillingPage />} />
              <Route path="/reports/timesheets" element={<TimesheetsPage />} />
              <Route path="/reports/labor-overview" element={<LaborOverviewPage />} />
              <Route path="/reports/profitability" element={<ProfitabilityPage />} />
              <Route path="/reports/exports" element={<ExportsPage />} />

              {/* Settings */}
              <Route path="/settings" element={<Navigate to="/settings/themes" replace />} />
              <Route path="/settings/app-config" element={<AppConfigPage />} />
              <Route path="/settings/company-profile" element={<CompanyProfilePage />} />
              <Route path="/settings/themes" element={<ThemesPage />} />
              <Route path="/settings/notifications" element={<NotificationPrefsPage />} />
              <Route path="/settings/questions" element={<Navigate to="/office/clock-out-questions" replace />} />
              <Route path="/settings/sync" element={<SyncPage />} />
              <Route path="/settings/bootstrap" element={<BootstrapAdminPage />} />
              <Route path="/settings/supplier-bridge" element={<SupplierBridgePage />} />
              <Route path="/settings/updates" element={<UpdateProtocolPage />} />
              <Route path="/settings/ai-config" element={<AiConfigPage />} />
              <Route path="/settings/devices" element={<DeviceManagementPage />} />
              <Route path="/settings/security" element={<SecurityAdminPage />} />
              <Route path="/settings/about" element={<AboutPage />} />

              {/* Tools — QR scan redirect (cross-module) */}
              <Route path="/tools/scan/:toolNumber" element={<ToolScanRedirect />} />

              {/* Catch-all → Dashboard */}
              <Route path="*" element={<Navigate to="/dashboard" replace />} />
            </Route>
          </Routes>
        </AuthGate>
      </BrowserRouter>
    </QueryClientProvider>
  );
}
