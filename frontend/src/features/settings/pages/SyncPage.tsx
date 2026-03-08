/**
 * SyncPage — data synchronization settings and status.
 *
 * Shows sync status, device registry, recent sync history,
 * and conflict log for admin users. Also provides shop URL
 * configuration for Capacitor devices.
 */

import { useState, useEffect } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  CloudOff, RefreshCw, CheckCircle, AlertCircle,
  Smartphone, Monitor, Settings2, History, ShieldAlert,
} from 'lucide-react';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import {
  getHardSyncHistory,
  getSyncConflicts,
  getSyncHistory,
  listSyncDevices,
  requestHardSync,
} from '../../../api/sync';
import { isCapacitor } from '../../../lib/environment';

export function SyncPage() {
  return (
    <div className="space-y-6">
      <h2 className="text-xl font-bold text-gray-900 dark:text-gray-100">
        Sync & Devices
      </h2>

      {/* Shop Connection (Capacitor only) */}
      {isCapacitor() && <ShopConnectionCard />}

      {/* Registered Devices */}
      <DeviceRegistryCard />

      {/* Hard Sync Recovery */}
      <HardSyncRecoveryCard />

      {/* Sync History */}
      <SyncHistoryCard />

      {/* Hard Sync History */}
      <HardSyncHistoryCard />

      {/* Conflict Log */}
      <ConflictLogCard />
    </div>
  );
}

// ── Shop Connection Card (Capacitor) ─────────────────────────────

function ShopConnectionCard() {
  const [url, setUrl] = useState('');
  const [_savedUrl, setSavedUrl] = useState<string | null>(null);
  const [reachable, setReachable] = useState<boolean | null>(null);
  const [shopInfo, setShopInfo] = useState<any>(null);
  const [checking, setChecking] = useState(false);

  useEffect(() => {
    import('../../../lib/shop-config').then(async (mod) => {
      const u = await mod.getShopUrl();
      setSavedUrl(u);
      if (u) setUrl(u);
    });
  }, []);

  async function handleSave() {
    const mod = await import('../../../lib/shop-config');
    await mod.setShopUrl(url);
    setSavedUrl(url);
    handleCheck();
  }

  async function handleCheck() {
    setChecking(true);
    const mod = await import('../../../lib/shop-config');
    const ok = await mod.isShopReachable();
    setReachable(ok);
    if (ok) {
      const info = await mod.getShopInfo();
      setShopInfo(info);
    }
    setChecking(false);
  }

  return (
    <div className="bg-surface border border-border rounded-lg p-4 space-y-3">
      <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
        <Settings2 className="h-4 w-4" />
        Shop Server Connection
      </h3>

      <div className="flex flex-wrap gap-2">
        <input
          type="url"
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          placeholder="http://192.168.1.100:8000"
          className="flex-1 min-w-[200px] px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
        />
        <Button size="sm" onClick={handleSave}>Save</Button>
        <Button size="sm" variant="secondary" onClick={handleCheck} disabled={checking}>
          {checking ? <RefreshCw className="h-4 w-4 animate-spin" /> : 'Test'}
        </Button>
      </div>

      {reachable !== null && (
        <div className={`flex items-center gap-2 text-sm ${reachable ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'}`}>
          {reachable ? <CheckCircle className="h-4 w-4" /> : <CloudOff className="h-4 w-4" />}
          {reachable ? 'Connected to shop server' : 'Cannot reach shop server'}
        </div>
      )}

      {shopInfo && (
        <div className="text-xs text-gray-500 dark:text-gray-400 space-y-0.5">
          <div>Host: {shopInfo.hostname}</div>
          <div>IP: {shopInfo.local_ip}:{shopInfo.port}</div>
        </div>
      )}
    </div>
  );
}

// ── Device Registry Card ─────────────────────────────────────────

function DeviceRegistryCard() {
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

// ── Hard Sync Recovery Card ─────────────────────────────────────

function HardSyncRecoveryCard() {
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

// ── Sync History Card ────────────────────────────────────────────

function SyncHistoryCard() {
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

// ── Hard Sync History Card ──────────────────────────────────────

function HardSyncHistoryCard() {
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

// ── Conflict Log Card ────────────────────────────────────────────

function ConflictLogCard() {
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

function hardSyncStatusVariant(status: string): 'default' | 'success' | 'warning' | 'danger' | 'info' {
  if (status === 'completed') return 'success';
  if (status === 'failed') return 'danger';
  if (status === 'requested' || status === 'package_ready' || status === 'in_progress') return 'warning';
  return 'default';
}

// ── Helpers ──────────────────────────────────────────────────────

function formatDate(iso: string): string {
  try {
    const d = new Date(iso);
    return d.toLocaleString(undefined, {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch {
    return iso;
  }
}
