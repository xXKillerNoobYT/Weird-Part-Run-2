/**
 * DeviceManagementPage — v1.0 real implementation.
 *
 * Three tabs:
 *   Devices      — registry of every phone/tablet that has synced, with revoke
 *   Sync History — recent sync batches (what moved and when)
 *   Conflicts    — records where device and shop disagreed, and how it was resolved
 *
 * All data comes from the sync router (/api/sync/*).
 * Requires manage_people permission (same as the backend endpoints).
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Monitor, Smartphone, Tablet, Globe, RefreshCw, ArrowLeftRight,
  AlertTriangle, CheckCircle, XCircle, Clock, Wifi, WifiOff,
  ShieldOff, ArrowUpDown, RotateCcw, ChevronDown, ChevronUp,
  Download, Cable, Wrench, Info,
} from 'lucide-react';
import { Card } from '../../../components/ui/Card';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { Spinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import {
  listSyncDevices, getSyncHistory, getSyncConflicts, revokeDevice,
} from '../../../api/sync';
import type { SyncBatch, SyncConflict } from '../../../api/sync';

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

/** A device is considered "recently active" if it synced within the last hour */
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
  if (p === 'ios' || p === 'android') {
    return <Smartphone className="h-5 w-5 text-gray-400 dark:text-gray-500 flex-shrink-0" />;
  }
  if (p === 'web') {
    return <Globe className="h-5 w-5 text-gray-400 dark:text-gray-500 flex-shrink-0" />;
  }
  return <Monitor className="h-5 w-5 text-gray-400 dark:text-gray-500 flex-shrink-0" />;
}

function platformLabel(platform: string | null): string {
  const p = (platform ?? '').toLowerCase();
  if (p === 'ios') return 'iPhone / iPad';
  if (p === 'android') return 'Android';
  if (p === 'web') return 'Web Browser';
  return 'Unknown';
}

const DIRECTION_LABELS: Record<string, string> = {
  push: 'Push',
  pull: 'Pull',
  full: 'Full Sync',
};

const RESOLUTION_LABELS: Record<string, string> = {
  device_wins: 'Device kept',
  shop_wins: 'Shop kept',
  merged: 'Merged',
};

// ── Tab: Devices ─────────────────────────────────────────────────

