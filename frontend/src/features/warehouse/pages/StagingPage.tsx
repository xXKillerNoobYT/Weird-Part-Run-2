/**
 * StagingPage — pulled items grouped by destination with aging colors.
 *
 * Shows items that have been pulled from warehouse shelves and are
 * waiting to be loaded onto trucks or dispatched to jobs.
 * Color coding: normal (< 24h), yellow (24-48h), red (> 48h).
 *
 * The FAB (floating action button) opens the movement wizard pre-filled
 * for "warehouse → pulled" so users can quickly stage more items.
 */

import { useState, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { PackageCheck, Plus, AlertTriangle, Package, ArrowUpDown } from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Badge } from '../../../components/ui/Badge';
import { getStagingGroups } from '../../../api/warehouse';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import { useMovementWizardStore } from '../stores/movement-wizard-store';
import { MovementWizard } from '../components/wizard/MovementWizard';
import { StagingCard } from '../components/staging/StagingCard';
import type { StagingGroup } from '../../../lib/types';

type SortOption = 'oldest' | 'newest' | 'most_items';

export function StagingPage() {
  const { hasPermission } = useAuthStore();
  const canMove = hasPermission(PERMISSIONS.MOVE_STOCK_WAREHOUSE);
  const { open: openWizard } = useMovementWizardStore();
  const [sort, setSort] = useState<SortOption>('oldest');

  const { data: groups, isLoading } = useQuery({
    queryKey: ['warehouse-staging'],
    queryFn: getStagingGroups,
    staleTime: 15_000,
    refetchOnWindowFocus: true,
  });

  /** Open wizard pre-filled for warehouse → pulled (staging). */
  const handlePullStock = () => {
    openWizard({
      fromLocationType: 'warehouse',
      toLocationType: 'pulled',
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

  if (isLoading) {
    return <PageSpinner label="Loading staging area..." />;
  }

  if (!groups || groups.length === 0) {
    return (
      <>
        <EmptyState
          icon={<PackageCheck className="h-12 w-12" />}
          title="No Staged Items"
          description="Nothing has been pulled from the shelves yet. Use the + button to pull items from the warehouse to the staging area."
        />
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

  // Summary stats
  const totalUnits = groups.reduce((s, g) => s + g.total_qty, 0);
  const totalParts = groups.reduce((s, g) => s + g.items.length, 0);
  const overdueGroups = groups.filter(g => g.aging_status === 'critical').length;
  const warningGroups = groups.filter(g => g.aging_status === 'warning').length;

  return (
    <>
      {/* Summary bar */}
      <div className="mb-4 flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-4 flex-wrap">
          <div className="flex items-center gap-1.5 text-sm text-gray-700 dark:text-gray-300">
            <Package size={16} className="text-gray-400 dark:text-gray-500 flex-shrink-0" />
            <span className="font-semibold">{groups.length}</span>
            <span className="text-gray-500 dark:text-gray-400">
              destination{groups.length !== 1 ? 's' : ''}
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
