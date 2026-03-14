/**
 * BluetoothSyncCard — Bluetooth sync status summary for Windows PCs.
 */

import { useQuery } from '@tanstack/react-query';
import {
  CheckCircle, AlertCircle, RefreshCw, Bluetooth,
} from 'lucide-react';
import { Badge } from '../../../../components/ui/Badge';
import { Link } from 'react-router-dom';
import {
  checkBtAvailability,
  getBtTunnelStatus,
  listPairedDevices,
} from '../../../../api/bluetooth';
import {
  BT_STATE_COLORS,
  BT_STATE_LABELS,
  formatBytesCompact,
  formatUptimeCompact,
} from './helpers';

export function BluetoothSyncCard() {
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
