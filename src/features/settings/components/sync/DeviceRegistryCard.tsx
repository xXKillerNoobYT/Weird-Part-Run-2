/**
 * DeviceRegistryCard — shows all registered sync devices.
 */

import { useQuery } from '@tanstack/react-query';
import { Smartphone, Monitor } from 'lucide-react';
import { Badge } from '../../../../components/ui/Badge';
import { PageSpinner } from '../../../../components/ui/Spinner';
import { listSyncDevices } from '../../../../api/sync';
import { formatDate } from './helpers';

export function DeviceRegistryCard() {
  const { data: devices, isLoading, error } = useQuery({
    queryKey: ['sync-devices'],
    queryFn: listSyncDevices,
    retry: 1,
    staleTime: 30000,
  });

  return (
    <div className="bg-surface border border-border rounded-lg p-4 space-y-3">
      <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
        <Smartphone className="h-4 w-4" />
        Registered Devices
      </h3>

      {isLoading ? (
        <PageSpinner label="Loading devices..." />
      ) : error || !devices?.length ? (
        <p className="text-sm text-gray-500 dark:text-gray-400">
          No devices registered for sync yet.
        </p>
      ) : (
        <div className="space-y-2">
          {devices.map((d) => (
            <div key={d.device_id} className="flex items-center gap-3 p-2 bg-gray-50 dark:bg-gray-800/50 rounded-md">
              {d.platform === 'ios' || d.platform === 'android' ? (
                <Smartphone className="h-4 w-4 text-gray-400 shrink-0" />
              ) : (
                <Monitor className="h-4 w-4 text-gray-400 shrink-0" />
              )}
              <div className="flex-1 min-w-0">
                <div className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                  {d.device_name || 'Unknown'}
                </div>
                <div className="text-xs text-gray-500 dark:text-gray-400">
                  {d.platform} &middot; Last sync: {d.last_sync_at ? formatDate(d.last_sync_at) : 'Never'}
                </div>
              </div>
              <Badge variant={d.last_sync_at ? 'success' : 'neutral'}>
                {d.last_sync_at ? 'Active' : 'Pending'}
              </Badge>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
