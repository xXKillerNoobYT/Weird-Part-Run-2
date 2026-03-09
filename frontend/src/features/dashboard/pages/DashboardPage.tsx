/**
 * DashboardPage — main landing page after login.
 *
 * Shows:
 *   1. Welcome header (always visible)
 *   2. Tab bar: Overview | Daily Report (report tab permission-gated)
 *   3. Overview: Fast Drive, KPI cards, Quick Actions
 *   4. Daily Report: live pending actions, deliveries, budget alerts
 */

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import {
  LayoutDashboard,
  Package,
  Briefcase,
  ShoppingCart,
  AlertTriangle,
  Search,
  ArrowRightLeft,
  Loader2,
  Activity,
} from 'lucide-react';

import { Card, CardHeader } from '../../../components/ui/Card';
import { Badge } from '../../../components/ui/Badge';
import { FastDriveCard } from '../components/FastDriveCard';
import { DailyReportTab } from '../components/DailyReportTab';
import { getDashboard, getCertAlerts } from '../../../api/dashboard';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';


// ── Icon lookup for quick actions (backend sends icon name strings) ──

const ICON_MAP: Record<string, React.ReactNode> = {
  'briefcase':       <Briefcase className="h-5 w-5" />,
  'shopping-cart':   <ShoppingCart className="h-5 w-5" />,
  'search':          <Search className="h-5 w-5" />,
  'arrow-right-left': <ArrowRightLeft className="h-5 w-5" />,
  'package':         <Package className="h-5 w-5" />,
};


// ── KPI card config (maps backend keys to labels / icons / colors) ──

const KPI_CONFIG = [
  {
    key: 'total_parts' as const,
    label: 'Total Parts',
    icon: <Package className="h-5 w-5 text-blue-500" />,
    bg: 'bg-blue-50 dark:bg-blue-900/20',
  },
  {
    key: 'active_jobs' as const,
    label: 'Active Jobs',
    icon: <Briefcase className="h-5 w-5 text-green-500" />,
    bg: 'bg-green-50 dark:bg-green-900/20',
  },
  {
    key: 'pending_orders' as const,
    label: 'Pending Orders',
    icon: <ShoppingCart className="h-5 w-5 text-amber-500" />,
    bg: 'bg-amber-50 dark:bg-amber-900/20',
  },
  {
    key: 'low_stock_alerts' as const,
    label: 'Low Stock Alerts',
    icon: <AlertTriangle className="h-5 w-5 text-red-500" />,
    bg: 'bg-red-50 dark:bg-red-900/20',
  },
] as const;


type DashTab = 'overview' | 'report';


/** Reusable tab button for the dashboard tab bar */
function TabButton({
  label, icon, active, onClick,
}: {
  label: string; icon: React.ReactNode; active: boolean; onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className={`flex items-center gap-1.5 px-3 py-2 text-sm font-medium whitespace-nowrap border-b-2 transition-colors ${
        active
          ? 'border-blue-500 text-blue-600 dark:text-blue-400'
          : 'border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
      }`}
    >
      {icon}
      {label}
    </button>
  );
}


