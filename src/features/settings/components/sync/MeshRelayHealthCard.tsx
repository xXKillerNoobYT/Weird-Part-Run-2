/**
 * MeshRelayHealthCard — tabbed relay health dashboard showing overview,
 * events, manifests, packages, and receipts.
 */

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  Radio, ArrowRightLeft, Activity, Package, FileCheck,
} from 'lucide-react';
import { Badge } from '../../../../components/ui/Badge';
import { PageSpinner } from '../../../../components/ui/Spinner';
import { EmptyState } from '../../../../components/ui/EmptyState';
import {
  listSyncDevices,
  getMeshRelayEvents,
  listRelayManifests,
  listRelayPackages,
  listDeliveryReceipts,
  getRelayStats,
} from '../../../../api/sync';
import {
  formatDate,
  truncateId,
  relayTypeBadge,
  packageStatusBadge,
} from './helpers';

type RelayTab = 'overview' | 'events' | 'manifests' | 'packages' | 'receipts';

export function MeshRelayHealthCard() {
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
