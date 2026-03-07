/**
 * SyncIndicator — header bar component showing sync state.
 *
 * Only renders in Capacitor mode (mobile devices).
 * Shows: synced, pending changes, syncing, or offline status.
 * Tapping opens a detail panel with sync info and manual sync button.
 */

import { useState, useEffect, useCallback } from 'react';
import {
  Cloud, CloudOff, RefreshCw, CheckCircle, AlertCircle,
} from 'lucide-react';
import { isCapacitor } from '../lib/environment';
import {
  getSyncState,
  onSyncStateChange,
  runSync,
  type SyncStatus,
} from '../local/sync-engine';

// Don't render anything in browser mode
export function SyncIndicator() {
  if (!isCapacitor()) return null;
  return <SyncIndicatorInner />;
}

function SyncIndicatorInner() {
  const [status, setStatus] = useState<SyncStatus>('idle');
  const [pendingCount, setPendingCount] = useState(0);
  const [lastSync, setLastSync] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [showDetail, setShowDetail] = useState(false);

  useEffect(() => {
    const state = getSyncState();
    setStatus(state.status);
    setPendingCount(state.pendingCount);
    setLastSync(state.lastSyncAt);
    setError(state.error);

    const unsub = onSyncStateChange((s) => {
      setStatus(s.status);
      setPendingCount(s.pendingCount);
      setLastSync(s.lastSyncAt);
      setError(s.error);
    });
    return unsub;
  }, []);

  const handleManualSync = useCallback(async () => {
    // Get device ID from Preferences
    try {
      const { Preferences } = await import('@capacitor/preferences');
      const result = await Preferences.get({ key: 'device_id' });
      if (result.value) {
        await runSync(result.value);
      }
    } catch (err) {
      console.error('Manual sync failed:', err);
    }
  }, []);

  const icon = getStatusIcon(status);
  const color = getStatusColor(status);
  const label = getStatusLabel(status, pendingCount);

  return (
    <>
      <button
        onClick={() => setShowDetail(!showDetail)}
        className={`flex items-center gap-1.5 px-2 py-1 rounded-md text-xs font-medium transition-colors ${color}`}
        title={label}
      >
        {icon}
        <span className="hidden sm:inline">{label}</span>
      </button>

      {/* Detail Panel */}
      {showDetail && (
        <div className="absolute right-0 top-full mt-1 w-72 bg-surface border border-border rounded-lg shadow-lg p-4 z-50">
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h4 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
                Sync Status
              </h4>
              <button
                onClick={() => setShowDetail(false)}
                className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
              >
                &times;
              </button>
            </div>

            <div className="flex items-center gap-2">
              {icon}
              <span className={`text-sm font-medium ${color}`}>{label}</span>
            </div>

            {lastSync && (
              <div className="text-xs text-gray-500 dark:text-gray-400">
                Last sync: {formatTime(lastSync)}
              </div>
            )}

            {pendingCount > 0 && (
              <div className="text-xs text-amber-600 dark:text-amber-400">
                {pendingCount} change{pendingCount !== 1 ? 's' : ''} pending
              </div>
            )}

            {error && (
              <div className="text-xs text-red-600 dark:text-red-400 bg-red-50 dark:bg-red-900/20 p-2 rounded">
                {error}
              </div>
            )}

            <button
              onClick={handleManualSync}
              disabled={status === 'syncing'}
              className="w-full flex items-center justify-center gap-2 px-3 py-2 text-sm font-medium bg-blue-50 dark:bg-blue-900/20 text-blue-700 dark:text-blue-300 rounded-md hover:bg-blue-100 dark:hover:bg-blue-900/30 disabled:opacity-50 transition-colors"
            >
              <RefreshCw className={`h-4 w-4 ${status === 'syncing' ? 'animate-spin' : ''}`} />
              {status === 'syncing' ? 'Syncing...' : 'Sync Now'}
            </button>
          </div>
        </div>
      )}
    </>
  );
}

function getStatusIcon(status: SyncStatus) {
  switch (status) {
    case 'synced':
      return <CheckCircle className="h-4 w-4 text-green-500" />;
    case 'syncing':
      return <RefreshCw className="h-4 w-4 text-blue-500 animate-spin" />;
    case 'offline':
      return <CloudOff className="h-4 w-4 text-red-500" />;
    case 'error':
      return <AlertCircle className="h-4 w-4 text-red-500" />;
    default:
      return <Cloud className="h-4 w-4 text-gray-400" />;
  }
}

function getStatusColor(status: SyncStatus): string {
  switch (status) {
    case 'synced':
      return 'text-green-600 dark:text-green-400';
    case 'syncing':
      return 'text-blue-600 dark:text-blue-400';
    case 'offline':
      return 'text-red-600 dark:text-red-400 bg-red-50 dark:bg-red-900/20';
    case 'error':
      return 'text-red-600 dark:text-red-400';
    default:
      return 'text-gray-500 dark:text-gray-400';
  }
}

function getStatusLabel(status: SyncStatus, pendingCount: number): string {
  switch (status) {
    case 'synced':
      return 'Synced';
    case 'syncing':
      return 'Syncing...';
    case 'offline':
      return pendingCount > 0
        ? `Offline (${pendingCount} pending)`
        : 'Offline';
    case 'error':
      return 'Sync Error';
    default:
      return pendingCount > 0 ? `${pendingCount} pending` : 'Idle';
  }
}

function formatTime(iso: string): string {
  try {
    const d = new Date(iso);
    const now = new Date();
    const diffMs = now.getTime() - d.getTime();
    const diffMin = Math.floor(diffMs / 60000);

    if (diffMin < 1) return 'Just now';
    if (diffMin < 60) return `${diffMin}m ago`;
    if (diffMin < 1440) return `${Math.floor(diffMin / 60)}h ago`;
    return d.toLocaleDateString();
  } catch {
    return iso;
  }
}
