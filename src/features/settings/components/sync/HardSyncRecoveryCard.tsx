/**
 * HardSyncRecoveryCard — "break glass" hard sync recovery for stale/corrupt devices.
 */

import { useState, useEffect } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { ShieldAlert } from 'lucide-react';
import { Button } from '../../../../components/ui/Button';
import { PageSpinner } from '../../../../components/ui/Spinner';
import { listSyncDevices, requestHardSync } from '../../../../api/sync';

export function HardSyncRecoveryCard() {
  const queryClient = useQueryClient();
  const [deviceId, setDeviceId] = useState('');
  const [reasonCode, setReasonCode] = useState('state_mismatch');
  const [notes, setNotes] = useState('');
  const [preservePendingData, setPreservePendingData] = useState(true);
  const [confirming, setConfirming] = useState(false);
  const [resultSummary, setResultSummary] = useState<string | null>(null);

  const { data: devices = [], isLoading } = useQuery({
    queryKey: ['sync-devices'],
    queryFn: listSyncDevices,
  });

  useEffect(() => {
    if (!deviceId && devices.length > 0) {
      setDeviceId(devices[0].device_id);
    }
  }, [devices, deviceId]);

  const requestMutation = useMutation({
    mutationFn: requestHardSync,
    onSuccess: (pkg) => {
      setResultSummary(
        `Package ready: ${pkg.total_rows} rows across ${pkg.table_count} tables (Hard Sync #${pkg.hard_sync_id})`,
      );
      setConfirming(false);
      queryClient.invalidateQueries({ queryKey: ['hard-sync-history'] });
      queryClient.invalidateQueries({ queryKey: ['sync-history'] });
    },
  });

  function submitHardSync() {
    if (!deviceId) return;
    requestMutation.mutate({
      device_id: deviceId,
      reason_code: reasonCode,
      preserve_pending_data: preservePendingData,
      notes: notes.trim() || undefined,
    });
  }

  return (
    <div className="bg-surface border border-amber-200 dark:border-amber-800 rounded-lg p-4 space-y-4">
      <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
        <ShieldAlert className="h-4 w-4 text-amber-500" />
        Hard Sync Recovery (Break Glass)
      </h3>

      <p className="text-sm text-gray-600 dark:text-gray-400">
        Use this only when a device is stale/corrupt/partial. It generates a fresh
        authoritative snapshot package for the selected device.
      </p>

      {isLoading ? (
        <PageSpinner label="Loading devices..." />
      ) : devices.length === 0 ? (
        <p className="text-sm text-gray-500 dark:text-gray-400">
          No registered devices available for hard sync.
        </p>
      ) : (
        <>
          <div className="flex flex-wrap gap-2">
            <select
              value={deviceId}
              onChange={(e) => setDeviceId(e.target.value)}
              className="min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100 min-w-[220px]"
            >
              {devices.map((d) => (
                <option key={d.device_id} value={d.device_id}>
                  {(d.device_name || d.device_id)} · {d.platform || 'unknown'}
                </option>
              ))}
            </select>

            <select
              value={reasonCode}
              onChange={(e) => setReasonCode(e.target.value)}
              className="min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100 min-w-[220px]"
            >
              <option value="state_mismatch">State mismatch</option>
              <option value="stale_cache">Stale cache</option>
              <option value="corrupt_db">Corrupt local DB</option>
              <option value="offline_gap">Long offline gap</option>
              <option value="manual_admin">Manual admin recovery</option>
            </select>
          </div>

          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={2}
            placeholder="Optional recovery note..."
            className="w-full px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
          />

          <label className="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
            <input
              type="checkbox"
              checked={preservePendingData}
              onChange={(e) => setPreservePendingData(e.target.checked)}
              className="h-4 w-4"
            />
            Preserve pending outbound data for replay after restore
          </label>

          {!confirming ? (
            <Button
              size="sm"
              variant="danger"
              onClick={() => setConfirming(true)}
              disabled={requestMutation.isPending || !deviceId}
            >
              Request Hard Sync
            </Button>
          ) : (
            <div className="flex flex-wrap items-center gap-2 p-3 rounded-md bg-amber-50 dark:bg-amber-900/10 border border-amber-200 dark:border-amber-800/40">
              <span className="text-sm text-amber-800 dark:text-amber-300">
                Confirm hard sync for this device?
              </span>
              <Button
                size="sm"
                variant="danger"
                isLoading={requestMutation.isPending}
                onClick={submitHardSync}
              >
                Confirm
              </Button>
              <Button size="sm" variant="secondary" onClick={() => setConfirming(false)}>
                Cancel
              </Button>
            </div>
          )}
        </>
      )}

      {resultSummary && (
        <div className="text-sm text-green-700 dark:text-green-300 bg-green-50 dark:bg-green-900/10 border border-green-200 dark:border-green-800/40 rounded-md p-2">
          {resultSummary}
        </div>
      )}

      {requestMutation.isError && (
        <div className="text-sm text-red-700 dark:text-red-300 bg-red-50 dark:bg-red-900/10 border border-red-200 dark:border-red-800/40 rounded-md p-2">
          Failed to request hard sync. Please try again.
        </div>
      )}
    </div>
  );
}
