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

import { useQuery } from '@tanstack/react-query';
import { PackageCheck, Plus } from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { getStagingGroups } from '../../../api/warehouse';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import { useMovementWizardStore } from '../stores/movement-wizard-store';
import { MovementWizard } from '../components/wizard/MovementWizard';
import { StagingCard } from '../components/staging/StagingCard';

export function StagingPage() {
  const { hasPermission } = useAuthStore();
  const canMove = hasPermission(PERMISSIONS.MOVE_STOCK_WAREHOUSE);
  const { open: openWizard } = useMovementWizardStore();

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

  return (
    <>
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
        {groups.map((group, i) => (
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