function DevicesTab() {
  const queryClient = useQueryClient();
  const [confirmRevoke, setConfirmRevoke] = useState<string | null>(null);

  const { data: devices, isLoading, refetch, isFetching } = useQuery({
    queryKey: ['sync-devices'],
    queryFn: listSyncDevices,
    staleTime: 15_000,
  });

  const revokeMutation = useMutation({
    mutationFn: revokeDevice,
    onSuccess: () => {
      setConfirmRevoke(null);
      queryClient.invalidateQueries({ queryKey: ['sync-devices'] });
    },
  });

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-16">
        <Spinner size="lg" />
      </div>
    );
  }

  if (!devices || devices.length === 0) {
    return (
      <EmptyState
        icon={<Smartphone className="h-12 w-12" />}
        title="No Devices Registered"
        description="Devices appear here after their first sync with the shop. Open the app on a phone or tablet and tap Sync to get started."
      />
    );
  }

  return (
    <div className="space-y-3">
      {/* Toolbar */}
      <div className="flex items-center justify-between">
        <p className="text-sm text-gray-500 dark:text-gray-400">
          {devices.length} device{devices.length !== 1 ? 's' : ''} registered
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

      {/* Device cards */}
      {devices.map((device) => {
        const active = isRecentlyActive(device.last_sync_at);
        const isRevoking = confirmRevoke === device.device_id;

        return (
          <div
            key={device.device_id}
            className="p-4 bg-surface border border-border rounded-xl space-y-3"
          >
            {/* Top row: icon + name + status */}
            <div className="flex items-start gap-3">
              <div className="mt-0.5">
                <PlatformIcon platform={device.platform} />
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="font-medium text-sm text-gray-900 dark:text-gray-100 truncate">
                    {device.device_name || 'Unnamed Device'}
                  </span>
                  <Badge variant={active ? 'success' : 'default'}>
                    {active ? (
                      <span className="flex items-center gap-1">
                        <Wifi className="h-3 w-3" /> Active
                      </span>
                    ) : (
                      <span className="flex items-center gap-1">
                        <WifiOff className="h-3 w-3" /> Idle
                      </span>
                    )}
                  </Badge>
                  {device.pending_changes > 0 && (
                    <Badge variant="warning">
                      {device.pending_changes} pending
                    </Badge>
                  )}
                </div>
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                  {platformLabel(device.platform)}
                  {' · '}
                  <span className="font-mono">{device.device_id.slice(0, 8)}…</span>
                </p>
              </div>

              {/* Revoke button */}
              {!isRevoking ? (
                <button
                  onClick={() => setConfirmRevoke(device.device_id)}
                  className="ml-auto text-xs text-red-500 hover:text-red-600 dark:text-red-400 dark:hover:text-red-300 transition-colors flex items-center gap-1 flex-shrink-0"
                  title="Revoke this device's sync access"
                >
                  <ShieldOff className="h-3.5 w-3.5" />
                  <span className="hidden sm:inline">Revoke</span>
                </button>
              ) : null}
            </div>

            {/* Stats row */}
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 text-xs">
              <div className="space-y-0.5">
                <p className="text-gray-400 dark:text-gray-500 uppercase tracking-wide text-[10px]">
                  Last Sync
                </p>
                <p className="text-gray-900 dark:text-gray-100 font-medium">
                  {relativeTime(device.last_sync_at)}
                </p>
                {device.last_sync_at && (
                  <p className="text-gray-500 dark:text-gray-400">
                    {formatDateTime(device.last_sync_at)}
                  </p>
                )}
              </div>
              <div className="space-y-0.5">
                <p className="text-gray-400 dark:text-gray-500 uppercase tracking-wide text-[10px]">
                  Registered
                </p>
                <p className="text-gray-900 dark:text-gray-100 font-medium">
                  {relativeTime(device.registered_at)}
                </p>
                <p className="text-gray-500 dark:text-gray-400">
                  {formatDateTime(device.registered_at)}
                </p>
              </div>
              <div className="space-y-0.5 col-span-2 sm:col-span-1">
                <p className="text-gray-400 dark:text-gray-500 uppercase tracking-wide text-[10px]">
                  Pending Changes
                </p>
                <p className={`font-medium ${device.pending_changes > 0
                    ? 'text-amber-600 dark:text-amber-400'
                    : 'text-gray-900 dark:text-gray-100'
                  }`}>
                  {device.pending_changes === 0
                    ? 'Up to date'
                    : `${device.pending_changes} change${device.pending_changes !== 1 ? 's' : ''} waiting`
                  }
                </p>
              </div>
            </div>

            {/* Revoke confirmation */}
            {isRevoking && (
              <div className="flex items-center gap-3 p-3 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800">
                <AlertTriangle className="h-4 w-4 text-red-500 flex-shrink-0" />
                <p className="text-sm text-red-700 dark:text-red-300 flex-1">
                  Remove <strong>{device.device_name || 'this device'}</strong> from sync? It will re-register on next sync.
                </p>
                <div className="flex gap-2">
                  <Button
                    size="sm"
                    variant="danger"
                    isLoading={revokeMutation.isPending}
                    onClick={() => revokeMutation.mutate(device.device_id)}
                  >
                    Revoke
                  </Button>
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={() => setConfirmRevoke(null)}
                  >
                    Cancel
                  </Button>
                </div>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

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

// ── Tab: Conflicts ────────────────────────────────────────────────

function ConflictsTab() {
  const [expanded, setExpanded] = useState<number | null>(null);

  const { data: conflicts, isLoading, refetch, isFetching } = useQuery({
    queryKey: ['sync-conflicts'],
    queryFn: () => getSyncConflicts(100),
    staleTime: 30_000,
  });

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-16">
        <Spinner size="lg" />
      </div>
    );
  }

  if (!conflicts || conflicts.length === 0) {
    return (
      <EmptyState
        icon={<CheckCircle className="h-12 w-12" />}
        title="No Conflicts"
        description="Great news — no sync conflicts have occurred. Conflicts happen when the same record is changed on two devices at the same time."
      />
    );
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <p className="text-sm text-gray-500 dark:text-gray-400">
          {conflicts.length} conflict{conflicts.length !== 1 ? 's' : ''} resolved
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

      {conflicts.map((c) => (
        <ConflictRow
          key={c.id}
          conflict={c}
          isExpanded={expanded === c.id}
          onToggle={() => setExpanded(expanded === c.id ? null : c.id)}
        />
      ))}
    </div>
  );
}

function ConflictRow({
  conflict, isExpanded, onToggle,
}: {
  conflict: SyncConflict;
  isExpanded: boolean;
  onToggle: () => void;
}) {
  const resVariant =
    conflict.resolution === 'shop_wins' ? 'default'
      : conflict.resolution === 'device_wins' ? 'warning'
        : 'success';

  let deviceVals: Record<string, unknown> | null = null;
  let shopVals: Record<string, unknown> | null = null;
  try {
    if (conflict.device_values) deviceVals = JSON.parse(conflict.device_values);
    if (conflict.shop_values) shopVals = JSON.parse(conflict.shop_values);
  } catch { /* ignore parse errors */ }

  return (
    <div className="border border-border rounded-xl overflow-hidden">
      {/* Summary row */}
      <button
        onClick={onToggle}
        className="w-full flex items-center gap-3 px-4 py-3 bg-surface hover:bg-surface-secondary transition-colors text-left"
      >
        <AlertTriangle className="h-4 w-4 text-amber-500 flex-shrink-0" />
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-sm font-medium text-gray-900 dark:text-gray-100">
              {conflict.table_name}
            </span>
            <span className="text-xs text-gray-500 dark:text-gray-400">
              #{conflict.record_id}
            </span>
            <Badge variant={resVariant}>
              {RESOLUTION_LABELS[conflict.resolution] ?? conflict.resolution}
            </Badge>
          </div>
          <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
            Device <span className="font-mono">{(conflict.device_a_id ?? '').slice(0, 8)}…</span>
            {' · '}
            {relativeTime(conflict.resolved_at)}
          </p>
        </div>
        {isExpanded
          ? <ChevronUp className="h-4 w-4 text-gray-400 flex-shrink-0" />
          : <ChevronDown className="h-4 w-4 text-gray-400 flex-shrink-0" />
        }
      </button>

      {/* Expanded detail */}
      {isExpanded && (
        <div className="px-4 pb-4 pt-2 bg-surface-secondary border-t border-border space-y-3">
          {deviceVals && (
            <div>
              <p className="text-[10px] uppercase tracking-wide text-amber-600 dark:text-amber-400 font-semibold mb-1">
                Device had
              </p>
              <pre className="text-xs bg-surface rounded-lg p-2 border border-border overflow-x-auto text-gray-700 dark:text-gray-300 whitespace-pre-wrap break-all">
                {JSON.stringify(deviceVals, null, 2)}
              </pre>
            </div>
          )}
          {shopVals && (
            <div>
              <p className="text-[10px] uppercase tracking-wide text-blue-600 dark:text-blue-400 font-semibold mb-1">
                Shop had
              </p>
              <pre className="text-xs bg-surface rounded-lg p-2 border border-border overflow-x-auto text-gray-700 dark:text-gray-300 whitespace-pre-wrap break-all">
                {JSON.stringify(shopVals, null, 2)}
              </pre>
            </div>
          )}
          <p className="text-xs text-gray-500 dark:text-gray-400">
            Resolved {formatDateTime(conflict.resolved_at)} — {RESOLUTION_LABELS[conflict.resolution] ?? conflict.resolution}
          </p>
        </div>
      )}
    </div>
  );
}

// ── Main Page ────────────────────────────────────────────────────

type Tab = 'devices' | 'history' | 'conflicts' | 'setup';
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
      'App won\'t open after 7 days: ensure AltServer is running and device is on same Wi-Fi.',
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
          <button
            key={id}
            onClick={() => setPlatform(id)}
            className={`min-h-11 px-3 py-2 rounded-lg border text-sm font-medium flex items-center justify-center gap-2 transition-colors ${platform === id
                ? 'bg-primary-600 text-white border-primary-600'
                : 'bg-surface border-border text-gray-700 dark:text-gray-300 hover:bg-surface-secondary'
              }`}
          >
            <Icon className="h-4 w-4" />
            {label}
          </button>
        ))}
      </div>

      <div className="rounded-xl border border-border bg-surface p-4 space-y-4">
        <div>
          <h3 className="text-base font-semibold text-gray-900 dark:text-gray-100">
            {guide.title}
          </h3>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
            {guide.subtitle}
          </p>
        </div>

        <HelperSection
          icon={<Wrench className="h-4 w-4 text-gray-500" />}
          title="Before you start"
          items={guide.prerequisites}
        />

        <HelperSection
          icon={<Cable className="h-4 w-4 text-gray-500" />}
          title="Install + pair"
          items={guide.steps}
          numbered
        />

        <HelperSection
          icon={<Download className="h-4 w-4 text-gray-500" />}
          title="Update later"
          items={guide.updateSteps}
          numbered
        />

        <HelperSection
          icon={<Info className="h-4 w-4 text-amber-500" />}
          title="Quick troubleshooting"
          items={guide.troubleshooting}
        />
      </div>
    </div>
  );
}

