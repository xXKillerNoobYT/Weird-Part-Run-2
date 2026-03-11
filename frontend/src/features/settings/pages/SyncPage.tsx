/**
 * SyncPage — data synchronization settings and status.
 *
 * Shows sync status, device registry, device sync profiles with
 * editable policies, relay health dashboard, sync history,
 * and conflict log for admin users. Also provides shop URL
 * configuration for Capacitor devices.
 */

import { useState, useEffect } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  CloudOff, RefreshCw, CheckCircle, AlertCircle,
  Smartphone, Monitor, Settings2, History, ShieldAlert,
  Radio, Package, FileCheck, ChevronDown, ChevronRight,
  Save, ArrowRightLeft, Activity, Bluetooth,
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
  getDeviceSyncProfile,
  updateDeviceSyncProfile,
  getMeshRelayEvents,
  listRelayManifests,
  listRelayPackages,
  listDeliveryReceipts,
  getRelayStats,
} from '../../../api/sync';
import type {
  SyncDevice,
  DeviceSyncProfileUpdate,
} from '../../../api/sync';
import { isCapacitor } from '../../../lib/environment';
import {
  checkBtAvailability,
  getBtTunnelStatus,
  listPairedDevices,
} from '../../../api/bluetooth';
import { Link } from 'react-router-dom';

