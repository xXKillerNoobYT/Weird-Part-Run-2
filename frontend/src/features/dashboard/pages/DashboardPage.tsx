/**
 * DashboardPage — main landing page after login.
 *
 * Shows a welcome card and four KPI placeholder cards.
 * KPIs will be wired to real data once the backend APIs are connected.
 */

import {
  LayoutDashboard,
  Package,
  Briefcase,
  Clock,
  AlertTriangle,
} from 'lucide-react';
import { Card, CardHeader } from '../../../components/ui/Card';

const kpis = [
  {
    label: 'Total Parts',
    value: 0,
    icon: <Package className="h-5 w-5 text-blue-500" />,
    color: 'bg-blue-50 dark:bg-blue-900/20',
  },
  {
    label: 'Active Jobs',
    value: 0,
    icon: <Briefcase className="h-5 w-5 text-green-500" />,
    color: 'bg-green-50 dark:bg-green-900/20',
  },
  {
    label: 'Pending Orders',
    value: 0,
    icon: <Clock className="h-5 w-5 text-amber-500" />,
    color: 'bg-amber-50 dark:bg-amber-900/20',
  },
  {
    label: 'Low Stock Alerts',
    value: 0,
    icon: <AlertTriangle className="h-5 w-5 text-red-500" />,
    color: 'bg-red-50 dark:bg-red-900/20',
  },
] as const;

export function DashboardPage() {
  return (
    <div className="space-y-6">
      {/* Welcome card */}
      <Card>
        <div className="flex items-center gap-4">
          <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-primary-50 dark:bg-primary-900/20">
            <LayoutDashboard className="h-6 w-6 text-primary-500" />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">
              Welcome to Wired Part
            </h1>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              Your HVAC parts, trucks, and job management hub. Here's today's snapshot.
            </p>
          </div>
        </div>
      </Card>

      {/* KPI grid */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {kpis.map((kpi) => (
          <Card key={kpi.label}>
            <div className="flex items-center gap-4">
              <div
                className={`flex h-10 w-10 items-center justify-center rounded-lg ${kpi.color}`}
              >
                {kpi.icon}
              </div>
              <div>
                <p className="text-sm font-medium text-gray-500 dark:text-gray-400">
                  {kpi.label}
                </p>
                <p className="text-2xl font-bold text-gray-900 dark:text-gray-100">
                  {kpi.value}
                </p>
              </div>
            </div>
          </Card>
        ))}
      </div>

      {/* Quick actions placeholder */}
      <Card>
        <CardHeader
          title="Quick Actions"
          subtitle="Shortcuts to common tasks"
        />
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {[
            { label: 'New Job', icon: <Briefcase className="h-5 w-5" /> },
            { label: 'Create PO', icon: <Package className="h-5 w-5" /> },
            { label: 'Stock Check', icon: <AlertTriangle className="h-5 w-5" /> },
            { label: 'Pull Parts', icon: <Clock className="h-5 w-5" /> },
          ].map((action) => (
            <button
              key={action.label}
              className="flex flex-col items-center gap-2 rounded-lg border border-gray-200 p-4 text-sm font-medium text-gray-600 transition-colors hover:bg-gray-50 dark:border-gray-700 dark:text-gray-300 dark:hover:bg-gray-800"
            >
              {action.icon}
              {action.label}
            </button>
          ))}
        </div>
      </Card>
    </div>
  );
}
