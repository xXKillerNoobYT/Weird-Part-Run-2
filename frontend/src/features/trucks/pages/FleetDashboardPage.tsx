/**
 * FleetDashboardPage — manager-level fleet KPI dashboard.
 *
 * Shows fleet-wide statistics: vehicle counts, maintenance health,
 * monthly mileage, maintenance costs, and pending reimbursements.
 * Accessible via Trucks > Fleet tab (requires manage_fleet permission).
 */

import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import {
  Truck,
  Car,
  Wrench,
  AlertTriangle,
  Gauge,
  DollarSign,
  Clock,
  CheckCircle,
  XCircle,
  ChevronRight,
  Users,
  Shield,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { Badge } from '../../../components/ui/Badge';
import {
  getFleetDashboard,
  getOverdueMaintenance,
  getUpcomingMaintenance,
} from '../../../api/vehicles';
import type { FleetDashboardStats, MaintenanceAlert } from '../../../lib/types';

export function FleetDashboardPage() {
  const navigate = useNavigate();

  const { data: stats, isLoading, error } = useQuery({
    queryKey: ['fleet-dashboard'],
    queryFn: getFleetDashboard,
    staleTime: 30_000,
  });

  const { data: overdue } = useQuery({
    queryKey: ['maintenance-overdue'],
    queryFn: () => getOverdueMaintenance(),
    staleTime: 30_000,
  });

  const { data: upcoming } = useQuery({
    queryKey: ['maintenance-upcoming', 14],
    queryFn: () => getUpcomingMaintenance({ days_ahead: 14 }),
    staleTime: 30_000,
  });

  if (isLoading) return <PageSpinner label="Loading fleet dashboard..." />;

  if (error || !stats) {
    return (
      <div className="text-center py-16">
        <p className="text-red-500">Failed to load fleet dashboard.</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* ── Vehicle Stats Grid ── */}
      <div>
        <h3 className="text-sm font-medium text-gray-500 dark:text-gray-400 mb-3">Fleet Overview</h3>
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
          <KpiCard
            label="Total Vehicles"
            value={stats.total_vehicles}
            icon={<Truck className="h-5 w-5" />}
            color="blue"
          />
          <KpiCard
            label="Active"
            value={stats.active_vehicles}
            icon={<CheckCircle className="h-5 w-5" />}
            color="green"
          />
          <KpiCard
            label="In Maintenance"
            value={stats.in_maintenance}
            icon={<Wrench className="h-5 w-5" />}
            color="amber"
          />
          <KpiCard
            label="Retired"
            value={stats.retired_vehicles}
            icon={<XCircle className="h-5 w-5" />}
            color="gray"
          />
          <KpiCard
            label="Company"
            value={stats.company_vehicles}
            icon={<Truck className="h-5 w-5" />}
            color="blue"
          />
          <KpiCard
            label="Private"
            value={stats.private_vehicles}
            icon={<Car className="h-5 w-5" />}
            color="purple"
          />
        </div>
      </div>

      {/* ── Operational Metrics ── */}
      <div>
        <h3 className="text-sm font-medium text-gray-500 dark:text-gray-400 mb-3">Monthly Metrics</h3>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <MetricCard
            label="Fleet Miles (Month)"
            value={`${stats.total_fleet_miles_month.toLocaleString()} mi`}
            icon={<Gauge className="h-4 w-4" />}
          />
          <MetricCard
            label="Maintenance Cost (Month)"
            value={`$${stats.total_maintenance_cost_month.toLocaleString(undefined, { minimumFractionDigits: 2 })}`}
            icon={<DollarSign className="h-4 w-4" />}
          />
          <MetricCard
            label="Pending Reimbursements"
            value={String(stats.pending_reimbursements)}
            icon={<DollarSign className="h-4 w-4" />}
            onClick={() => navigate('/trucks/mileage')}
            highlight={stats.pending_reimbursements > 0}
          />
          <MetricCard
            label="Needing Inspection"
            value={String(stats.vehicles_needing_inspection)}
            icon={<Shield className="h-4 w-4" />}
            highlight={stats.vehicles_needing_inspection > 0}
          />
        </div>
      </div>

      {/* ── Maintenance Health ── */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {/* Overdue */}
        <div className="bg-surface border border-border rounded-xl">
          <div className="flex items-center justify-between p-4 border-b border-border">
            <div className="flex items-center gap-2">
              <AlertTriangle className="h-4 w-4 text-red-500" />
              <h3 className="text-sm font-medium text-gray-900 dark:text-gray-100">Overdue Maintenance</h3>
              {stats.overdue_maintenance_count > 0 && (
                <Badge variant="destructive">{stats.overdue_maintenance_count}</Badge>
              )}
            </div>
            <button
              onClick={() => navigate('/trucks/maintenance')}
              className="text-xs text-blue-500 hover:text-blue-700 dark:hover:text-blue-300 flex items-center gap-0.5"
            >
              View All <ChevronRight className="h-3 w-3" />
            </button>
          </div>
          <div className="divide-y divide-border max-h-64 overflow-y-auto">
            {!overdue || overdue.length === 0 ? (
              <p className="text-sm text-gray-400 dark:text-gray-500 text-center py-6">
                No overdue maintenance — great job!
              </p>
            ) : (
              overdue.slice(0, 5).map((alert) => (
                <AlertRow
                  key={`${alert.vehicle_id}-${alert.maintenance_type_id}`}
                  alert={alert}
                  onClick={() => navigate(`/trucks/${alert.vehicle_id}`)}
                />
              ))
            )}
          </div>
        </div>

        {/* Upcoming */}
        <div className="bg-surface border border-border rounded-xl">
          <div className="flex items-center justify-between p-4 border-b border-border">
            <div className="flex items-center gap-2">
              <Clock className="h-4 w-4 text-amber-500" />
              <h3 className="text-sm font-medium text-gray-900 dark:text-gray-100">Upcoming (14 Days)</h3>
              {stats.upcoming_maintenance_count > 0 && (
                <Badge variant="warning">{stats.upcoming_maintenance_count}</Badge>
              )}
            </div>
            <button
              onClick={() => navigate('/trucks/maintenance')}
              className="text-xs text-blue-500 hover:text-blue-700 dark:hover:text-blue-300 flex items-center gap-0.5"
            >
              View All <ChevronRight className="h-3 w-3" />
            </button>
          </div>
          <div className="divide-y divide-border max-h-64 overflow-y-auto">
            {!upcoming || upcoming.length === 0 ? (
              <p className="text-sm text-gray-400 dark:text-gray-500 text-center py-6">
                No upcoming maintenance in the next 14 days
              </p>
            ) : (
              upcoming.slice(0, 5).map((alert) => (
                <AlertRow
                  key={`${alert.vehicle_id}-${alert.maintenance_type_id}`}
                  alert={alert}
                  onClick={() => navigate(`/trucks/${alert.vehicle_id}`)}
                />
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  );
}


// ── KPI Card ──────────────────────────────────────────────────────────

function KpiCard({
  label,
  value,
  icon,
  color,
}: {
  label: string;
  value: number;
  icon: React.ReactNode;
  color: 'blue' | 'green' | 'amber' | 'gray' | 'purple' | 'red';
}) {
  const colors = {
    blue: 'bg-blue-50 dark:bg-blue-900/20 text-blue-600 dark:text-blue-400',
    green: 'bg-green-50 dark:bg-green-900/20 text-green-600 dark:text-green-400',
    amber: 'bg-amber-50 dark:bg-amber-900/20 text-amber-600 dark:text-amber-400',
    gray: 'bg-gray-50 dark:bg-gray-800/50 text-gray-500 dark:text-gray-400',
    purple: 'bg-purple-50 dark:bg-purple-900/20 text-purple-600 dark:text-purple-400',
    red: 'bg-red-50 dark:bg-red-900/20 text-red-600 dark:text-red-400',
  };

  return (
    <div className="bg-surface border border-border rounded-xl p-3">
      <div className={`inline-flex items-center justify-center h-8 w-8 rounded-lg ${colors[color]} mb-2`}>
        {icon}
      </div>
      <p className="text-2xl font-bold text-gray-900 dark:text-gray-100">{value}</p>
      <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">{label}</p>
    </div>
  );
}


// ── Metric Card ───────────────────────────────────────────────────────

function MetricCard({
  label,
  value,
  icon,
  onClick,
  highlight,
}: {
  label: string;
  value: string;
  icon: React.ReactNode;
  onClick?: () => void;
  highlight?: boolean;
}) {
  return (
    <div
      className={`bg-surface border rounded-xl p-3 ${
        highlight
          ? 'border-amber-300 dark:border-amber-700'
          : 'border-border'
      } ${onClick ? 'cursor-pointer hover:border-blue-300 dark:hover:border-blue-600 transition-colors' : ''}`}
      onClick={onClick}
    >
      <div className="flex items-center gap-1.5 mb-1.5">
        <span className="text-gray-400 dark:text-gray-500">{icon}</span>
        <span className="text-xs text-gray-500 dark:text-gray-400">{label}</span>
      </div>
      <p className="text-lg font-bold text-gray-900 dark:text-gray-100 font-mono">{value}</p>
    </div>
  );
}


// ── Alert Row ─────────────────────────────────────────────────────────

function AlertRow({ alert, onClick }: { alert: MaintenanceAlert; onClick: () => void }) {
  return (
    <div
      className="flex items-center justify-between px-4 py-2.5 hover:bg-gray-50 dark:hover:bg-gray-800/50 cursor-pointer transition-colors"
      onClick={onClick}
    >
      <div className="min-w-0">
        <div className="flex items-center gap-2">
          <span className="text-xs font-mono text-gray-500 dark:text-gray-400">
            {alert.vehicle_number}
          </span>
          <span className="text-sm text-gray-900 dark:text-gray-100 truncate">
            {alert.maintenance_type_name}
          </span>
        </div>
      </div>
      <div className="text-xs shrink-0 ml-2">
        {alert.is_overdue ? (
          <span className="text-red-600 dark:text-red-400 font-medium">Overdue</span>
        ) : alert.days_until_due != null ? (
          <span className="text-amber-600 dark:text-amber-400">{alert.days_until_due}d</span>
        ) : alert.miles_until_due != null ? (
          <span className="text-amber-600 dark:text-amber-400">{alert.miles_until_due.toLocaleString()} mi</span>
        ) : null}
      </div>
    </div>
  );
}
