/**
 * StagingPage — pulled items grouped by destination with aging colors,
 * plus a "Pending Pull" section for JPO items received but not yet staged.
 *
 * Shows items that have been pulled from warehouse shelves and are
 * waiting to be loaded onto trucks or dispatched to jobs.
 * Color coding: normal (< 24h), yellow (24-48h), red (> 48h).
 *
 * The Pending Pull section shows items from approved JPOs that have been
 * received into the warehouse but not yet pulled — giving warehouse staff
 * visibility into what still needs to be staged.
 *
 * The FAB (floating action button) opens the movement wizard pre-filled
 * for "warehouse → pulled" so users can quickly stage more items.
 */

import { useState, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  PackageCheck, Plus, AlertTriangle, Package, ArrowUpDown,
  Inbox, ChevronDown, ChevronRight,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Badge } from '../../../components/ui/Badge';
import { Card } from '../../../components/ui/Card';
import { Button } from '../../../components/ui/Button';
import { getStagingGroups, getPendingPulls } from '../../../api/warehouse';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import { useMovementWizardStore } from '../stores/movement-wizard-store';
import { MovementWizard } from '../components/wizard/MovementWizard';
import { StagingCard } from '../components/staging/StagingCard';
import type { StagingGroup, PendingPullGroup, PendingPullItem } from '../../../lib/types';

type SortOption = 'oldest' | 'newest' | 'most_items';