function HelperSection({
  icon,
  title,
  items,
  numbered = false,
}: {
  icon: React.ReactNode;
  title: string;
  items: string[];
  numbered?: boolean;
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

const TABS: { id: Tab; label: string; icon: React.FC<{ className?: string }> }[] = [
  { id: 'devices', label: 'Devices', icon: Smartphone },
  { id: 'history', label: 'Sync History', icon: ArrowUpDown },
  { id: 'conflicts', label: 'Conflicts', icon: AlertTriangle },
  { id: 'setup', label: 'Setup Helper', icon: Tablet },
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
          Monitor and manage devices syncing with this shop computer.
        </p>
      </div>

      {/* Info banner */}
      <div className="flex items-start gap-3 p-3 rounded-xl bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800">
        <RotateCcw className="h-4 w-4 text-blue-500 mt-0.5 flex-shrink-0" />
        <p className="text-sm text-blue-700 dark:text-blue-300">
          Devices sync over your local network (LAN). Revoking a device removes it from
          the registry — it can re-register automatically on next sync. No data is lost.
        </p>
      </div>

      {/* Tab bar */}
      <div className="flex gap-1 overflow-x-auto bg-surface-secondary rounded-xl p-1 border border-border">
        {TABS.map(({ id, label, icon: Icon }) => (
          <button
            key={id}
            onClick={() => setTab(id)}
            className={`flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-medium transition-colors whitespace-nowrap flex-1 justify-center ${tab === id
                ? 'bg-surface text-gray-900 dark:text-gray-100 shadow-sm'
                : 'text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
              }`}
          >
            <Icon className="h-4 w-4" />
            <span>{label}</span>
          </button>
        ))}
      </div>

      {/* Tab content */}
      <Card>
        <div className="p-1">
          {tab === 'devices' && <DevicesTab />}
          {tab === 'history' && <SyncHistoryTab />}
          {tab === 'conflicts' && <ConflictsTab />}
          {tab === 'setup' && <SetupHelperTab />}
        </div>
      </Card>
    </div>
  );
}
