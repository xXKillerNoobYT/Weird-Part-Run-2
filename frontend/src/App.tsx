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

// Pages — Warehouse
import { WarehouseDashboardPage } from './features/warehouse/pages/WarehouseDashboardPage';
import { InventoryGridPage } from './features/warehouse/pages/InventoryGridPage';
import { StagingPage } from './features/warehouse/pages/StagingPage';
import { AuditPage } from './features/warehouse/pages/AuditPage';
import { MovementsLogPage } from './features/warehouse/pages/MovementsLogPage';
import { WarehouseToolsPage } from './features/warehouse/pages/ToolsPage';

// Pages — Trucks
import { MyTruckPage } from './features/trucks/pages/MyTruckPage';
import { AllTrucksPage } from './features/trucks/pages/AllTrucksPage';
import { ToolsPage } from './features/trucks/pages/ToolsPage';
import { MaintenancePage } from './features/trucks/pages/MaintenancePage';
import { MileagePage } from './features/trucks/pages/MileagePage';

// Pages — Jobs
import { ActiveJobsPage } from './features/jobs/pages/ActiveJobsPage';
import { MyClockPage } from './features/jobs/pages/MyClockPage';
import { JobDetailPage } from './features/jobs/pages/JobDetailPage';
import { JobReportsListPage } from './features/jobs/pages/JobReportsListPage';
import { DailyReportView } from './features/jobs/pages/DailyReportView';
import { TemplatesPage } from './features/jobs/pages/TemplatesPage';

// Pages — Orders
import { DraftOrdersPage } from './features/orders/pages/DraftOrdersPage';
import { PendingOrdersPage } from './features/orders/pages/PendingOrdersPage';
import { IncomingOrdersPage } from './features/orders/pages/IncomingOrdersPage';
import { ReturnsPage } from './features/orders/pages/ReturnsPage';
import { ProcurementPage } from './features/orders/pages/ProcurementPage';

// Pages — People
import { EmployeeListPage } from './features/people/pages/EmployeeListPage';
import { HatsPage } from './features/people/pages/HatsPage';
import { PermissionsPage } from './features/people/pages/PermissionsPage';

// Pages — Reports
import { PreBillingPage } from './features/reports/pages/PreBillingPage';
import { TimesheetsPage } from './features/reports/pages/TimesheetsPage';
import { LaborOverviewPage } from './features/reports/pages/LaborOverviewPage';
import { ExportsPage } from './features/reports/pages/ExportsPage';

// Pages — Settings
import { AppConfigPage } from './features/settings/pages/AppConfigPage';
import { ThemesPage } from './features/settings/pages/ThemesPage';
import { SyncPage } from './features/settings/pages/SyncPage';
import { AiConfigPage } from './features/settings/pages/AiConfigPage';
import { DeviceManagementPage } from './features/settings/pages/DeviceManagementPage';
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

              {/* Warehouse */}
              <Route path="/warehouse" element={<Navigate to="/warehouse/dashboard" replace />} />
              <Route path="/warehouse/dashboard" element={<WarehouseDashboardPage />} />
              <Route path="/warehouse/inventory" element={<InventoryGridPage />} />
              <Route path="/warehouse/staging" element={<StagingPage />} />
              <Route path="/warehouse/audit" element={<AuditPage />} />
              <Route path="/warehouse/movements" element={<MovementsLogPage />} />
              <Route path="/warehouse/tools" element={<WarehouseToolsPage />} />

              {/* Trucks */}
              <Route path="/trucks" element={<Navigate to="/trucks/my-truck" replace />} />
              <Route path="/trucks/my-truck" element={<MyTruckPage />} />
              <Route path="/trucks/all" element={<AllTrucksPage />} />
              <Route path="/trucks/tools" element={<ToolsPage />} />
              <Route path="/trucks/maintenance" element={<MaintenancePage />} />
              <Route path="/trucks/mileage" element={<MileagePage />} />

              {/* Jobs */}
              <Route path="/jobs" element={<Navigate to="/jobs/active" replace />} />
              <Route path="/jobs/active" element={<ActiveJobsPage />} />
              <Route path="/jobs/my-clock" element={<MyClockPage />} />
              <Route path="/jobs/reports" element={<JobReportsListPage />} />
              <Route path="/jobs/templates" element={<TemplatesPage />} />
              <Route path="/jobs/:id" element={<JobDetailPage />} />
              <Route path="/jobs/:id/report/:date" element={<DailyReportView />} />

              {/* Orders */}
              <Route path="/orders" element={<Navigate to="/orders/drafts" replace />} />
              <Route path="/orders/drafts" element={<DraftOrdersPage />} />
              <Route path="/orders/pending" element={<PendingOrdersPage />} />
              <Route path="/orders/incoming" element={<IncomingOrdersPage />} />
              <Route path="/orders/returns" element={<ReturnsPage />} />
              <Route path="/orders/procurement" element={<ProcurementPage />} />

              {/* People */}
              <Route path="/people" element={<Navigate to="/people/employees" replace />} />
              <Route path="/people/employees" element={<EmployeeListPage />} />
              <Route path="/people/hats" element={<HatsPage />} />
              <Route path="/people/permissions" element={<PermissionsPage />} />

              {/* Reports */}
              <Route path="/reports" element={<Navigate to="/reports/pre-billing" replace />} />
              <Route path="/reports/pre-billing" element={<PreBillingPage />} />
              <Route path="/reports/timesheets" element={<TimesheetsPage />} />
              <Route path="/reports/labor-overview" element={<LaborOverviewPage />} />
              <Route path="/reports/exports" element={<ExportsPage />} />

              {/* Settings */}
              <Route path="/settings" element={<Navigate to="/settings/themes" replace />} />
              <Route path="/settings/app-config" element={<AppConfigPage />} />
              <Route path="/settings/themes" element={<ThemesPage />} />
              <Route path="/settings/questions" element={<ClockOutQuestionsPage />} />
              <Route path="/settings/sync" element={<SyncPage />} />
              <Route path="/settings/ai-config" element={<AiConfigPage />} />
              <Route path="/settings/devices" element={<DeviceManagementPage />} />

              {/* Catch-all → Dashboard */}
              <Route path="*" element={<Navigate to="/dashboard" replace />} />
            </Route>
          </Routes>
        </AuthGate>
      </BrowserRouter>
    </QueryClientProvider>
  );
}