export function StagingPage() {
  const { hasPermission } = useAuthStore();
  const canMove = hasPermission(PERMISSIONS.MOVE_STOCK_WAREHOUSE);
  const { open: openWizard } = useMovementWizardStore();
  const [sort, setSort] = useState<SortOption>('oldest');
  const [expandedPendingJobs, setExpandedPendingJobs] = useState<Set<number | null>>(new Set());

  const { data: groups, isLoading } = useQuery({
    queryKey: ['warehouse-staging'],
    queryFn: getStagingGroups,
    staleTime: 15_000,
    refetchOnWindowFocus: true,
  });

  const { data: pendingPulls, isLoading: pendingLoading } = useQuery({
    queryKey: ['warehouse-pending-pulls'],
    queryFn: getPendingPulls,
    staleTime: 30_000,
    refetchOnWindowFocus: true,
  });

  /** Open wizard pre-filled for warehouse → pulled (staging). */
  const handlePullStock = () => {
    openWizard({
      fromLocationType: 'warehouse',
      toLocationType: 'pulled',
    });
  };

  const togglePendingJob = (jobId: number | null) => {
    setExpandedPendingJobs(prev => {
      const next = new Set(prev);
      if (next.has(jobId)) next.delete(jobId);
      else next.add(jobId);
      return next;
    });
  };

  const sortedGroups = useMemo<StagingGroup[]>(() => {
    if (!groups) return [];
    const g = [...groups];
    if (sort === 'oldest') return g.sort((a, b) => b.oldest_hours - a.oldest_hours);
    if (sort === 'newest') return g.sort((a, b) => a.oldest_hours - b.oldest_hours);
    if (sort === 'most_items') return g.sort((a, b) => b.total_qty - a.total_qty);
    return g;
  }, [groups, sort]);

  const totalPendingItems = pendingPulls?.reduce((s, g) => s + g.total_pending, 0) ?? 0;
  const hasPendingPulls = pendingPulls && pendingPulls.length > 0;

  if (isLoading && pendingLoading) {
    return <PageSpinner label="Loading staging area..." />;
  }

  const hasStaged = groups && groups.length > 0;

  if (!hasStaged && !hasPendingPulls) {
    return (
      <>
        <EmptyState
          icon={<PackageCheck className="h-12 w-12" />}
          title="No Staged Items"
          description="Nothing has been pulled from the shelves yet. Use the + button to pull items from the warehouse to the staging area."
        />
        {canMove && (
          <button
            onClick={handlePullStock}
            className="fixed bottom-6 right-6 z-40 flex items-center justify-center w-14 h-14 rounded-full bg-primary-500 text-white shadow-lg hover:bg-primary-600 active:bg-primary-700 transition-colors focus:outline-none focus:ring-4 focus:ring-primary-300 dark:focus:ring-primary-800"
            aria-label="Pull Stock to Staging"
          >
            <Plus className="h-6 w-6" />
          </button>
        )}
        <MovementWizard />
      </>
    );
  }

  // Summary stats
  const totalUnits = groups?.reduce((s, g) => s + g.total_qty, 0) ?? 0;
  const totalParts = groups?.reduce((s, g) => s + g.items.length, 0) ?? 0;
  const overdueGroups = groups?.filter(g => g.aging_status === 'critical').length ?? 0;
  const warningGroups = groups?.filter(g => g.aging_status === 'warning').length ?? 0;

  return (
    <>
      {/* ── Pending Pulls Section ─────────────────────────────── */}
      {hasPendingPulls && (
        <div className="mb-6">
          <div className="flex items-center gap-2 mb-3">
            <Inbox size={18} className="text-amber-500" />
            <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
              Pending Pulls
            </h2>
            <Badge variant="warning">
              {totalPendingItems} unit{totalPendingItems !== 1 ? 's' : ''} across{' '}
              {pendingPulls.length} job{pendingPulls.length !== 1 ? 's' : ''}
            </Badge>
          </div>
          <p className="text-xs text-gray-500 dark:text-gray-400 mb-3">
            Items received from suppliers but not yet pulled from warehouse shelves.
          </p>

          <div className="space-y-2">
            {pendingPulls.map((group) => (
              <PendingPullCard
                key={group.job_id ?? 'no-job'}
                group={group}
                expanded={expandedPendingJobs.has(group.job_id)}
                onToggle={() => togglePendingJob(group.job_id)}
                onPull={canMove ? handlePullStock : undefined}
              />
            ))}
          </div>
        </div>
      )}

      {/* ── Already-Pulled / Staged Section ───────────────────── */}
      {hasStaged && (
        <>
          <div className="mb-4 flex items-center justify-between flex-wrap gap-3">
            <div className="flex items-center gap-4 flex-wrap">
              <div className="flex items-center gap-1.5 text-sm text-gray-700 dark:text-gray-300">
                <Package size={16} className="text-gray-400 dark:text-gray-500 flex-shrink-0" />
                <span className="font-semibold">{(groups ?? []).length}</span>
                <span className="text-gray-500 dark:text-gray-400">
                  destination{(groups ?? []).length !== 1 ? 's' : ''}
                </span>
                <span className="text-gray-400 dark:text-gray-500">&middot;</span>
                <span className="font-semibold">{totalUnits}</span>
                <span className="text-gray-500 dark:text-gray-400">
                  unit{totalUnits !== 1 ? 's' : ''}
                </span>
                <span className="text-gray-400 dark:text-gray-500">&middot;</span>
                <span className="font-semibold">{totalParts}</span>
                <span className="text-gray-500 dark:text-gray-400">
                  line item{totalParts !== 1 ? 's' : ''}
                </span>
              </div>
              {overdueGroups > 0 && (
                <Badge variant="danger" className="flex items-center gap-1">
                  <AlertTriangle size={11} />
                  {overdueGroups} overdue (&gt;48h)
                </Badge>
              )}
              {warningGroups > 0 && (
                <Badge variant="warning">
                  {warningGroups} aging (&gt;24h)
                </Badge>
              )}
            </div>

            {/* Sort control */}
            <div className="flex items-center gap-1.5">
              <ArrowUpDown size={13} className="text-gray-400 dark:text-gray-500 flex-shrink-0" />
              <select
                value={sort}
                onChange={e => setSort(e.target.value as SortOption)}
                className="text-xs rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-300 px-2 py-1.5"
              >
                <option value="oldest">Oldest first</option>
                <option value="newest">Newest first</option>
                <option value="most_items">Most items first</option>
              </select>
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
            {sortedGroups.map((group, i) => (
              <StagingCard
                key={`${group.destination_type}-${group.destination_id}-${i}`}
                group={group}
              />
            ))}
          </div>
        </>
      )}

      {/* FAB — Pull Stock */}
      {canMove && (
        <button
          onClick={handlePullStock}
          className="fixed bottom-6 right-6 z-40 flex items-center justify-center w-14 h-14 rounded-full bg-primary-500 text-white shadow-lg hover:bg-primary-600 active:bg-primary-700 transition-colors focus:outline-none focus:ring-4 focus:ring-primary-300 dark:focus:ring-primary-800"
          aria-label="Pull Stock to Staging"
        >
          <Plus className="h-6 w-6" />
        </button>
      )}
      <MovementWizard />
    </>
  );
}


/* ─── Pending Pull Card ─────────────────────────────────────────── */

