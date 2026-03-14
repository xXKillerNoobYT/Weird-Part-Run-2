/**
 * ConflictLogCard — shows recent sync conflicts and their resolutions.
 */

import { useQuery } from '@tanstack/react-query';
import { AlertCircle, CheckCircle } from 'lucide-react';
import { Badge } from '../../../../components/ui/Badge';
import { PageSpinner } from '../../../../components/ui/Spinner';
import { EmptyState } from '../../../../components/ui/EmptyState';
import { getSyncConflicts } from '../../../../api/sync';
import { formatDate } from './helpers';

export function ConflictLogCard() {
  const { data: conflicts, isLoading, error } = useQuery({
    queryKey: ['sync-conflicts'],
    queryFn: () => getSyncConflicts(20),
    retry: 1,
    staleTime: 30000,
  });

  return (
    <div className="bg-surface border border-border rounded-lg p-4 space-y-3">
      <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
        <AlertCircle className="h-4 w-4" />
        Conflict Log
      </h3>

      {isLoading ? (
        <PageSpinner label="Loading conflicts..." />
      ) : error || !conflicts?.length ? (
        <EmptyState
          icon={CheckCircle}
          title="No Conflicts"
          description="No sync conflicts have been recorded."
        />
      ) : (
        <div className="space-y-2">
          {conflicts.map((c) => (
            <div key={c.id} className="p-2 bg-amber-50 dark:bg-amber-900/10 border border-amber-200 dark:border-amber-800/30 rounded-md">
              <div className="flex flex-wrap items-center gap-2 text-sm">
                <Badge variant={c.resolution === 'device_wins' ? 'info' : 'warning'}>
                  {c.resolution}
                </Badge>
                <span className="text-gray-700 dark:text-gray-300">
                  {c.table_name}.{c.record_id}
                </span>
                <span className="text-xs text-gray-500 dark:text-gray-400 ml-auto">
                  {formatDate(c.resolved_at)}
                </span>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
