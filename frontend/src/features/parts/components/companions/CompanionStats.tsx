/**
 * CompanionStats — KPI cards row for the companion dashboard.
 *
 * Shows: Active Rules, Pending Suggestions, Approved, Discarded, Co-occurrence Pairs.
 */

import { useQuery } from '@tanstack/react-query';
import { BookOpen, Clock, CheckCircle, XCircle, GitBranch } from 'lucide-react';
import { Card } from '../../../../components/ui/Card';
import { Spinner } from '../../../../components/ui/Spinner';
import { getCompanionStats } from '../../../../api/parts';

export function CompanionStats() {
  const { data: stats, isLoading } = useQuery({
    queryKey: ['companion-stats'],
    queryFn: getCompanionStats,
    staleTime: 15_000,
  });

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-6">
        <Spinner />
      </div>
    );
  }

  const kpis = [
    {
      label: 'Active Rules',
      value: stats?.active_rules ?? 0,
      total: stats?.total_rules,
      icon: BookOpen,
      color: 'text-blue-600 dark:text-blue-400',
      bg: 'bg-blue-50 dark:bg-blue-900/30',
    },
    {
      label: 'Pending',
      value: stats?.pending_suggestions ?? 0,
      icon: Clock,
      color: 'text-amber-600 dark:text-amber-400',
      bg: 'bg-amber-50 dark:bg-amber-900/30',
    },
    {
      label: 'Approved',
      value: stats?.approved_count ?? 0,
      icon: CheckCircle,
      color: 'text-green-600 dark:text-green-400',
      bg: 'bg-green-50 dark:bg-green-900/30',
    },
    {
      label: 'Discarded',
      value: stats?.discarded_count ?? 0,
      icon: XCircle,
      color: 'text-red-600 dark:text-red-400',
      bg: 'bg-red-50 dark:bg-red-900/30',
    },
    {
      label: 'Learned Pairs',
      value: stats?.co_occurrence_pairs ?? 0,
      icon: GitBranch,
      color: 'text-purple-600 dark:text-purple-400',
      bg: 'bg-purple-50 dark:bg-purple-900/30',
    },
  ];

  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
      {kpis.map((kpi) => (
        <Card key={kpi.label} className="p-4">
          <div className="flex items-center gap-3">
            <div className={`p-2 rounded-lg ${kpi.bg}`}>
              <kpi.icon className={`h-5 w-5 ${kpi.color}`} />
            </div>
            <div>
              <p className="text-2xl font-bold text-gray-900 dark:text-gray-100">
                {kpi.value}
                {kpi.total !== undefined && (
                  <span className="text-sm font-normal text-gray-400 ml-1">
                    /{kpi.total}
                  </span>
                )}
              </p>
              <p className="text-xs text-gray-500 dark:text-gray-400">
                {kpi.label}
              </p>
            </div>
          </div>
        </Card>
      ))}
    </div>
  );
}
