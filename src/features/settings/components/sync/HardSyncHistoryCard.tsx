/**
 * HardSyncHistoryCard — table of past hard sync recovery events.
 */

import { useQuery } from '@tanstack/react-query';
import { ShieldAlert } from 'lucide-react';
import { Badge } from '../../../../components/ui/Badge';
import { PageSpinner } from '../../../../components/ui/Spinner';
import { getHardSyncHistory } from '../../../../api/sync';
import { formatDate, hardSyncStatusVariant } from './helpers';

export function HardSyncHistoryCard() {
  const { data: events, isLoading, error } = useQuery({
    queryKey: ['hard-sync-history'],
    queryFn: () => getHardSyncHistory(undefined, 20),
    retry: 1,
    staleTime: 30000,
  });

  return (
    <div className="bg-surface border border-border rounded-lg p-4 space-y-3">
      <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
        <ShieldAlert className="h-4 w-4" />
        Hard Sync History
      </h3>

      {isLoading ? (
        <PageSpinner label="Loading hard sync history..." />
      ) : error || !events?.length ? (
        <p className="text-sm text-gray-500 dark:text-gray-400">
          No hard sync events yet.
        </p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-xs text-gray-500 dark:text-gray-400 border-b border-border">
                <th className="pb-2 pr-4">Requested</th>
                <th className="pb-2 pr-4">Device</th>
                <th className="pb-2 pr-4">Reason</th>
                <th className="pb-2 pr-4">Status</th>
                <th className="pb-2">Completed</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {events.map((e) => (
                <tr key={e.id}>
                  <td className="py-1.5 pr-4 text-gray-700 dark:text-gray-300 whitespace-nowrap">
                    {formatDate(e.requested_at)}
                  </td>
                  <td className="py-1.5 pr-4 text-gray-700 dark:text-gray-300 font-mono">
                    {e.device_id}
                  </td>
                  <td className="py-1.5 pr-4 text-gray-700 dark:text-gray-300">
                    {e.reason_code || '—'}
                  </td>
                  <td className="py-1.5 pr-4">
                    <Badge variant={hardSyncStatusVariant(e.status)}>{e.status}</Badge>
                  </td>
                  <td className="py-1.5 text-gray-700 dark:text-gray-300 whitespace-nowrap">
                    {e.completed_at ? formatDate(e.completed_at) : '—'}
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
