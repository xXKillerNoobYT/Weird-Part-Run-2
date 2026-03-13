/**
 * DeviceManagementPage — Enhanced v2 with health telemetry, overrides,
 * primary user reassignment, error logs, BT encounters, and cluster management.
 *
 * Six tabs:
 *   Devices       — full device registry with health, overrides, and primary user
 *   Health & Errors — error log + health timeline
 *   BT Encounters — Bluetooth sync encounter history
 *   Sync History  — recent sync batches
 *   Cluster       — shop PC cluster nodes
 *   Setup Helper  — iOS/iPad/Android install guides
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Monitor, Smartphone, Tablet, Globe, RefreshCw, ArrowLeftRight,
  AlertTriangle, CheckCircle, XCircle, Clock, Wifi, WifiOff,
  ArrowUpDown, ChevronDown, ChevronUp,
  Download, Cable, Wrench, Info, Battery, HardDrive, AlertOctagon,
  UserCheck, LogOut, Trash2, Zap, Server, Bluetooth,
  BatteryCharging, Lock, Unlock, Send,
} from 'lucide-react';
import { Card } from '../../../components/ui/Card';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { Spinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import {
  listDevices, setPrimaryUser, setDeviceOverride,
  clearDeviceOverride, disableDevice, enableDevice,
  forceSyncDevice, pushDeviceConfig,
  listAllErrors, resolveError,
  listBtEncounters, listClusterNodes, setClusterPrimary,
} from '../../../api/devices';
import type { DeviceSummary, DeviceErrorLog, BtEncounter, ClusterNode } from '../../../api/devices';
import { getSyncHistory } from '../../../api/sync';
import type { SyncBatch } from '../../../api/sync';
import { getUsers } from '../../../api/auth';

// ── Helpers ──────────────────────────────────────────────────────

function relativeTime(isoStr: string | null): string {
  if (!isoStr) return 'Never';
  try {
    const ms = Date.now() - new Date(isoStr + (isoStr.endsWith('Z') ? '' : 'Z')).getTime();
    const secs = Math.floor(ms / 1000);
    if (secs < 60) return 'Just now';
    const mins = Math.floor(secs / 60);
    if (mins < 60) return `${mins}m ago`;
    const hrs = Math.floor(mins / 60);
    if (hrs < 24) return `${hrs}h ago`;
    const days = Math.floor(hrs / 24);
    return `${days}d ago`;
  } catch {
    return isoStr;
  }
}

function formatDateTime(isoStr: string | null): string {
  if (!isoStr) return '—';
  try {
    return new Date(isoStr + (isoStr.endsWith('Z') ? '' : 'Z')).toLocaleString([], {
      month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
    });
  } catch {
    return isoStr;
  }
}

function isRecentlyActive(lastSync: string | null): boolean {
  if (!lastSync) return false;
  try {
    const ms = Date.now() - new Date(lastSync + (lastSync.endsWith('Z') ? '' : 'Z')).getTime();
    return ms < 60 * 60 * 1000;
  } catch {
    return false;
  }
}

function PlatformIcon({ platform }: { platform: string | null }) {
  const p = (platform ?? '').toLowerCase();
  if (p === 'ios' || p === 'android')
    return <Smartphone className="h-5 w-5 text-gray-400 dark:text-gray-500 flex-shrink-0" />;
  if (p === 'web')
    return <Globe className="h-5 w-5 text-gray-400 dark:text-gray-500 flex-shrink-0" />;
  return <Monitor className="h-5 w-5 text-gray-400 dark:text-gray-500 flex-shrink-0" />;
}

function platformLabel(platform: string | null): string {
  const p = (platform ?? '').toLowerCase();
  if (p === 'ios') return 'iPhone / iPad';
  if (p === 'android') return 'Android';
  if (p === 'web') return 'Web Browser';
  return 'Unknown';
}

function BatteryIndicator({ level, charging }: { level: number | null; charging: number | null }) {
  if (level == null) return null;
  const color = level > 50 ? 'text-green-500' : level > 20 ? 'text-amber-500' : 'text-red-500';
  const Icon = charging ? BatteryCharging : Battery;
  return (
    <span className={`inline-flex items-center gap-1 text-xs ${color}`}>
      <Icon className="h-3.5 w-3.5" />
      {level}%
    </span>
  );
}

function StorageBar({ used, total }: { used: number | null; total: number | null }) {
  if (used == null || total == null || total === 0) return null;
  const pct = Math.round((used / total) * 100);
  const color = pct > 90 ? 'bg-red-500' : pct > 70 ? 'bg-amber-500' : 'bg-green-500';
  return (
    <div className="flex items-center gap-2 text-xs">
      <HardDrive className="h-3.5 w-3.5 text-gray-400" />
      <div className="flex-1 h-1.5 rounded-full bg-gray-200 dark:bg-gray-700 max-w-20">
        <div className={`h-full rounded-full ${color}`} style={{ width: `${Math.min(pct, 100)}%` }} />
      </div>
      <span className="text-gray-500 dark:text-gray-400">
        {(used / 1024).toFixed(1)}/{(total / 1024).toFixed(1)} GB
      </span>
    </div>
  );
}


// ── Tab: Devices (Enhanced v2) ──────────────────────────────────

function DevicesTab() {
  const queryClient = useQueryClient();
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [confirmAction, setConfirmAction] = useState<{ deviceId: string; action: string } | null>(null);

  const { data: devices, isLoading, refetch, isFetching } = useQuery({
    queryKey: ['admin-devices'],
    queryFn: () => listDevices(true),
    staleTime: 15_000,
  });

  const { data: users } = useQuery({
    queryKey: ['users'],
    queryFn: getUsers,
    staleTime: 60_000,
  });

  const overrideMutation = useMutation({
    mutationFn: ({ deviceId, action }: { deviceId: string; action: 'force_logout' | 'force_wipe' | 'force_sync' }) =>
      setDeviceOverride(deviceId, action),
    onSuccess: () => { setConfirmAction(null); queryClient.invalidateQueries({ queryKey: ['admin-devices'] }); },
  });

  const clearOverrideMutation = useMutation({
    mutationFn: clearDeviceOverride,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['admin-devices'] }),
  });

  const disableMutation = useMutation({
    mutationFn: ({ deviceId, reason }: { deviceId: string; reason: string }) => disableDevice(deviceId, reason),
    onSuccess: () => { setConfirmAction(null); queryClient.invalidateQueries({ queryKey: ['admin-devices'] }); },
  });

  const enableMutation = useMutation({
    mutationFn: enableDevice,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['admin-devices'] }),
  });

  const primaryUserMutation = useMutation({
    mutationFn: ({ deviceId, userId }: { deviceId: string; userId: number }) => setPrimaryUser(deviceId, userId),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['admin-devices'] }),
  });

  const forceSyncMutation = useMutation({
    mutationFn: forceSyncDevice,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['admin-devices'] }),
  });

  const pushConfigMutation = useMutation({
    mutationFn: pushDeviceConfig,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['admin-devices'] }),
  });

  if (isLoading) return <div className="flex items-center justify-center py-16"><Spinner size="lg" /></div>;

  if (!devices || devices.length === 0) {
    return (
      <EmptyState icon={<Smartphone className="h-12 w-12" />} title="No Devices Registered"
        description="Devices appear here after their first sync with the shop." />
    );
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <p className="text-sm text-gray-500 dark:text-gray-400">
          {devices.length} device{devices.length !== 1 ? 's' : ''} registered
        </p>
        <Button size="sm" variant="secondary"
          icon={<RefreshCw className={`h-3.5 w-3.5 ${isFetching ? 'animate-spin' : ''}`} />}
          onClick={() => refetch()}>
          <span className="hidden sm:inline">Refresh</span>
        </Button>
      </div>

      {devices.map((device: DeviceSummary) => {
        const active = isRecentlyActive(device.last_sync_at);
        const isExpanded = expandedId === device.device_id;
        const isDisabled = !!device.is_disabled;
        const hasOverride = !!device.override_action;

        return (
          <div key={device.device_id}
            className={`border rounded-xl overflow-hidden transition-colors ${isDisabled ? 'border-red-300 dark:border-red-800 bg-red-50/50 dark:bg-red-900/10' :
                hasOverride ? 'border-amber-300 dark:border-amber-800 bg-amber-50/50 dark:bg-amber-900/10' :
                  'border-border bg-surface'
              }`}>
            <div className="p-4 space-y-3">
              {/* Top row */}
              <div className="flex items-start gap-3">
                <div className="mt-0.5"><PlatformIcon platform={device.platform} /></div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-medium text-sm text-gray-900 dark:text-gray-100 truncate">
                      {device.device_name || 'Unnamed Device'}
                    </span>
                    <Badge variant={isDisabled ? 'danger' : active ? 'success' : 'default'}>
                      {isDisabled ? (<span className="flex items-center gap-1"><Lock className="h-3 w-3" /> Disabled</span>)
                        : active ? (<span className="flex items-center gap-1"><Wifi className="h-3 w-3" /> Active</span>)
                          : (<span className="flex items-center gap-1"><WifiOff className="h-3 w-3" /> Idle</span>)}
                    </Badge>
                    {hasOverride && <Badge variant="warning">⚡ {device.override_action?.replace('_', ' ')}</Badge>}
                    {(device.unresolved_errors ?? 0) > 0 && (
                      <Badge variant="danger">{device.unresolved_errors} error{device.unresolved_errors !== 1 ? 's' : ''}</Badge>
                    )}
                  </div>
                  <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                    {platformLabel(device.platform)} · <span className="font-mono">{device.device_id.slice(0, 8)}…</span>
                    {device.primary_user_name && (<> · <UserCheck className="inline h-3 w-3 -mt-0.5" /> {device.primary_user_name}</>)}
                  </p>
                </div>
                <button onClick={() => setExpandedId(isExpanded ? null : device.device_id)}
                  className="ml-auto text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 p-1">
                  {isExpanded ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                </button>
              </div>

              {/* Stats row */}
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs">
                <div className="space-y-0.5">
                  <p className="text-gray-400 dark:text-gray-500 uppercase tracking-wide text-[10px]">Last Sync</p>
                  <p className="text-gray-900 dark:text-gray-100 font-medium">{relativeTime(device.last_sync_at)}</p>
                </div>
                <div className="space-y-0.5">
                  <p className="text-gray-400 dark:text-gray-500 uppercase tracking-wide text-[10px]">Pending</p>
                  <p className={`font-medium ${(device.pending_changes ?? 0) > 0 ? 'text-amber-600 dark:text-amber-400' : 'text-gray-900 dark:text-gray-100'}`}>
                    {device.pending_changes ?? 0} changes
                  </p>
                </div>
                <div className="space-y-0.5">
                  <p className="text-gray-400 dark:text-gray-500 uppercase tracking-wide text-[10px]">Battery</p>
                  <BatteryIndicator level={device.battery_level} charging={device.battery_charging} />
                  {device.battery_level == null && <p className="text-gray-400">—</p>}
                </div>
                <div className="space-y-0.5">
                  <p className="text-gray-400 dark:text-gray-500 uppercase tracking-wide text-[10px]">Storage</p>
                  <StorageBar used={device.storage_used_mb} total={device.storage_total_mb} />
                  {device.storage_used_mb == null && <p className="text-gray-400">—</p>}
                </div>
              </div>

              {(device.app_version || device.os_version) && (
                <div className="flex gap-4 text-[11px] text-gray-400 dark:text-gray-500">
                  {device.app_version && <span>App: v{device.app_version}</span>}
                  {device.os_version && <span>OS: {device.os_version}</span>}
                </div>
              )}
            </div>

            {/* Expanded actions panel */}
            {isExpanded && (
              <div className="border-t border-border bg-surface-secondary p-4 space-y-4">
                {/* Primary user */}
                <div className="space-y-2">
                  <h4 className="text-xs font-semibold text-gray-600 dark:text-gray-400 uppercase tracking-wide">Primary User</h4>
                  <div className="flex items-center gap-2 flex-wrap">
                    <select
                      className="text-sm px-3 py-1.5 rounded-lg border border-border bg-surface text-gray-900 dark:text-gray-100 min-w-[180px]"
                      value={device.primary_user_id || ''}
                      onChange={(e) => {
                        const userId = parseInt(e.target.value, 10);
                        if (userId) primaryUserMutation.mutate({ deviceId: device.device_id, userId });
                      }}>
                      <option value="">Unassigned</option>
                      {users?.map((u) => <option key={u.id} value={u.id}>{u.display_name}</option>)}
                    </select>
                    {primaryUserMutation.isPending && <Spinner size="sm" />}
                  </div>
                </div>

                {/* Override actions */}
                <div className="space-y-2">
                  <h4 className="text-xs font-semibold text-gray-600 dark:text-gray-400 uppercase tracking-wide">Remote Actions</h4>
                  <div className="flex flex-wrap gap-2">
                    {!isDisabled ? (
                      <>
                        <Button size="sm" variant="secondary" icon={<Zap className="h-3.5 w-3.5" />}
                          onClick={() => forceSyncMutation.mutate(device.device_id)} isLoading={forceSyncMutation.isPending}>
                          Force Sync
                        </Button>
                        <Button size="sm" variant="secondary" icon={<Send className="h-3.5 w-3.5" />}
                          onClick={() => pushConfigMutation.mutate(device.device_id)} isLoading={pushConfigMutation.isPending}>
                          Push Config
                        </Button>
                        <Button size="sm" variant="warning" icon={<LogOut className="h-3.5 w-3.5" />}
                          onClick={() => setConfirmAction({ deviceId: device.device_id, action: 'force_logout' })}>
                          Force Logout
                        </Button>
                        <Button size="sm" variant="warning" icon={<Lock className="h-3.5 w-3.5" />}
                          onClick={() => setConfirmAction({ deviceId: device.device_id, action: 'disable' })}>
                          Disable
                        </Button>
                        <Button size="sm" variant="danger" icon={<Trash2 className="h-3.5 w-3.5" />}
                          onClick={() => setConfirmAction({ deviceId: device.device_id, action: 'force_wipe' })}>
                          Force Wipe
                        </Button>
                      </>
                    ) : (
                      <Button size="sm" variant="success" icon={<Unlock className="h-3.5 w-3.5" />}
                        onClick={() => enableMutation.mutate(device.device_id)} isLoading={enableMutation.isPending}>
                        Re-enable Device
                      </Button>
                    )}
                    {hasOverride && !isDisabled && (
                      <Button size="sm" variant="secondary" icon={<XCircle className="h-3.5 w-3.5" />}
                        onClick={() => clearOverrideMutation.mutate(device.device_id)} isLoading={clearOverrideMutation.isPending}>
                        Clear Override
                      </Button>
                    )}
                  </div>
                  {isDisabled && device.disabled_reason && (
                    <p className="text-xs text-red-600 dark:text-red-400 mt-1">Reason: {device.disabled_reason}</p>
                  )}
                </div>

                {/* Confirm action */}
                {confirmAction?.deviceId === device.device_id && (
                  <ConfirmActionPanel
                    action={confirmAction.action}
                    deviceName={device.device_name || 'this device'}
                    isLoading={overrideMutation.isPending || disableMutation.isPending}
                    onConfirm={(reason) => {
                      if (confirmAction.action === 'disable') {
                        disableMutation.mutate({ deviceId: device.device_id, reason: reason || 'Admin action' });
                      } else {
                        overrideMutation.mutate({ deviceId: device.device_id, action: confirmAction.action as 'force_logout' | 'force_wipe' | 'force_sync' });
                      }
                    }}
                    onCancel={() => setConfirmAction(null)}
                  />
                )}

                <div className="grid grid-cols-2 gap-2 text-xs text-gray-500 dark:text-gray-400">
                  <div>Registered: {formatDateTime(device.registered_at)}</div>
                  <div>Storage Policy: {device.storage_policy || '—'}</div>
                  <div>Media Policy: {device.media_policy || '—'}</div>
                  <div>Config Version: {device.config_version || '—'}</div>
                </div>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

const DIRECTION_LABELS: Record<string, string> = {
  push: 'Push',
  pull: 'Pull',
  full: 'Full Sync',
};


// ── Tab: Sync History ────────────────────────────────────────────

function SyncHistoryTab() {
  const { data: history, isLoading, refetch, isFetching } = useQuery({
    queryKey: ['sync-history'],
    queryFn: () => getSyncHistory(undefined, 100),
    staleTime: 15_000,
  });

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-16">
        <Spinner size="lg" />
      </div>
    );
  }

  if (!history || history.length === 0) {
    return (
      <EmptyState
        icon={<ArrowLeftRight className="h-12 w-12" />}
        title="No Sync History"
        description="Sync activity will appear here after devices connect to the shop."
      />
    );
  }

  // Group by date
  const grouped = history.reduce<Record<string, SyncBatch[]>>((acc, batch) => {
    const day = batch.started_at.slice(0, 10);
    (acc[day] ??= []).push(batch);
    return acc;
  }, {});

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <p className="text-sm text-gray-500 dark:text-gray-400">
          {history.length} sync session{history.length !== 1 ? 's' : ''}
        </p>
        <Button
          size="sm"
          variant="secondary"
          icon={<RefreshCw className={`h-3.5 w-3.5 ${isFetching ? 'animate-spin' : ''}`} />}
          onClick={() => refetch()}
        >
          <span className="hidden sm:inline">Refresh</span>
        </Button>
      </div>

      {Object.entries(grouped).map(([day, batches]) => (
        <div key={day}>
          <p className="text-xs font-semibold text-gray-400 dark:text-gray-500 uppercase tracking-wide mb-2">
            {new Date(day + 'T00:00:00').toLocaleDateString([], {
              weekday: 'short', month: 'short', day: 'numeric',
            })}
          </p>
          <div className="space-y-2">
            {batches.map((batch) => (
              <SyncBatchRow key={batch.id} batch={batch} />
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

function SyncBatchRow({ batch }: { batch: SyncBatch }) {
  const isOk = batch.status === 'completed';
  const isFailed = batch.status === 'failed';

  const StatusIcon = isOk
    ? CheckCircle
    : isFailed
      ? XCircle
      : Clock;

  const statusColor = isOk
    ? 'text-green-500 dark:text-green-400'
    : isFailed
      ? 'text-red-500 dark:text-red-400'
      : 'text-amber-500 dark:text-amber-400';

  return (
    <div className="flex items-center gap-3 px-3 py-2.5 bg-surface border border-border rounded-lg text-xs">
      <StatusIcon className={`h-4 w-4 flex-shrink-0 ${statusColor}`} />

      <div className="flex-1 min-w-0 grid grid-cols-2 sm:grid-cols-4 gap-x-4 gap-y-1">
        <div className="col-span-2 sm:col-span-1">
          <span className="text-gray-400 dark:text-gray-500">Device: </span>
          <span className="font-mono text-gray-900 dark:text-gray-100">
            {batch.device_id.slice(0, 8)}…
          </span>
        </div>
        <div>
          <span className="text-gray-400 dark:text-gray-500">Type: </span>
          <span className="text-gray-900 dark:text-gray-100">
            {DIRECTION_LABELS[batch.direction] ?? batch.direction}
          </span>
        </div>
        <div>
          <span className="text-gray-400 dark:text-gray-500">Sent: </span>
          <span className="text-gray-900 dark:text-gray-100">{batch.changes_sent}</span>
          <span className="text-gray-400 dark:text-gray-500"> / Received: </span>
          <span className="text-gray-900 dark:text-gray-100">{batch.changes_received}</span>
        </div>
        {batch.conflicts_resolved > 0 && (
          <div>
            <span className="text-amber-500 dark:text-amber-400">
              {batch.conflicts_resolved} conflict{batch.conflicts_resolved !== 1 ? 's' : ''}
            </span>
          </div>
        )}
      </div>

      <span className="text-gray-400 dark:text-gray-500 flex-shrink-0">
        {relativeTime(batch.started_at)}
      </span>
    </div>
  );
}

// ── Confirm Action Panel ─────────────────────────────────────────

function ConfirmActionPanel({
  action, deviceName, isLoading: loading, onConfirm, onCancel,
}: {
  action: string;
  deviceName: string;
  isLoading: boolean;
  onConfirm: (reason?: string) => void;
  onCancel: () => void;
}) {
  const [reason, setReason] = useState('');
  const isDestructive = action === 'force_wipe' || action === 'disable';
  const labels: Record<string, { title: string; desc: string; confirm: string }> = {
    force_logout: {
      title: 'Force Logout',
      desc: `The next time ${deviceName} contacts the shop, it will be signed out. The user will need to re-enter their PIN.`,
      confirm: 'Force Logout',
    },
    force_wipe: {
      title: '⚠️ Force Wipe',
      desc: `This will delete ALL local data on ${deviceName} the next time it contacts the shop. This cannot be undone.`,
      confirm: 'Wipe Device',
    },
    disable: {
      title: 'Disable Device',
      desc: `${deviceName} will be locked out of the system until re-enabled. Provide a reason.`,
      confirm: 'Disable',
    },
  };
  const l = labels[action] ?? { title: action, desc: '', confirm: 'Confirm' };

  return (
    <div className={`p-3 rounded-lg border ${isDestructive ? 'bg-red-50 dark:bg-red-900/20 border-red-200 dark:border-red-800' : 'bg-amber-50 dark:bg-amber-900/20 border-amber-200 dark:border-amber-800'}`}>
      <div className="flex items-start gap-2 mb-2">
        <AlertTriangle className={`h-4 w-4 mt-0.5 flex-shrink-0 ${isDestructive ? 'text-red-500' : 'text-amber-500'}`} />
        <div>
          <p className={`text-sm font-medium ${isDestructive ? 'text-red-700 dark:text-red-300' : 'text-amber-700 dark:text-amber-300'}`}>
            {l.title}
          </p>
          <p className={`text-xs mt-0.5 ${isDestructive ? 'text-red-600 dark:text-red-400' : 'text-amber-600 dark:text-amber-400'}`}>
            {l.desc}
          </p>
        </div>
      </div>
      {action === 'disable' && (
        <input
          type="text" placeholder="Reason for disabling…" value={reason}
          onChange={(e) => setReason(e.target.value)}
          className="w-full text-sm px-3 py-1.5 rounded-lg border border-border bg-surface mb-2"
        />
      )}
      <div className="flex gap-2">
        <Button size="sm" variant={isDestructive ? 'danger' : 'warning'} isLoading={loading}
          onClick={() => onConfirm(reason || undefined)}>
          {l.confirm}
        </Button>
        <Button size="sm" variant="secondary" onClick={onCancel}>Cancel</Button>
      </div>
    </div>
  );
}



// ── Tab: Health & Errors ─────────────────────────────────────────

function HealthErrorsTab() {
  const queryClient = useQueryClient();
  const [severity, setSeverity] = useState<string>('all');
  const [expandedId, setExpandedId] = useState<number | null>(null);

  const { data: errors, isLoading, refetch, isFetching } = useQuery({
    queryKey: ['device-errors', severity],
    queryFn: () => listAllErrors(severity !== 'all' ? { severity } : undefined),
    staleTime: 15_000,
  });

  const resolveMutation = useMutation({
    mutationFn: (errorId: number) => resolveError(errorId),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['device-errors'] }),
  });

  if (isLoading) return <div className="flex items-center justify-center py-16"><Spinner size="lg" /></div>;

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3 flex-wrap">
        <div className="flex gap-1 bg-surface-secondary rounded-lg p-0.5 border border-border">
          {['all', 'critical', 'error', 'warning', 'info'].map((s) => (
            <button key={s} onClick={() => setSeverity(s)}
              className={`px-2.5 py-1 rounded-md text-xs font-medium capitalize transition-colors ${severity === s ? 'bg-surface text-gray-900 dark:text-gray-100 shadow-sm' : 'text-gray-500 hover:text-gray-700 dark:hover:text-gray-300'
                }`}>
              {s}
            </button>
          ))}
        </div>
        <div className="ml-auto">
          <Button size="sm" variant="secondary"
            icon={<RefreshCw className={`h-3.5 w-3.5 ${isFetching ? 'animate-spin' : ''}`} />}
            onClick={() => refetch()}>
            <span className="hidden sm:inline">Refresh</span>
          </Button>
        </div>
      </div>

      {(!errors || errors.length === 0) ? (
        <EmptyState icon={<CheckCircle className="h-12 w-12" />} title="No Errors"
          description={severity === 'all' ? 'No device errors have been reported.' : `No ${severity}-level errors.`} />
      ) : (
        <div className="space-y-2">
          <p className="text-sm text-gray-500 dark:text-gray-400">
            {errors.length} error{errors.length !== 1 ? 's' : ''}
          </p>
          {errors.map((err: DeviceErrorLog) => (
            <ErrorRow key={err.id} error={err} isExpanded={expandedId === err.id}
              onToggle={() => setExpandedId(expandedId === err.id ? null : err.id)}
              onResolve={() => resolveMutation.mutate(err.id)}
              isResolving={resolveMutation.isPending} />
          ))}
        </div>
      )}
    </div>
  );
}

function ErrorRow({ error, isExpanded, onToggle, onResolve, isResolving }: {
  error: DeviceErrorLog; isExpanded: boolean; onToggle: () => void;
  onResolve: () => void; isResolving: boolean;
}) {
  const severityColor: Record<string, string> = {
    critical: 'text-red-600 dark:text-red-400 bg-red-50 dark:bg-red-900/20 border-red-200 dark:border-red-800',
    error: 'text-red-500 dark:text-red-400 bg-red-50/50 dark:bg-red-900/10 border-red-200 dark:border-red-800',
    warning: 'text-amber-600 dark:text-amber-400 bg-amber-50 dark:bg-amber-900/20 border-amber-200 dark:border-amber-800',
    info: 'text-blue-600 dark:text-blue-400 bg-blue-50 dark:bg-blue-900/20 border-blue-200 dark:border-blue-800',
  };
  const colors = severityColor[error.severity] ?? severityColor.info;

  return (
    <div className={`border rounded-xl overflow-hidden ${colors.split(' ').filter(c => c.startsWith('border-')).join(' ')}`}>
      <button onClick={onToggle}
        className={`w-full flex items-center gap-3 px-4 py-3 text-left transition-colors ${colors.split(' ').filter(c => c.startsWith('bg-')).join(' ')} hover:opacity-80`}>
        <AlertOctagon className={`h-4 w-4 flex-shrink-0 ${colors.split(' ').filter(c => c.startsWith('text-')).join(' ')}`} />
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <Badge variant={error.severity === 'critical' || error.severity === 'error' ? 'danger' : error.severity === 'warning' ? 'warning' : 'default'}>
              {error.severity}
            </Badge>
            <span className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
              {error.error_type}
            </span>
          </div>
          <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5 truncate">
            Device <span className="font-mono">{error.device_id.slice(0, 8)}…</span>
            {' · '}{relativeTime(error.occurred_at)}
            {error.resolved_at && ' · ✓ Resolved'}
          </p>
        </div>
        {isExpanded ? <ChevronUp className="h-4 w-4 text-gray-400" /> : <ChevronDown className="h-4 w-4 text-gray-400" />}
      </button>

      {isExpanded && (
        <div className="px-4 pb-4 pt-2 bg-surface-secondary border-t border-border space-y-3">
          <p className="text-sm text-gray-700 dark:text-gray-300">{error.message}</p>
          {error.stack_trace && (
            <pre className="text-xs bg-surface rounded-lg p-2 border border-border overflow-x-auto text-gray-600 dark:text-gray-400 whitespace-pre-wrap break-all max-h-48 overflow-y-auto">
              {error.stack_trace}
            </pre>
          )}
          <div className="flex items-center gap-3 text-xs text-gray-500">
            <span>Occurred: {formatDateTime(error.occurred_at)}</span>
            {error.context_json && <span>Context: {error.context_json}</span>}
          </div>
          {!error.resolved_at && (
            <Button size="sm" variant="secondary" icon={<CheckCircle className="h-3.5 w-3.5" />}
              onClick={onResolve} isLoading={isResolving}>
              Mark Resolved
            </Button>
          )}
        </div>
      )}
    </div>
  );
}


// ── Tab: BT Encounters ───────────────────────────────────────────

function BtEncountersTab() {
  const { data: encounters, isLoading, refetch, isFetching } = useQuery({
    queryKey: ['bt-encounters'],
    queryFn: () => listBtEncounters(),
    staleTime: 30_000,
  });

  if (isLoading) return <div className="flex items-center justify-center py-16"><Spinner size="lg" /></div>;

  if (!encounters || encounters.length === 0) {
    return (
      <EmptyState icon={<Bluetooth className="h-12 w-12" />} title="No BT Encounters"
        description="Bluetooth sync encounters will appear here when devices exchange data via BT mesh." />
    );
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <p className="text-sm text-gray-500 dark:text-gray-400">
          {encounters.length} encounter{encounters.length !== 1 ? 's' : ''}
        </p>
        <Button size="sm" variant="secondary"
          icon={<RefreshCw className={`h-3.5 w-3.5 ${isFetching ? 'animate-spin' : ''}`} />}
          onClick={() => refetch()}>
          <span className="hidden sm:inline">Refresh</span>
        </Button>
      </div>

      {encounters.map((enc: BtEncounter) => (
        <div key={enc.id} className="flex items-center gap-3 px-3 py-2.5 bg-surface border border-border rounded-lg text-xs">
          <Bluetooth className="h-4 w-4 text-blue-500 flex-shrink-0" />
          <div className="flex-1 min-w-0 grid grid-cols-2 sm:grid-cols-4 gap-x-4 gap-y-1">
            <div>
              <span className="text-gray-400 dark:text-gray-500">From: </span>
              <span className="font-mono text-gray-900 dark:text-gray-100">{enc.local_device_id.slice(0, 8)}…</span>
              {enc.local_name && <span className="text-gray-400"> ({enc.local_name})</span>}
            </div>
            <div>
              <span className="text-gray-400 dark:text-gray-500">To: </span>
              <span className="font-mono text-gray-900 dark:text-gray-100">{enc.remote_device_id.slice(0, 8)}…</span>
              {enc.remote_name && <span className="text-gray-400"> ({enc.remote_name})</span>}
            </div>
            <div>
              <span className="text-gray-400 dark:text-gray-500">Sent/Recv: </span>
              <span className="text-gray-900 dark:text-gray-100">{enc.changes_sent}/{enc.changes_received}</span>
            </div>
            <div className="flex items-center gap-2">
              <Badge variant={enc.status === 'completed' ? 'success' : enc.status === 'failed' ? 'danger' : 'default'}>
                {enc.status}
              </Badge>
              {enc.signal_strength != null && (
                <span className="text-gray-400">
                  {enc.signal_strength} dBm
                </span>
              )}
            </div>
          </div>
          <span className="text-gray-400 dark:text-gray-500 flex-shrink-0">
            {relativeTime(enc.encounter_start)}
          </span>
        </div>
      ))}
    </div>
  );
}


// ── Tab: Cluster ─────────────────────────────────────────────────

function ClusterTab() {
  const queryClient = useQueryClient();

  const { data: nodes, isLoading, refetch, isFetching } = useQuery({
    queryKey: ['cluster-nodes'],
    queryFn: listClusterNodes,
    staleTime: 30_000,
  });

  const setPrimaryMutation = useMutation({
    mutationFn: setClusterPrimary,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['cluster-nodes'] }),
  });

  if (isLoading) return <div className="flex items-center justify-center py-16"><Spinner size="lg" /></div>;

  if (!nodes || nodes.length === 0) {
    return (
      <EmptyState icon={<Server className="h-12 w-12" />} title="No Cluster Nodes"
        description="Shop cluster nodes register themselves when the backend starts. If you only have one shop computer, the cluster view will show a single node." />
    );
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <p className="text-sm text-gray-500 dark:text-gray-400">
          {nodes.length} node{nodes.length !== 1 ? 's' : ''} in cluster
        </p>
        <Button size="sm" variant="secondary"
          icon={<RefreshCw className={`h-3.5 w-3.5 ${isFetching ? 'animate-spin' : ''}`} />}
          onClick={() => refetch()}>
          <span className="hidden sm:inline">Refresh</span>
        </Button>
      </div>

      {nodes.map((node: ClusterNode) => (
        <div key={node.id}
          className={`p-4 border rounded-xl space-y-2 ${node.is_primary ? 'border-primary-300 dark:border-primary-700 bg-primary-50/50 dark:bg-primary-900/10' : 'border-border bg-surface'
            }`}>
          <div className="flex items-center gap-3">
            <Server className={`h-5 w-5 ${node.is_primary ? 'text-primary-500' : 'text-gray-400'}`} />
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2 flex-wrap">
                <span className="font-medium text-sm text-gray-900 dark:text-gray-100">{node.hostname ?? 'Unknown'}</span>
                {node.is_primary ? <Badge variant="success">Primary</Badge> : null}
                <span className="text-xs text-gray-500 dark:text-gray-400">{node.local_ip}</span>
                <Badge variant={node.status === 'online' ? 'success' : node.status === 'syncing' ? 'warning' : 'default'}>{node.status}</Badge>
              </div>
              <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                Port {node.port} · Last sync: {relativeTime(node.last_sync_at)} · Seen: {relativeTime(node.last_seen_at)}
              </p>
            </div>
            {!node.is_primary && (
              <Button size="sm" variant="secondary"
                onClick={() => setPrimaryMutation.mutate(String(node.id))}
                isLoading={setPrimaryMutation.isPending}>
                Set Primary
              </Button>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}


// ── Tab: Setup Helper ────────────────────────────────────────────

type SetupPlatform = 'ios' | 'ipad' | 'android';

type SetupGuide = {
  title: string;
  subtitle: string;
  prerequisites: string[];
  steps: string[];
  updateSteps: string[];
  troubleshooting: string[];
};

const SETUP_GUIDES: Record<SetupPlatform, SetupGuide> = {
  ios: {
    title: 'iPhone Setup (Free Sideload)',
    subtitle: 'Sideloadly + AltServer · 7-day signing auto-refresh on shop Wi-Fi',
    prerequisites: [
      'Built IPA file from Mac/Xcode',
      'Sideloadly installed (Mac or Windows)',
      'AltServer running on shop computer',
      'USB cable + free Apple ID',
    ],
    steps: [
      'Connect iPhone by USB and tap Trust This Computer.',
      'Open Sideloadly and choose the iPhone in the device dropdown.',
      'Drag WiredPart.ipa into Sideloadly and click Start.',
      'After install, trust the developer profile in Settings → General → VPN & Device Management.',
      'Open Wired-Part, connect to shop Wi-Fi, then scan setup QR or enter shop IP manually.',
      'Run initial sync and sign in with PIN.',
    ],
    updateSteps: [
      'Build new IPA on Mac (npm run build → npx cap sync ios → Archive).',
      'Re-sideload updated IPA with Sideloadly.',
      'No data loss — local DB is preserved and migrations run on first launch.',
    ],
    troubleshooting: [
      "App won't open after 7 days: ensure AltServer is running and device is on same Wi-Fi.",
      'Untrusted Developer warning: trust profile in VPN & Device Management.',
      'Shop unreachable: verify same Wi-Fi as shop computer; app still works offline.',
    ],
  },
  ipad: {
    title: 'iPad Setup (Same as iPhone)',
    subtitle: 'Universal iOS app · tablet layout auto-optimized',
    prerequisites: [
      'Built IPA file from Mac/Xcode',
      'Sideloadly installed (Mac or Windows)',
      'AltServer running on shop computer',
      'USB cable + free Apple ID',
    ],
    steps: [
      'Connect iPad by USB and tap Trust This Computer.',
      'Open Sideloadly, choose iPad, and install WiredPart.ipa.',
      'Trust developer profile in Settings → General → VPN & Device Management.',
      'Open app, connect to shop Wi-Fi, complete setup QR/IP pairing.',
      'Run first sync, then sign in with PIN.',
      'Use landscape for best tablet workflow (sidebar stays visible).',
    ],
    updateSteps: [
      'Export new IPA from Xcode archive.',
      'Re-sideload IPA to iPad through Sideloadly.',
      'Data remains intact across updates.',
    ],
    troubleshooting: [
      'If app expires, connect to shop Wi-Fi so AltServer can refresh signing.',
      'If setup QR fails, manually enter shop IP in app settings.',
      'If sync appears stuck, open Sync status and retry once on stable Wi-Fi.',
    ],
  },
  android: {
    title: 'Android Setup (APK Sideload)',
    subtitle: 'Direct APK install · no signing expiry',
    prerequisites: [
      'Signed release APK (app-release.apk)',
      'APK shared via shop URL, email, or file transfer',
      'Allow Install unknown apps for browser/file manager',
    ],
    steps: [
      'Download APK on the Android device.',
      'Enable Install unknown apps when prompted.',
      'Tap APK and install Wired-Part.',
      'Open app and connect to shop Wi-Fi.',
      'Scan setup QR or manually enter shop IP.',
      'Run initial sync and sign in with PIN.',
    ],
    updateSteps: [
      'Build new signed APK (same keystore as prior versions).',
      'Install new APK over existing app.',
      'Local data is preserved; migrations apply automatically.',
    ],
    troubleshooting: [
      'App not installed: usually mismatched signing key — rebuild with original keystore.',
      'Play Protect warning: expected for sideloaded apps; allow install.',
      'Sync unreachable: join shop Wi-Fi; offline features still work meanwhile.',
    ],
  },
};

function SetupHelperTab() {
  const [platform, setPlatform] = useState<SetupPlatform>('ios');
  const guide = SETUP_GUIDES[platform];

  return (
    <div className="space-y-4">
      <div className="p-3 rounded-xl border border-emerald-200 dark:border-emerald-800 bg-emerald-50 dark:bg-emerald-900/20">
        <p className="text-sm text-emerald-800 dark:text-emerald-300">
          Fast helper: choose a device type and follow the checklist to install and pair in minutes.
        </p>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
        {([
          { id: 'ios', label: 'iPhone', icon: Smartphone },
          { id: 'ipad', label: 'iPad', icon: Tablet },
          { id: 'android', label: 'Android', icon: Smartphone },
        ] as const).map(({ id, label, icon: Icon }) => (
          <button key={id} onClick={() => setPlatform(id)}
            className={`min-h-11 px-3 py-2 rounded-lg border text-sm font-medium flex items-center justify-center gap-2 transition-colors ${platform === id
                ? 'bg-primary-600 text-white border-primary-600'
                : 'bg-surface border-border text-gray-700 dark:text-gray-300 hover:bg-surface-secondary'
              }`}>
            <Icon className="h-4 w-4" />
            {label}
          </button>
        ))}
      </div>

      <div className="rounded-xl border border-border bg-surface p-4 space-y-4">
        <div>
          <h3 className="text-base font-semibold text-gray-900 dark:text-gray-100">{guide.title}</h3>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">{guide.subtitle}</p>
        </div>
        <HelperSection icon={<Wrench className="h-4 w-4 text-gray-500" />} title="Before you start" items={guide.prerequisites} />
        <HelperSection icon={<Cable className="h-4 w-4 text-gray-500" />} title="Install + pair" items={guide.steps} numbered />
        <HelperSection icon={<Download className="h-4 w-4 text-gray-500" />} title="Update later" items={guide.updateSteps} numbered />
        <HelperSection icon={<Info className="h-4 w-4 text-amber-500" />} title="Quick troubleshooting" items={guide.troubleshooting} />
      </div>
    </div>
  );
}

function HelperSection({ icon, title, items, numbered = false }: {
  icon: React.ReactNode; title: string; items: string[]; numbered?: boolean;
}) {
  return (
    <div className="space-y-2">
      <div className="flex items-center gap-2">
        {icon}
        <h4 className="text-sm font-semibold text-gray-800 dark:text-gray-200">{title}</h4>
      </div>
      <ul className="space-y-1.5">
        {items.map((item, idx) => (
          <li key={`${title}-${idx}`} className="text-sm text-gray-700 dark:text-gray-300 flex gap-2">
            <span className="text-gray-400 dark:text-gray-500 w-5 flex-shrink-0 text-right">
              {numbered ? `${idx + 1}.` : '•'}
            </span>
            <span>{item}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}


// ── Main Page (6-tab layout) ─────────────────────────────────────

type Tab = 'devices' | 'errors' | 'bluetooth' | 'history' | 'cluster' | 'setup';

const TABS: { id: Tab; label: string; shortLabel?: string; icon: React.FC<{ className?: string }> }[] = [
  { id: 'devices', label: 'Devices', icon: Smartphone },
  { id: 'errors', label: 'Health & Errors', shortLabel: 'Errors', icon: AlertOctagon },
  { id: 'bluetooth', label: 'BT Encounters', shortLabel: 'BT', icon: Bluetooth },
  { id: 'history', label: 'Sync History', shortLabel: 'History', icon: ArrowUpDown },
  { id: 'cluster', label: 'Cluster', icon: Server },
  { id: 'setup', label: 'Setup Helper', shortLabel: 'Setup', icon: Tablet },
];

export function DeviceManagementPage() {
  const [tab, setTab] = useState<Tab>('devices');

  return (
    <div className="space-y-5">
      {/* Header */}
      <div>
        <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
          Device Management
        </h2>
        <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
          Monitor, manage, and troubleshoot all devices syncing with this shop.
        </p>
      </div>

      {/* Tab bar */}
      <div className="flex gap-1 overflow-x-auto bg-surface-secondary rounded-xl p-1 border border-border">
        {TABS.map(({ id, label, shortLabel, icon: Icon }) => (
          <button key={id} onClick={() => setTab(id)}
            className={`flex items-center gap-1.5 px-2.5 py-2 rounded-lg text-sm font-medium transition-colors whitespace-nowrap flex-1 justify-center min-w-0 ${tab === id
                ? 'bg-surface text-gray-900 dark:text-gray-100 shadow-sm'
                : 'text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
              }`}>
            <Icon className="h-4 w-4 flex-shrink-0" />
            <span className="hidden sm:inline">{label}</span>
            {shortLabel && <span className="sm:hidden">{shortLabel}</span>}
            {!shortLabel && <span className="sm:hidden">{label}</span>}
          </button>
        ))}
      </div>

      {/* Tab content */}
      <Card>
        <div className="p-1">
          {tab === 'devices' && <DevicesTab />}
          {tab === 'errors' && <HealthErrorsTab />}
          {tab === 'bluetooth' && <BtEncountersTab />}
          {tab === 'history' && <SyncHistoryTab />}
          {tab === 'cluster' && <ClusterTab />}
          {tab === 'setup' && <SetupHelperTab />}
        </div>
      </Card>
    </div>
  );
}