function PendingPullCard({
  group,
  expanded,
  onToggle,
  onPull,
}: {
  group: PendingPullGroup;
  expanded: boolean;
  onToggle: () => void;
  onPull?: () => void;
}) {
  const jobLabel = group.job_number
    ? `${group.job_number} — ${group.job_name ?? 'Unnamed Job'}`
    : group.job_name ?? 'No Job Assigned';

  return (
    <Card className="overflow-hidden">
      {/* Collapsible header */}
      <button
        onClick={onToggle}
        className="w-full flex items-center justify-between px-4 py-3 text-left hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors"
      >
        <div className="flex items-center gap-3 min-w-0">
          {expanded
            ? <ChevronDown size={16} className="text-gray-400 flex-shrink-0" />
            : <ChevronRight size={16} className="text-gray-400 flex-shrink-0" />
          }
          <div className="min-w-0">
            <p className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
              {jobLabel}
            </p>
            <p className="text-xs text-gray-500 dark:text-gray-400">
              {group.items.length} part{group.items.length !== 1 ? 's' : ''} &middot;{' '}
              <span className="font-medium text-amber-600 dark:text-amber-400">
                {group.total_pending} unit{group.total_pending !== 1 ? 's' : ''} pending
              </span>
              {group.total_already_pulled > 0 && (
                <>
                  {' '}&middot;{' '}
                  <span className="text-green-600 dark:text-green-400">
                    {group.total_already_pulled} already pulled
                  </span>
                </>
              )}
            </p>
          </div>
        </div>

        {/* Quick-pull action */}
        {onPull && (
          <Button
            size="sm"
            variant="primary"
            onClick={(e) => { e.stopPropagation(); onPull(); }}
            className="flex-shrink-0 ml-2"
          >
            Pull
          </Button>
        )}
      </button>

      {/* Expanded line items */}
      {expanded && (
        <div className="border-t border-gray-200 dark:border-gray-700">
          <table className="w-full text-xs">
            <thead>
              <tr className="bg-gray-50 dark:bg-gray-800/30 text-gray-500 dark:text-gray-400">
                <th className="text-left px-4 py-2 font-medium">Part</th>
                <th className="text-right px-4 py-2 font-medium">In WH</th>
                <th className="text-right px-4 py-2 font-medium">Received</th>
                <th className="text-right px-4 py-2 font-medium">Pulled</th>
                <th className="text-right px-4 py-2 font-medium">Pending</th>
                <th className="text-left px-4 py-2 font-medium">Priority</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100 dark:divide-gray-700/50">
              {group.items.map((item) => (
                <PendingPullRow key={item.jpo_line_id} item={item} />
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Card>
  );
}


function PendingPullRow({ item }: { item: PendingPullItem }) {
  const priorityBadge = item.priority === 'critical'
    ? <Badge variant="danger">critical</Badge>
    : item.priority === 'urgent'
      ? <Badge variant="warning">urgent</Badge>
      : <Badge variant="neutral">normal</Badge>;

  const canFulfill = item.warehouse_qty >= item.qty_pending;

  return (
    <tr className="hover:bg-gray-50/50 dark:hover:bg-gray-800/20">
      <td className="px-4 py-2">
        <div className="font-medium text-gray-900 dark:text-gray-100 truncate max-w-[200px]">
          {item.part_name}
        </div>
        {item.part_code && (
          <div className="text-gray-400 dark:text-gray-500">{item.part_code}</div>
        )}
        {item.supplier_name && (
          <div className="text-gray-400 dark:text-gray-500 truncate max-w-[200px]">
            via {item.supplier_name}
          </div>
        )}
      </td>
      <td className={`text-right px-4 py-2 font-mono ${
        canFulfill
          ? 'text-green-600 dark:text-green-400'
          : 'text-red-500 dark:text-red-400'
      }`}>
        {item.warehouse_qty}
      </td>
      <td className="text-right px-4 py-2 font-mono text-gray-600 dark:text-gray-400">
        {item.qty_received}
      </td>
      <td className="text-right px-4 py-2 font-mono text-gray-600 dark:text-gray-400">
        {item.qty_already_pulled}
      </td>
      <td className="text-right px-4 py-2 font-mono font-semibold text-amber-600 dark:text-amber-400">
        {item.qty_pending}
      </td>
      <td className="px-4 py-2">{priorityBadge}</td>
    </tr>
  );
}
