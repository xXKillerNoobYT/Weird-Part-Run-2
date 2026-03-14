/**
 * SyncHistoryCard — recent sync history table.
 */

import { useQuery } from '@tanstack/react-query';
import { History } from 'lucide-react';
import { Badge } from '../../../../components/ui/Badge';
import { PageSpinner } from '../../../../components/ui/Spinner';
import { getSyncHistory } from '../../../../api/sync';
import { formatDate } from './helpers';

export function SyncHistoryCard() {
  const { data: history, isLoading, error } = useQuery({
    queryKey: ['sync-history'],
    queryFn: () => getSyncHistory(undefined, 20),
    retry: 1,
    staleTime: 30000,
  });

  return (
    <div className="bg-surface border border-border rounded-lg p-4 space-y-3">
      <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
        <History className="h-4 w-4" />
        Recent Sync History
      </h3>

      {isLoading ? (
        <PageSpinner label="Loading history..." />
      ) : error || !history?.length ? (
        <p className="text-sm text-gray-500 dark:text-gray-400">
          No sync activity yet.
        </p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-xs text-gray-500 dark:text-gray-400 border-b border-border">
                <th className="pb-2 pr-4">Time</th>
                <th className="pb-2 pr-4">Direction</th>
                <th className="pb-2 pr-4">Sent</th>
                <th className="pb-2 pr-4">Received</th>
                <th className="pb-2">Conflicts</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {history.map((h) => (
                <tr key={h.id}>
                  <td className="py-1.5 pr-4 text-gray-700 dark:text-gray-300 whitespace-nowrap">
                    {formatDate(h.started_at)}
                  </td>
                  <td className="py-1.5 pr-4">
                    <Badge variant={h.direction === 'push' ? 'info' : 'neutral'}>
                      {h.direction}
                    </Badge>
                  </td>
                  <td className="py-1.5 pr-4 text-gray-700 dark:text-gray-300">{h.changes_sent}</td>
                  <td className="py-1.5 pr-4 text-gray-700 dark:text-gray-300">{h.changes_received}</td>
                  <td className="py-1.5">
                    {h.conflicts_resolved > 0 ? (
                      <Badge variant="warning">{h.conflicts_resolved}</Badge>
                    ) : (
                      <span className="text-gray-400">0</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
