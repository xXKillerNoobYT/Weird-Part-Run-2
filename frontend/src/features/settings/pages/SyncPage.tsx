/**
 * SyncPage — data synchronization settings and status.
 *
 * Shows sync status, device registry, recent sync history,
 * and conflict log for admin users. Also provides shop URL
 * configuration for Capacitor devices.
 */

import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  Cloud, CloudOff, RefreshCw, CheckCircle, AlertCircle,
  Smartphone, Monitor, Settings2, History,
} from 'lucide-react';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import apiClient from '../../../api/client';
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

      {/* Sync History */}
      <SyncHistoryCard />

      {/* Conflict Log */}
      <ConflictLogCard />
    </div>
  );
}

// ── Shop Connection Card (Capacitor) ─────────────────────────────

function ShopConnectionCard() {
  const [url, setUrl] = useState('');
  const [savedUrl, setSavedUrl] = useState<string | null>(null);
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
    queryFn: async () => {
      const resp = await apiClient.get('/sync/devices');
      return resp.data.data as any[];
    },
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
          {devices.map((d: any) => (
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
              <Badge color={d.last_sync_at ? 'green' : 'gray'} size="sm">
                {d.last_sync_at ? 'Active' : 'Pending'}
              </Badge>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ── Sync History Card ────────────────────────────────────────────

function SyncHistoryCard() {
  const { data: history, isLoading, error } = useQuery({
    queryKey: ['sync-history'],
    queryFn: async () => {
      const resp = await apiClient.get('/sync/history?limit=20');
      return resp.data.data as any[];
    },
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
              {history.map((h: any) => (
                <tr key={h.id}>
                  <td className="py-1.5 pr-4 text-gray-700 dark:text-gray-300 whitespace-nowrap">
                    {formatDate(h.started_at)}
                  </td>
                  <td className="py-1.5 pr-4">
                    <Badge color={h.direction === 'push' ? 'blue' : 'purple'} size="sm">
                      {h.direction}
                    </Badge>
                  </td>
                  <td className="py-1.5 pr-4 text-gray-700 dark:text-gray-300">{h.changes_sent}</td>
                  <td className="py-1.5 pr-4 text-gray-700 dark:text-gray-300">{h.changes_received}</td>
                  <td className="py-1.5">
                    {h.conflicts_resolved > 0 ? (
                      <Badge color="amber" size="sm">{h.conflicts_resolved}</Badge>
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

// ── Conflict Log Card ────────────────────────────────────────────

function ConflictLogCard() {
  const { data: conflicts, isLoading, error } = useQuery({
    queryKey: ['sync-conflicts'],
    queryFn: async () => {
      const resp = await apiClient.get('/sync/conflicts?limit=20');
      return resp.data.data as any[];
    },
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
          icon={<CheckCircle className="h-8 w-8" />}
          title="No Conflicts"
          description="No sync conflicts have been recorded."
        />
      ) : (
        <div className="space-y-2">
          {conflicts.map((c: any) => (
            <div key={c.id} className="p-2 bg-amber-50 dark:bg-amber-900/10 border border-amber-200 dark:border-amber-800/30 rounded-md">
              <div className="flex flex-wrap items-center gap-2 text-sm">
                <Badge color={c.resolution === 'device_wins' ? 'blue' : 'amber'} size="sm">
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