export function DashboardPage() {
  const navigate = useNavigate();
  const { hasPermission } = useAuthStore();
  const canSeeReport = hasPermission(PERMISSIONS.SHOW_DOLLAR_VALUES);

  const [activeTab, setActiveTab] = useState<DashTab>('overview');

  const canViewPeople = hasPermission(PERMISSIONS.VIEW_PEOPLE);

  const { data: dashboard, isLoading } = useQuery({
    queryKey: ['dashboard'],
    queryFn: getDashboard,
    staleTime: 30_000,  // refresh every 30s
  });

  const { data: certAlerts = [] } = useQuery({
    queryKey: ['cert-alerts'],
    queryFn: getCertAlerts,
    enabled: canViewPeople,
    staleTime: 60_000,
  });

  const kpis = dashboard?.kpis;

  return (
    <div className="space-y-6">
      {/* ── Welcome card ─────────────────────────────────── */}
      <Card>
        <div className="flex items-center gap-4">
          <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-primary-50 dark:bg-primary-900/20">
            <LayoutDashboard className="h-6 w-6 text-primary-500" />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">
              {dashboard
                ? `Welcome, ${dashboard.user_name}`
                : 'Welcome to Wired Part'}
            </h1>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              Your HVAC parts, trucks, and job management hub.
            </p>
          </div>
        </div>
      </Card>

      {/* ── Tab bar (only visible if user has report permission) ── */}
      {canSeeReport && (
        <div className="flex gap-1 border-b border-border overflow-x-auto">
          <TabButton
            label="Overview"
            icon={<LayoutDashboard className="h-4 w-4" />}
            active={activeTab === 'overview'}
            onClick={() => setActiveTab('overview')}
          />
          <TabButton
            label="Daily Report"
            icon={<Activity className="h-4 w-4" />}
            active={activeTab === 'report'}
            onClick={() => setActiveTab('report')}
          />
        </div>
      )}

      {/* ── Tab content ───────────────────────────────────── */}
      {activeTab === 'overview' && (
        <>
          {/* ── Fast Drive ──────────────────────────────── */}
          <FastDriveCard />

          {/* ── KPI grid ────────────────────────────────── */}
          <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
            {KPI_CONFIG.map((cfg) => (
              <Card key={cfg.key}>
                <div className="flex items-center gap-3 sm:gap-4">
                  <div
                    className={`flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-lg ${cfg.bg}`}
                  >
                    {cfg.icon}
                  </div>
                  <div className="min-w-0">
                    <p className="text-xs sm:text-sm font-medium text-gray-500 dark:text-gray-400 truncate">
                      {cfg.label}
                    </p>
                    {isLoading ? (
                      <Loader2 className="h-5 w-5 animate-spin text-gray-300 mt-1" />
                    ) : (
                      <p className="text-xl sm:text-2xl font-bold text-gray-900 dark:text-gray-100">
                        {kpis?.[cfg.key] ?? 0}
                      </p>
                    )}
                  </div>
                </div>
              </Card>
            ))}
          </div>

          {/* ── Cert Expiry Alerts ────────────────────── */}
          {canViewPeople && certAlerts.length > 0 && (
            <Card>
              <CardHeader
                title="Certification Alerts"
                subtitle={`${certAlerts.length} certification${certAlerts.length === 1 ? '' : 's'} expiring soon`}
              />
              <div className="space-y-2">
                {certAlerts.slice(0, 5).map((alert, i) => (
                  <button
                    key={`${alert.user_id}-${alert.cert_name}-${i}`}
                    onClick={() => navigate(`/people/employees/${alert.user_id}`)}
                    className="w-full flex items-center justify-between p-2.5 rounded-lg border border-gray-200 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors text-left"
                  >
                    <div className="min-w-0">
                      <p className="text-sm font-medium text-gray-900 dark:text-white truncate">
                        {alert.user_name}
                      </p>
                      <p className="text-xs text-gray-500 dark:text-gray-400 truncate">
                        {alert.cert_name} · Expires {alert.expiry_date}
                      </p>
                    </div>
                    <Badge
                      variant={alert.days_until_expiry <= 30 ? 'danger' : 'warning'}
                      className="text-xs ml-2 flex-shrink-0"
                    >
                      {alert.days_until_expiry <= 0
                        ? 'Expired'
                        : `${alert.days_until_expiry}d`}
                    </Badge>
                  </button>
                ))}
                {certAlerts.length > 5 && (
                  <p className="text-xs text-center text-gray-400 dark:text-gray-500 pt-1">
                    +{certAlerts.length - 5} more
                  </p>
                )}
              </div>
            </Card>
          )}

          {/* ── Quick Actions ───────────────────────────── */}
          <Card>
            <CardHeader
              title="Quick Actions"
              subtitle="Shortcuts to common tasks"
            />
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
              {(dashboard?.quick_actions ?? []).map((action) => (
                <button
                  key={action.label}
                  onClick={() => navigate(action.route)}
                  className="flex flex-col items-center gap-2 rounded-lg border border-gray-200 p-4 text-sm font-medium text-gray-600 transition-colors hover:bg-gray-50 dark:border-gray-700 dark:text-gray-300 dark:hover:bg-gray-800"
                >
                  {ICON_MAP[action.icon] ?? <Package className="h-5 w-5" />}
                  {action.label}
                </button>
              ))}
            </div>
          </Card>
        </>
      )}

      {activeTab === 'report' && canSeeReport && (
        <DailyReportTab />
      )}
    </div>
  );
}
