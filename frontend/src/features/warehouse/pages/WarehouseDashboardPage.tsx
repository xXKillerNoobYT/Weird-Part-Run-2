/**
 * WarehouseDashboardPage — warehouse overview and status at a glance.
 *
 * Shows KPI cards, quick action buttons, recent activity feed,
 * and pending tasks (staged items, audits, spot-checks).
 *
 * The FAB (floating action button) opens the movement wizard
 * and is visible on all warehouse pages for users with permission.
 *
 * ── DEV NOTE: Tools at Warehouse ──────────────────────────────
 * The Warehouse Dashboard should include a "Tools" section/panel that:
 *  1. Shows all tools currently stored at the warehouse
 *  2. Provides the ability to add NEW tools to the system (tool registration)
 *  3. Shows a summary of where all company tools currently are
 *     (which trucks have which tools, which jobs, which are at warehouse)
 *  4. Acts as the "master tools registry" — the primary place to manage
 *     the full tool inventory across the entire company
 *
 * The Trucks > Tools tab manages tools assigned per-truck.
 * The Jobs dashboard should show tools checked out to that job.
 * But the Warehouse Dashboard is the global view / tool admin center.
 * ── Stubbed for Phase 6 ──────────────────────────────────────
 */

import { useQuery } from '@tanstack/react-query';
import { Plus, Wrench } from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { Card, CardHeader } from '../../../components/ui/Card';
import { Button } from '../../../components/ui/Button';
import { getDashboard } from '../../../api/warehouse';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import { useMovementWizardStore } from '../stores/movement-wizard-store';
import { MovementWizard } from '../components/wizard/MovementWizard';
import { KpiCards } from '../components/dashboard/KpiCards';
import { QuickActions } from '../components/dashboard/QuickActions';
import { RecentActivityFeed } from '../components/dashboard/RecentActivityFeed';
import { PendingTasksList } from '../components/dashboard/PendingTasksList';

export function WarehouseDashboardPage() {
  const { hasPermission } = useAuthStore();
  const canMove = hasPermission(PERMISSIONS.MOVE_STOCK_WAREHOUSE);
  const { open: openWizard } = useMovementWizardStore();

  const { data: dashboard, isLoading, error } = useQuery({
    queryKey: ['warehouse-dashboard'],
    queryFn: getDashboard,
    staleTime: 30_000, // 30s — light polling via refetchOnWindowFocus
    refetchOnWindowFocus: true,
  });

  if (isLoading) {
    return <PageSpinner label="Loading dashboard..." />;
  }

  if (error || !dashboard) {
    return (
      <div className="text-center py-16">
        <p className="text-sm text-red-600 dark:text-red-400">
          Failed to load dashboard. Please refresh the page.
        </p>
      </div>
    );
  }

  return (
    <>
      <div className="space-y-6">
        {/* KPI Cards */}
        <KpiCards kpis={dashboard.kpis} />

        {/* Main grid: 2 columns on desktop */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Left column */}
          <div className="space-y-6">
            <QuickActions />
            <RecentActivityFeed activity={dashboard.recent_activity} />
          </div>

          {/* Right column */}
          <div className="space-y-6">
            <PendingTasksList tasks={dashboard.pending_tasks} />

            {/* Tools stub — Phase 6 */}
            <Card>
              <CardHeader title="Tools Registry" />
              <div className="flex flex-col items-center py-8 gap-3">
                <Wrench className="h-8 w-8 text-gray-400 dark:text-gray-500" />
                <p className="text-sm text-gray-500 dark:text-gray-400 text-center max-w-xs">
                  Tool tracking and registration coming in a future update.
                </p>
              </div>
            </Card>
          </div>
        </div>
      </div>

      {/* FAB — Floating Action Button for new movement */}
      {canMove && (
        <button
          onClick={() => openWizard()}
          className="fixed bottom-6 right-6 z-40 flex items-center justify-center w-14 h-14 rounded-full bg-primary-500 text-white shadow-lg hover:bg-primary-600 active:bg-primary-700 transition-colors focus:outline-none focus:ring-4 focus:ring-primary-300 dark:focus:ring-primary-800"
          aria-label="New Stock Movement"
        >
          <Plus className="h-6 w-6" />
        </button>
      )}

      {/* Movement Wizard (renders when open) */}
      <MovementWizard />
    </>
  );
}
