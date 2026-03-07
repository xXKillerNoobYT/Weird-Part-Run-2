/**
 * Sync Status Indicator — shows sync state in the TopBar header.
 *
 * States:
 * - Synced (green dot) — all caught up
 * - Pending (yellow dot + count) — offline, changes queued
 * - Syncing (spinning icon) — actively syncing
 * - Error (red dot) — sync failed
 * - Offline (gray dot) — shop unreachable
 *
 * Tapping opens a detail panel with:
 * - Last sync time
 * - Pending changes count
 * - "Sync Now" button
 * - Error details
 *
 * Only renders in Capacitor mode — browser mode doesn't need sync.
 */

import { useState, useEffect, useCallback } from 'react';
import {
  RefreshCw, CheckCircle, AlertCircle, WifiOff, CloudOff,
  ChevronDown, X,
} from 'lucide-react';
import { isCapacitor } from '../../lib/environment';
import { getDeviceId } from '../../lib/device-identity';
import {
  getSyncState, onSyncStateChange, manualSync,
  type SyncState,
} from '../../local/sync-engine';

export function SyncStatusIndicator() {
  const [state, setState] = useState<SyncState>(getSyncState);
  const [showPanel, setShowPanel] = useState(false);
  const [isCap] = useState(() => isCapacitor());

  useEffect(() => {
    if (!isCap) return;
    return onSyncStateChange(setState);
  }, [isCap]);

  const handleSyncNow = useCallback(async () => {
    const deviceId = await getDeviceId();
    await manualSync(deviceId);
  }, []);

  // Don't render in browser mode
  if (!isCap) return null;

  const { status, pendingCount, lastSyncAt, error } = state;

  // Icon + color based on status
  let icon: React.ReactNode;
  let dotColor: string;
  let label: string;

  switch (status) {
    case 'synced':
      icon = <CheckCircle className="h-4 w-4" />;
      dotColor = 'text-green-500';
      label = 'Synced';
      break;
    case 'syncing':
      icon = <RefreshCw className="h-4 w-4 animate-spin" />;
      dotColor = 'text-blue-500';
      label = 'Syncing...';
      break;
    case 'offline':
      icon = <WifiOff className="h-4 w-4" />;
      dotColor = 'text-gray-400';
      label = pendingCount > 0 ? `${pendingCount} pending` : 'Offline';
      break;
    case 'error':
      icon = <AlertCircle className="h-4 w-4" />;
      dotColor = 'text-red-500';
      label = 'Sync error';
      break;
    default:
      icon = <CloudOff className="h-4 w-4" />;
      dotColor = 'text-gray-400';
      label = 'Idle';
  }

  return (
    <div className="relative">
      {/* Compact indicator button */}
      <button
        onClick={() => setShowPanel((p) => !p)}
        className={`
          flex items-center gap-1.5 px-2 py-1.5 rounded-lg
          text-sm font-medium transition-colors
          hover:bg-gray-100 dark:hover:bg-gray-700
          ${dotColor}
          min-h-[44px] min-w-[44px] justify-center
        `}
        title={label}
      >
        {icon}
        {/* Show pending badge on mobile */}
        {pendingCount > 0 && status !== 'syncing' && (
          <span className="hidden sm:inline text-xs">{pendingCount}</span>
        )}
        <ChevronDown className="h-3 w-3 hidden sm:block opacity-50" />
      </button>

      {/* Pending count badge (mobile — shows over the icon) */}
      {pendingCount > 0 && status !== 'syncing' && (
        <span className="sm:hidden absolute -top-1 -right-1 bg-yellow-500 text-white text-[10px] font-bold rounded-full h-4 min-w-4 px-1 flex items-center justify-center">
          {pendingCount > 99 ? '99+' : pendingCount}
        </span>
      )}

      {/* Detail panel (dropdown) */}
      {showPanel && (
        <>
          {/* Backdrop */}
          <div
            className="fixed inset-0 z-40"
            onClick={() => setShowPanel(false)}
          />

          {/* Panel */}
          <div className="absolute right-0 top-full mt-2 z-50 w-72 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl shadow-lg p-4">
            <div className="flex items-center justify-between mb-3">
              <h3 className="font-semibold text-gray-900 dark:text-gray-100">
                Sync Status
              </h3>
              <button
                onClick={() => setShowPanel(false)}
                className="p-1 rounded hover:bg-gray-100 dark:hover:bg-gray-700"
              >
                <X className="h-4 w-4 text-gray-400" />
              </button>
            </div>

            {/* Status row */}
            <div className={`flex items-center gap-2 mb-3 ${dotColor}`}>
              {icon}
              <span className="font-medium">{label}</span>
            </div>

            {/* Details */}
            <div className="space-y-2 text-sm text-gray-600 dark:text-gray-400">
              <div className="flex justify-between">
                <span>Last sync</span>
                <span className="text-gray-900 dark:text-gray-200">
                  {lastSyncAt ? formatRelativeTime(lastSyncAt) : 'Never'}
                </span>
              </div>
              <div className="flex justify-between">
                <span>Pending changes</span>
                <span className="text-gray-900 dark:text-gray-200">
                  {pendingCount}
                </span>
              </div>
              {state.consecutiveFailures > 0 && (
                <div className="flex justify-between">
                  <span>Failed attempts</span>
                  <span className="text-red-500">
                    {state.consecutiveFailures}
                  </span>
                </div>
              )}
            </div>

            {/* Error message */}
            {error && (
              <div className="mt-3 p-2 bg-red-50 dark:bg-red-900/20 rounded-lg text-xs text-red-600 dark:text-red-400">
                {error}
              </div>
            )}

            {/* Sync Now button */}
            <button
              onClick={handleSyncNow}
              disabled={status === 'syncing'}
              className="
                mt-4 w-full flex items-center justify-center gap-2
                px-4 py-2.5 rounded-lg font-medium text-sm
                bg-primary-600 text-white
                hover:bg-primary-700 disabled:opacity-50
                transition-colors min-h-[44px]
              "
            >
              <RefreshCw className={`h-4 w-4 ${status === 'syncing' ? 'animate-spin' : ''}`} />
              {status === 'syncing' ? 'Syncing...' : 'Sync Now'}
            </button>
          </div>
        </>
      )}
    </div>
  );
}

/** Format a timestamp as relative time (e.g. "2 min ago") */
function formatRelativeTime(isoString: string): string {
  const now = Date.now();
  const then = new Date(isoString).getTime();
  const diffMs = now - then;
  const diffSec = Math.floor(diffMs / 1000);
  const diffMin = Math.floor(diffSec / 60);
  const diffHr = Math.floor(diffMin / 60);

  if (diffSec < 30) return 'Just now';
  if (diffSec < 60) return `${diffSec}s ago`;
  if (diffMin < 60) return `${diffMin} min ago`;
  if (diffHr < 24) return `${diffHr}h ago`;
  return new Date(isoString).toLocaleDateString();
}