export function SyncPage() {
  return (
    <div className="space-y-6">
      <h2 className="text-xl font-bold text-gray-900 dark:text-gray-100">
        Sync & Devices
      </h2>

      {/* Shop Connection (Capacitor only) */}
      {isCapacitor() && <ShopConnectionCard />}

      {/* Bluetooth Sync Status (Windows PCs) */}
      {!isCapacitor() && <BluetoothSyncCard />}

      {/* Registered Devices */}
      <DeviceRegistryCard />

      {/* Device Sync Profiles */}
      <DeviceSyncProfilesCard />

      {/* Mesh Relay Health */}
      <MeshRelayHealthCard />

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

// ── Bluetooth Sync Card (Windows PCs) ────────────────────────────

const BT_STATE_COLORS: Record<string, string> = {
  connected: 'text-green-600 dark:text-green-400',
  listening: 'text-blue-600 dark:text-blue-400',
  connecting: 'text-yellow-600 dark:text-yellow-400',
  reconnecting: 'text-yellow-600 dark:text-yellow-400',
  idle: 'text-gray-500 dark:text-gray-400',
  stopped: 'text-gray-400 dark:text-gray-500',
  error: 'text-red-600 dark:text-red-400',
};

const BT_STATE_LABELS: Record<string, string> = {
  connected: 'Connected',
  listening: 'Listening for devices…',
  connecting: 'Connecting…',
  reconnecting: 'Reconnecting…',
  idle: 'Idle',
  stopped: 'Stopped',
  error: 'Error',
};

function BluetoothSyncCard() {
  const { data: availability } = useQuery({
    queryKey: ['bt-availability'],
    queryFn: checkBtAvailability,
    retry: 1,
    staleTime: 60000,
  });

  const { data: tunnel } = useQuery({
    queryKey: ['bt-tunnel-status'],
    queryFn: getBtTunnelStatus,
    refetchInterval: 5000,
    enabled: availability?.available === true,
  });

  const { data: paired } = useQuery({
    queryKey: ['bt-paired-devices'],
    queryFn: listPairedDevices,
    staleTime: 30000,
    enabled: availability?.available === true,
  });

  // Not available — collapsed info row
  if (availability && !availability.available) {
    return (
      <div className="bg-surface border border-border rounded-lg p-4">
        <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
          <Bluetooth className="h-4 w-4 text-gray-400" />
          Bluetooth Sync
        </h3>
        <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
          Bluetooth not available on this machine.
          {availability.error && ` (${availability.error})`}
        </p>
      </div>
    );
  }

  const state = tunnel?.state ?? 'stopped';
  const stateColor = BT_STATE_COLORS[state] || BT_STATE_COLORS.idle;
  const stateLabel = BT_STATE_LABELS[state] || state;
  const pairedCount = paired?.length ?? 0;
  const activeDevice = paired?.find((d) => d.is_active);

  return (
    <div className="bg-surface border border-border rounded-lg p-4 space-y-3">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
          <Bluetooth className="h-4 w-4 text-blue-500" />
          Bluetooth Sync
        </h3>
        <Link
          to="/settings/bluetooth"
          className="text-xs text-blue-600 dark:text-blue-400 hover:underline"
        >
          Manage →
        </Link>
      </div>

      {/* Status row */}
      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
        <span className={`flex items-center gap-1 ${stateColor}`}>
          {state === 'connected' && <CheckCircle className="h-3.5 w-3.5" />}
          {(state === 'connecting' || state === 'reconnecting') && <RefreshCw className="h-3.5 w-3.5 animate-spin" />}
          {state === 'error' && <AlertCircle className="h-3.5 w-3.5" />}
          {stateLabel}
        </span>

        {tunnel?.mode && tunnel.mode !== 'none' && (
          <Badge variant="neutral">
            {tunnel.mode === 'primary' ? 'Shop (Primary)' : 'Field (Secondary)'}
          </Badge>
        )}
      </div>

      {/* Active device */}
      {activeDevice && (
        <div className="text-xs text-gray-500 dark:text-gray-400">
          Paired with <span className="font-medium text-gray-700 dark:text-gray-300">
            {activeDevice.display_name}
          </span>
          {' '}({activeDevice.bt_address})
        </div>
      )}

      {/* Stats */}
      {tunnel && state === 'connected' && (
        <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-gray-500 dark:text-gray-400">
          <span>Requests: {tunnel.requests_forwarded ?? 0}</span>
          <span>Bytes: {formatBytesCompact(tunnel.bytes_sent ?? 0)} ↑ / {formatBytesCompact(tunnel.bytes_received ?? 0)} ↓</span>
          {tunnel.uptime_seconds != null && (
            <span>Uptime: {formatUptimeCompact(tunnel.uptime_seconds)}</span>
          )}
        </div>
      )}

      {/* No paired devices prompt */}
      {pairedCount === 0 && (
        <p className="text-xs text-gray-500 dark:text-gray-400">
          No devices paired.{' '}
          <Link to="/settings/bluetooth" className="text-blue-600 dark:text-blue-400 hover:underline">
            Pair a device
          </Link>{' '}
          to enable Bluetooth sync.
        </p>
      )}
    </div>
  );
}

function formatBytesCompact(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatUptimeCompact(seconds: number): string {
  if (seconds < 60) return `${Math.round(seconds)}s`;
  if (seconds < 3600) return `${Math.round(seconds / 60)}m`;
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  return `${h}h ${m}m`;
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

// ── Device Sync Profiles Card ────────────────────────────────────

const STORAGE_POLICIES = [
  { value: 'active_jobs_core_only', label: 'Active Jobs Only', desc: 'Only store data for currently active jobs' },
  { value: 'all_jobs_core', label: 'All Jobs', desc: 'Store data for all jobs (active, completed, on-hold)' },
  { value: 'minimal', label: 'Minimal', desc: 'Bare minimum — only what\'s needed to operate' },
];

const MEDIA_POLICIES = [
  { value: 'all_jobs', label: 'All Jobs Media', desc: 'Photos/attachments for all jobs' },
  { value: 'assigned_jobs_only', label: 'Assigned Jobs Only', desc: 'Media only for jobs assigned to this device\'s primary user' },
  { value: 'thumbnails_only', label: 'Thumbnails Only', desc: 'Save bandwidth — only download thumbnails' },
  { value: 'last_n_days', label: 'Recent Only', desc: 'Media from the last N days (see retention setting)' },
  { value: 'none', label: 'No Media', desc: 'Don\'t store media locally (view on demand)' },
];

function DeviceSyncProfilesCard() {
  const [expandedDevice, setExpandedDevice] = useState<string | null>(null);

  const { data: devices = [], isLoading: devicesLoading } = useQuery({
    queryKey: ['sync-devices'],
    queryFn: listSyncDevices,
    retry: 1,
    staleTime: 30000,
  });

  return (
    <div className="bg-surface border border-border rounded-lg p-4 space-y-3">
      <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
        <Settings2 className="h-4 w-4" />
        Device Sync Profiles
      </h3>
      <p className="text-xs text-gray-500 dark:text-gray-400">
        Configure how each device stores data, handles media, and syncs.
        Profiles belong to the device's primary user — borrowed users cannot change these.
      </p>

      {devicesLoading ? (
        <PageSpinner label="Loading devices..." />
      ) : devices.length === 0 ? (
        <p className="text-sm text-gray-500 dark:text-gray-400">
          No devices registered. Profiles will appear after a device syncs.
        </p>
      ) : (
        <div className="space-y-2">
          {devices.map((d) => (
            <DeviceProfileRow
              key={d.device_id}
              device={d}
              expanded={expandedDevice === d.device_id}
              onToggle={() =>
                setExpandedDevice(expandedDevice === d.device_id ? null : d.device_id)
              }
            />
          ))}
        </div>
      )}
    </div>
  );
}

function DeviceProfileRow({
  device,
  expanded,
  onToggle,
}: {
  device: SyncDevice;
  expanded: boolean;
  onToggle: () => void;
}) {
  const queryClient = useQueryClient();

  const { data: profile, isLoading } = useQuery({
    queryKey: ['device-profile', device.device_id],
    queryFn: () => getDeviceSyncProfile(device.device_id),
    enabled: expanded,
    staleTime: 30000,
  });

  const [form, setForm] = useState<DeviceSyncProfileUpdate>({});
  const [dirty, setDirty] = useState(false);

  // Sync form with profile data when loaded
  useEffect(() => {
    if (profile) {
      setForm({
        storage_policy: profile.storage_policy,
        media_policy: profile.media_policy,
        media_retention_days: profile.media_retention_days,
        force_carry_undelivered_media: !!profile.force_carry_undelivered_media,
        allow_borrowed_user_overrides: !!profile.allow_borrowed_user_overrides,
        active_only_sync: !!profile.active_only_sync,
      });
      setDirty(false);
    }
  }, [profile]);

  const mutation = useMutation({
    mutationFn: (payload: DeviceSyncProfileUpdate) =>
      updateDeviceSyncProfile(device.device_id, payload),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['device-profile', device.device_id] });
      setDirty(false);
    },
  });

  function updateField(key: keyof DeviceSyncProfileUpdate, value: unknown) {
    setForm((prev) => ({ ...prev, [key]: value }));
    setDirty(true);
  }

  return (
    <div className="border border-border rounded-md">
      <button
        type="button"
        onClick={onToggle}
        className="w-full flex items-center gap-3 p-3 text-left hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors"
      >
        {device.platform === 'ios' || device.platform === 'android' ? (
          <Smartphone className="h-4 w-4 text-gray-400 shrink-0" />
        ) : (
          <Monitor className="h-4 w-4 text-gray-400 shrink-0" />
        )}
        <div className="flex-1 min-w-0">
          <span className="text-sm font-medium text-gray-900 dark:text-gray-100">
            {device.device_name || device.device_id}
          </span>
          <span className="text-xs text-gray-500 dark:text-gray-400 ml-2">
            {device.platform}
          </span>
        </div>
        {expanded ? (
          <ChevronDown className="h-4 w-4 text-gray-400" />
        ) : (
          <ChevronRight className="h-4 w-4 text-gray-400" />
        )}
      </button>

      {expanded && (
        <div className="px-3 pb-3 pt-1 border-t border-border space-y-3">
          {isLoading ? (
            <PageSpinner label="Loading profile..." />
          ) : !profile ? (
            <p className="text-sm text-gray-500 dark:text-gray-400">
              No profile found — it will be created on the device's next sync.
            </p>
          ) : (
            <>
              {/* Storage Policy */}
              <div>
                <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Storage Policy
                </label>
                <select
                  value={form.storage_policy || ''}
                  onChange={(e) => updateField('storage_policy', e.target.value)}
                  className="w-full min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                >
                  {STORAGE_POLICIES.map((p) => (
                    <option key={p.value} value={p.value}>{p.label}</option>
                  ))}
                </select>
                <p className="text-xs text-gray-400 mt-0.5">
                  {STORAGE_POLICIES.find((p) => p.value === form.storage_policy)?.desc}
                </p>
              </div>

              {/* Media Policy */}
              <div>
                <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Media Policy
                </label>
                <select
                  value={form.media_policy || ''}
                  onChange={(e) => updateField('media_policy', e.target.value)}
                  className="w-full min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                >
                  {MEDIA_POLICIES.map((p) => (
                    <option key={p.value} value={p.value}>{p.label}</option>
                  ))}
                </select>
                <p className="text-xs text-gray-400 mt-0.5">
                  {MEDIA_POLICIES.find((p) => p.value === form.media_policy)?.desc}
                </p>
              </div>

              {/* Media Retention Days */}
              {form.media_policy === 'last_n_days' && (
                <div>
                  <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                    Media Retention (days)
                  </label>
                  <input
                    type="number"
                    min={1}
                    max={365}
                    value={form.media_retention_days ?? 30}
                    onChange={(e) => updateField('media_retention_days', parseInt(e.target.value) || 30)}
                    className="w-32 min-h-11 px-3 py-2 text-sm border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
                  />
                </div>
              )}

              {/* Toggle switches */}
              <div className="space-y-2">
                <label className="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
                  <input
                    type="checkbox"
                    checked={!!form.force_carry_undelivered_media}
                    onChange={(e) => updateField('force_carry_undelivered_media', e.target.checked)}
                    className="h-4 w-4"
                  />
                  Force carry undelivered media
                  <span className="text-xs text-gray-400">(mandatory relay)</span>
                </label>

                <label className="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
                  <input
                    type="checkbox"
                    checked={!!form.active_only_sync}
                    onChange={(e) => updateField('active_only_sync', e.target.checked)}
                    className="h-4 w-4"
                  />
                  Active-only sync
                  <span className="text-xs text-gray-400">(skip completed/on-hold jobs)</span>
                </label>

                <label className="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300">
                  <input
                    type="checkbox"
                    checked={!!form.allow_borrowed_user_overrides}
                    onChange={(e) => updateField('allow_borrowed_user_overrides', e.target.checked)}
                    className="h-4 w-4"
                  />
                  Allow borrowed user overrides
                  <span className="text-xs text-gray-400">(let guest users change profile)</span>
                </label>
              </div>

              {/* Save button */}
              <div className="flex items-center gap-2">
                <Button
                  size="sm"
                  disabled={!dirty || mutation.isPending}
                  isLoading={mutation.isPending}
                  onClick={() => mutation.mutate(form)}
                >
                  <Save className="h-3.5 w-3.5 mr-1" />
                  Save Profile
                </Button>
                {mutation.isSuccess && !dirty && (
                  <span className="text-xs text-green-600 dark:text-green-400 flex items-center gap-1">
                    <CheckCircle className="h-3.5 w-3.5" /> Saved
                  </span>
                )}
                {mutation.isError && (
                  <span className="text-xs text-red-600 dark:text-red-400">
                    Failed to save
                  </span>
                )}
              </div>

              {/* Last updated */}
              <p className="text-xs text-gray-400">
                Last updated: {formatDate(profile.updated_at)}
                {profile.updated_by ? ` by user #${profile.updated_by}` : ''}
              </p>
            </>
          )}
        </div>
      )}
    </div>
  );
}

// ── Mesh Relay Health Card ───────────────────────────────────────

type RelayTab = 'overview' | 'events' | 'manifests' | 'packages' | 'receipts';

function MeshRelayHealthCard() {
  const [tab, setTab] = useState<RelayTab>('overview');
  const [filterDevice, setFilterDevice] = useState<string>('');

  const { data: devices = [] } = useQuery({
    queryKey: ['sync-devices'],
    queryFn: listSyncDevices,
    retry: 1,
    staleTime: 30000,
  });

  return (
    <div className="bg-surface border border-border rounded-lg p-4 space-y-3">
      <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex items-center gap-2">
        <Radio className="h-4 w-4" />
        Mesh Relay Health
      </h3>
      <p className="text-xs text-gray-500 dark:text-gray-400">
        Monitor peer-to-peer relay activity, delivery receipts, and mesh network health.
      </p>

      {/* Device filter */}
      {devices.length > 0 && (
        <div className="flex flex-wrap items-center gap-2">
          <label className="text-xs text-gray-500 dark:text-gray-400">Filter by device:</label>
          <select
            value={filterDevice}
            onChange={(e) => setFilterDevice(e.target.value)}
            className="min-h-9 px-2 py-1 text-xs border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
          >
            <option value="">All devices</option>
            {devices.map((d) => (
              <option key={d.device_id} value={d.device_id}>
                {d.device_name || d.device_id}
              </option>
            ))}
          </select>
        </div>
      )}

      {/* Tab bar */}
      <div className="flex flex-wrap gap-1 border-b border-border pb-1 overflow-x-auto">
        {([
          { key: 'overview', icon: Activity, label: 'Overview' },
          { key: 'events', icon: ArrowRightLeft, label: 'Events' },
          { key: 'manifests', icon: Radio, label: 'Manifests' },
          { key: 'packages', icon: Package, label: 'Packages' },
          { key: 'receipts', icon: FileCheck, label: 'Receipts' },
        ] as const).map(({ key, icon: Icon, label }) => (
          <button
            key={key}
            type="button"
            onClick={() => setTab(key)}
            className={`flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-t-md transition-colors whitespace-nowrap ${tab === key
                ? 'bg-blue-50 dark:bg-blue-900/20 text-blue-700 dark:text-blue-300 border-b-2 border-blue-500'
                : 'text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
              }`}
          >
            <Icon className="h-3.5 w-3.5" />
            <span className="hidden sm:inline">{label}</span>
          </button>
        ))}
      </div>

      {/* Tab content */}
      {tab === 'overview' && <RelayOverviewTab deviceId={filterDevice || undefined} />}
      {tab === 'events' && <RelayEventsTab deviceId={filterDevice || undefined} />}
      {tab === 'manifests' && <RelayManifestsTab />}
      {tab === 'packages' && <RelayPackagesTab deviceId={filterDevice || undefined} />}
      {tab === 'receipts' && <RelayReceiptsTab deviceId={filterDevice || undefined} />}
    </div>
  );
}

// ── Relay Overview Tab ──────────────────────────────────────────

function RelayOverviewTab({ deviceId }: { deviceId?: string }) {
  const { data: stats, isLoading } = useQuery({
    queryKey: ['relay-stats', deviceId],
    queryFn: () => getRelayStats(deviceId),
    retry: 1,
    staleTime: 15000,
  });

  if (isLoading) return <PageSpinner label="Loading stats..." />;
  if (!stats) return <p className="text-sm text-gray-500">No relay data available.</p>;

  const pendingReceipts = stats.receipts_by_status.find(r => r.acknowledged_by_origin === 0);
  const ackedReceipts = stats.receipts_by_status.find(r => r.acknowledged_by_origin === 1);

  return (
    <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
      {/* Relay events by type */}
      {stats.events_by_type.map((e) => (
        <div key={e.relay_type} className="p-3 bg-gray-50 dark:bg-gray-800/50 rounded-md">
          <div className="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wider">
            {e.relay_type}
          </div>
          <div className="text-lg font-bold text-gray-900 dark:text-gray-100">{e.cnt}</div>
          <div className="text-xs text-gray-400">
            {e.total_changes} changes &middot; {e.total_media} media
          </div>
        </div>
      ))}

      {/* Packages by status */}
      {stats.packages_by_status.map((p) => (
        <div key={p.status} className="p-3 bg-gray-50 dark:bg-gray-800/50 rounded-md">
          <div className="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wider">
            Pkg: {p.status}
          </div>
          <div className="text-lg font-bold text-gray-900 dark:text-gray-100">{p.cnt}</div>
        </div>
      ))}

      {/* Receipts */}
      <div className="p-3 bg-gray-50 dark:bg-gray-800/50 rounded-md">
        <div className="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wider">
          Pending Receipts
        </div>
        <div className="text-lg font-bold text-amber-600 dark:text-amber-400">
          {pendingReceipts?.cnt ?? 0}
        </div>
        <div className="text-xs text-gray-400">
          {pendingReceipts?.total_changes ?? 0} changes
        </div>
      </div>

      <div className="p-3 bg-gray-50 dark:bg-gray-800/50 rounded-md">
        <div className="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wider">
          Acknowledged
        </div>
        <div className="text-lg font-bold text-green-600 dark:text-green-400">
          {ackedReceipts?.cnt ?? 0}
        </div>
        <div className="text-xs text-gray-400">
          {ackedReceipts?.total_changes ?? 0} changes
        </div>
      </div>

      <div className="p-3 bg-gray-50 dark:bg-gray-800/50 rounded-md">
        <div className="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wider">
          Active Manifests
        </div>
        <div className="text-lg font-bold text-blue-600 dark:text-blue-400">
          {stats.active_manifests}
        </div>
        <div className="text-xs text-gray-400">devices carrying data</div>
      </div>
    </div>
  );
}

// ── Relay Events Tab ────────────────────────────────────────────

function RelayEventsTab({ deviceId }: { deviceId?: string }) {
  const { data: events, isLoading } = useQuery({
    queryKey: ['relay-events', deviceId],
    queryFn: () => getMeshRelayEvents(deviceId, 50),
    retry: 1,
    staleTime: 15000,
  });

  if (isLoading) return <PageSpinner label="Loading events..." />;
  if (!events?.length) {
    return <EmptyState icon={ArrowRightLeft} title="No Relay Events" description="No peer-to-peer relay activity recorded yet." />;
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="text-left text-xs text-gray-500 dark:text-gray-400 border-b border-border">
            <th className="pb-2 pr-3">Time</th>
            <th className="pb-2 pr-3">Source → Peer</th>
            <th className="pb-2 pr-3">Type</th>
            <th className="pb-2 pr-3">Changes</th>
            <th className="pb-2 pr-3">Media</th>
            <th className="pb-2">Undelivered</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-border">
          {events.map((e) => (
            <tr key={e.id}>
              <td className="py-1.5 pr-3 text-gray-700 dark:text-gray-300 whitespace-nowrap text-xs">
                {formatDate(e.recorded_at)}
              </td>
              <td className="py-1.5 pr-3 text-xs font-mono">
                <span className="text-blue-600 dark:text-blue-400">{truncateId(e.source_device_id)}</span>
                <span className="text-gray-400 mx-1">→</span>
                <span className="text-purple-600 dark:text-purple-400">{truncateId(e.peer_device_id)}</span>
              </td>
              <td className="py-1.5 pr-3">
                <Badge variant={relayTypeBadge(e.relay_type)}>{e.relay_type}</Badge>
              </td>
              <td className="py-1.5 pr-3 text-gray-700 dark:text-gray-300">{e.carried_change_count}</td>
              <td className="py-1.5 pr-3 text-gray-700 dark:text-gray-300">{e.carried_media_count}</td>
              <td className="py-1.5">
                {e.undelivered_after_count > 0 ? (
                  <Badge variant="warning">{e.undelivered_after_count}</Badge>
                ) : (
                  <span className="text-gray-400">0</span>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ── Relay Manifests Tab ─────────────────────────────────────────

function RelayManifestsTab() {
  const { data: manifests, isLoading } = useQuery({
    queryKey: ['relay-manifests'],
    queryFn: listRelayManifests,
    retry: 1,
    staleTime: 15000,
  });

  if (isLoading) return <PageSpinner label="Loading manifests..." />;
  if (!manifests?.length) {
    return <EmptyState icon={Radio} title="No Manifests" description="No devices have advertised relay data yet." />;
  }

  return (
    <div className="space-y-2">
      {manifests.map((m) => (
        <div key={m.device_id} className="p-3 bg-gray-50 dark:bg-gray-800/50 rounded-md">
          <div className="flex items-center justify-between">
            <span className="text-sm font-mono font-medium text-gray-900 dark:text-gray-100">
              {m.device_id}
            </span>
            <span className="text-xs text-gray-500 dark:text-gray-400">
              Updated {formatDate(m.updated_at)}
            </span>
          </div>
          <div className="flex flex-wrap gap-3 mt-1 text-xs text-gray-600 dark:text-gray-400">
            <span>
              <strong>{m.pending_change_count}</strong> pending changes
            </span>
            <span>
              <strong>{m.pending_media_count}</strong> pending media
            </span>
            {m.origin_device_ids.length > 0 && (
              <span>
                Origins: {m.origin_device_ids.map(truncateId).join(', ')}
              </span>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}

// ── Relay Packages Tab ──────────────────────────────────────────

function RelayPackagesTab({ deviceId }: { deviceId?: string }) {
  const { data: packages, isLoading } = useQuery({
    queryKey: ['relay-packages', deviceId],
    queryFn: () => listRelayPackages(deviceId, undefined, 50),
    retry: 1,
    staleTime: 15000,
  });

  if (isLoading) return <PageSpinner label="Loading packages..." />;
  if (!packages?.length) {
    return <EmptyState icon={Package} title="No Packages" description="No relay packages recorded yet." />;
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="text-left text-xs text-gray-500 dark:text-gray-400 border-b border-border">
            <th className="pb-2 pr-3">#</th>
            <th className="pb-2 pr-3">Sender → Receiver</th>
            <th className="pb-2 pr-3">Origin</th>
            <th className="pb-2 pr-3">Changes</th>
            <th className="pb-2 pr-3">Status</th>
            <th className="pb-2">Created</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-border">
          {packages.map((p) => (
            <tr key={p.id}>
              <td className="py-1.5 pr-3 text-gray-500 text-xs">{p.id}</td>
              <td className="py-1.5 pr-3 text-xs font-mono">
                <span className="text-blue-600 dark:text-blue-400">{truncateId(p.sender_device_id)}</span>
                <span className="text-gray-400 mx-1">→</span>
                <span className="text-purple-600 dark:text-purple-400">{truncateId(p.receiver_device_id)}</span>
              </td>
              <td className="py-1.5 pr-3 text-xs font-mono text-gray-600 dark:text-gray-400">
                {truncateId(p.origin_device_id)}
              </td>
              <td className="py-1.5 pr-3 text-gray-700 dark:text-gray-300">{p.change_count}</td>
              <td className="py-1.5 pr-3">
                <Badge variant={packageStatusBadge(p.status)}>{p.status}</Badge>
              </td>
              <td className="py-1.5 text-xs text-gray-500 whitespace-nowrap">
                {formatDate(p.created_at)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ── Relay Receipts Tab ──────────────────────────────────────────

function RelayReceiptsTab({ deviceId }: { deviceId?: string }) {
  const { data: receipts, isLoading } = useQuery({
    queryKey: ['relay-receipts', deviceId],
    queryFn: () => listDeliveryReceipts(deviceId, undefined, 50),
    retry: 1,
    staleTime: 15000,
  });

  if (isLoading) return <PageSpinner label="Loading receipts..." />;
  if (!receipts?.length) {
    return <EmptyState icon={FileCheck} title="No Receipts" description="No delivery receipts issued yet." />;
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="text-left text-xs text-gray-500 dark:text-gray-400 border-b border-border">
            <th className="pb-2 pr-3">#</th>
            <th className="pb-2 pr-3">Origin</th>
            <th className="pb-2 pr-3">Delivered By</th>
            <th className="pb-2 pr-3">Type</th>
            <th className="pb-2 pr-3">Changes</th>
            <th className="pb-2 pr-3">Status</th>
            <th className="pb-2">Issued</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-border">
          {receipts.map((r) => (
            <tr key={r.id}>
              <td className="py-1.5 pr-3 text-gray-500 text-xs">{r.id}</td>
              <td className="py-1.5 pr-3 text-xs font-mono text-blue-600 dark:text-blue-400">
                {truncateId(r.origin_device_id)}
              </td>
              <td className="py-1.5 pr-3 text-xs font-mono text-purple-600 dark:text-purple-400">
                {truncateId(r.delivered_by_device_id)}
              </td>
              <td className="py-1.5 pr-3">
                <Badge variant="neutral">{r.receipt_type}</Badge>
              </td>
              <td className="py-1.5 pr-3 text-gray-700 dark:text-gray-300">
                {r.change_count}{r.media_count > 0 ? ` + ${r.media_count} media` : ''}
              </td>
              <td className="py-1.5 pr-3">
                {r.acknowledged_by_origin ? (
                  <Badge variant="success">Acked</Badge>
                ) : (
                  <Badge variant="warning">Pending</Badge>
                )}
              </td>
              <td className="py-1.5 text-xs text-gray-500 whitespace-nowrap">
                {formatDate(r.issued_at)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
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

/** Truncate a UUID-style device ID for display → first 8 chars */
function truncateId(id: string): string {
  return id.length > 12 ? `${id.slice(0, 8)}…` : id;
}

/** Badge variant for relay event types */
function relayTypeBadge(type: string): 'success' | 'warning' | 'danger' | 'neutral' | 'default' {
  if (type === 'shop_ack') return 'success';
  if (type === 'shop_delivery') return 'success';
  if (type === 'gossip') return 'neutral';
  if (type === 'handoff') return 'warning';
  return 'default';
}

/** Badge variant for relay package status */
function packageStatusBadge(status: string): 'success' | 'warning' | 'danger' | 'neutral' | 'default' {
  if (status === 'confirmed') return 'success';
  if (status === 'transferred') return 'neutral';
  if (status === 'created') return 'warning';
  if (status === 'failed') return 'danger';
  return 'default';
}
